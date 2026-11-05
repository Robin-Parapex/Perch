import Foundation
import Nuke
import Observation
import OSLog
import PerchCore
import PerchPlex
import Synchronization
import UIKit

/// One place artwork bytes can come from. Sources are tried in ARCHITECTURE.md:38 order (override,
/// fanart.tv, TMDB, Plex); a source returns nil when it has nothing and the next one is asked.
/// WP-08 ships the Plex source only.
protocol ArtworkSource: Sendable {
    var name: String { get }
    func data(path: String, size: ArtworkSize) async throws -> Data?
}

enum ArtworkError: Error {
    case notConnected
    case noSource
    /// The caches were cleared while this load was in flight; its bytes are dropped, never stored.
    case cleared
}

/// The connected Plex server's photo transcoder. The request is built at load time, so a background
/// address upgrade (WP-07) applies to the next load; the token stays in the header (PerchPlex).
struct PlexArtworkSource: ArtworkSource {
    let session: PlexSession
    let transport: any PlexTransport

    var name: String { "plex" }

    func data(path: String, size: ArtworkSize) async throws -> Data? {
        guard let request = await session.imageRequest(path: path, size: size) else { throw ArtworkError.notConnected }
        return try await transport.perform(request, host: .server)
    }
}

/// Sized, cached artwork for every screen (WP-08). Owns one Nuke pipeline: its own memory cache and a
/// 300 MB LRU disk cache in the App Group Caches. Cache keys are `server|path|size` or `public|url`
/// (ArtworkCacheKey), never the request URL, so an address change does not miss and no token reaches a key.
/// The server the cache belongs to is kept through connecting and offline states (ArtworkCachePolicy), so
/// cached art shows at launch, during a profile switch and without a server.
@MainActor @Observable
final class ArtworkService {
    nonisolated let pipeline: ImagePipeline
    nonisolated private let sources: [any ArtworkSource]
    nonisolated private let generation = Generation()
    @ObservationIgnored private let dataCache: DataCache?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let currentServerID: @Sendable () async -> String?
    @ObservationIgnored private var policy: ArtworkCachePolicy
    @ObservationIgnored private var observeTask: Task<Void, Never>?
    /// Called after every clear (CoreServices cancels prefetches and resets the page tint).
    @ObservationIgnored var onClear: (@MainActor () -> Void)?

    /// The server the cached images belong to; kept while connecting or offline, nil only after a sign-out
    /// (views show the gradient then).
    private(set) var serverID: String?

    nonisolated static let diskSizeLimit = 300 * 1024 * 1024
    nonisolated static let serverIDKey = "perch.artwork.serverID"
    nonisolated static let log = Logger(subsystem: "com.robrolabs.perch", category: "artwork")

    /// A counter bumped by every clear; a load that sees it change drops its bytes.
    final class Generation: Sendable {
        private let value = Mutex(0)
        var current: Int { value.withLock { $0 } }
        func bump() { value.withLock { $0 += 1 } }
    }

    /// The app's service: the Plex source, the App Group disk cache, the shared App Group defaults.
    convenience init(session: PlexSession, transport: any PlexTransport) {
        self.init(
            sources: [PlexArtworkSource(session: session, transport: transport)],
            diskDirectory: Self.diskDirectory(), defaults: CoreServices.plexDefaults(),
            currentServerID: { await session.currentServerID }, becomesShared: true)
    }

    init(
        sources: [any ArtworkSource], diskDirectory: URL, defaults: UserDefaults,
        currentServerID: @escaping @Sendable () async -> String?, becomesShared: Bool
    ) {
        self.sources = sources
        self.defaults = defaults
        self.currentServerID = currentServerID
        let saved = defaults.string(forKey: Self.serverIDKey)
        policy = ArtworkCachePolicy(savedServerID: saved)
        serverID = saved
        let cache = try? DataCache(path: diskDirectory)
        cache?.sizeLimit = Self.diskSizeLimit
        dataCache = cache
        // Public images (plex.tv avatars) go through Nuke's loader: no URLCache, so this is the only disk copy.
        let loaderConfiguration = URLSessionConfiguration.default
        loaderConfiguration.urlCache = nil
        loaderConfiguration.timeoutIntervalForRequest = 15
        var configuration = ImagePipeline.Configuration(dataLoader: DataLoader(configuration: loaderConfiguration))
        configuration.dataCache = cache
        configuration.imageCache = ImageCache()
        configuration.dataCachePolicy = .storeOriginalData
        pipeline = ImagePipeline(configuration: configuration)
        if becomesShared {
            // So a view that forgets `.pipeline(_:)` still uses this cache, never a second one.
            ImagePipeline.shared = pipeline
            Self.removeLegacyCache()
        }
    }

    // MARK: requests

    /// A request for a server image path at a size, or nil without a path or a known server.
    func request(path: String?, size: ArtworkSize, priority: ImageRequest.Priority = .normal) -> ImageRequest? {
        guard let path, !path.isEmpty, let serverID else { return nil }
        return Self.serverRequest(
            serverID: serverID, path: path, size: size, sources: sources, generation: generation, priority: priority)
    }

    /// The cache key a request for this path and size would use (the tint cache keys by it too).
    func cacheKey(path: String, size: ArtworkSize) -> String? {
        serverID.map { ArtworkCacheKey.server(serverID: $0, path: path, size: size) }
    }

    /// As `request`, but asks the session for the server when none is known yet (a first sign-in).
    func resolvedRequest(path: String?, size: ArtworkSize) async -> ImageRequest? {
        if serverID == nil, let id = await currentServerID() { observe(.ready(serverID: id)) }
        return request(path: path, size: size)
    }

    /// A public absolute https image (plex.tv avatars): fetched plainly, keyed without its query except `c`.
    func publicRequest(_ url: URL) -> ImageRequest? {
        guard let key = ArtworkCacheKey.publicImage(url) else { return nil }
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("image/*", forHTTPHeaderField: "Accept")
        return ImageRequest(urlRequest: urlRequest, userInfo: [.imageIdKey: key])
    }

    /// An avatar: a server path through the server, an https address as a public image.
    func avatarRequest(thumb: String?) async -> ImageRequest? {
        guard let thumb, !thumb.isEmpty else { return nil }
        if thumb.hasPrefix("/") { return await resolvedRequest(path: thumb, size: .poster) }
        return URL(string: thumb).flatMap(publicRequest)
    }

    nonisolated private static func serverRequest(
        serverID: String, path: String, size: ArtworkSize, sources: [any ArtworkSource], generation: Generation,
        priority: ImageRequest.Priority
    ) -> ImageRequest {
        ImageRequest(
            id: ArtworkCacheKey.server(serverID: serverID, path: path, size: size),
            data: {
                let started = generation.current
                for source in sources {
                    guard let data = try await source.data(path: path, size: size) else { continue }
                    // A clear while this was in flight: drop it, so nothing reaches the emptied caches.
                    guard generation.current == started else { throw ArtworkError.cleared }
                    log.info(
                        "Artwork loaded: \(size.rawValue, privacy: .public) \(data.count, privacy: .public) bytes from \(source.name, privacy: .public)"
                    )
                    return data
                }
                throw ArtworkError.noSource
            },
            priority: priority)
    }

    // MARK: loading

    func image(_ request: ImageRequest?) async -> UIImage? {
        guard let request else { return nil }
        return try? await pipeline.image(for: request)
    }

    /// Raw bytes (memory, then disk, then the source), for AVKit metadata that wants Data.
    func data(path: String?, size: ArtworkSize) async -> Data? {
        guard let request = await resolvedRequest(path: path, size: size) else { return nil }
        return try? await pipeline.data(for: request).0
    }

    /// Memory or disk only, decoded on the caller's thread; nil when not cached.
    func cachedImage(_ request: ImageRequest?) -> UIImage? {
        guard let request else { return nil }
        return pipeline.cache.cachedImage(for: request)?.image
    }

    /// Memory or disk only for a key saved earlier (the picker backdrop).
    func cachedImage(key: String) -> UIImage? {
        cachedImage(ImageRequest(id: key, data: { throw ArtworkError.noSource }))
    }

    // MARK: checks (unit tests, logs)

    enum CacheLayer { case memory, disk }

    /// Whether the image for a cache key is in one cache layer. The disk check touches the file system.
    func isCached(key: String, in layer: CacheLayer) -> Bool {
        let request = ImageRequest(id: key, data: { throw ArtworkError.noSource })
        return pipeline.cache.containsCachedImage(for: request, caches: layer == .memory ? .memory : .disk)
    }

    /// The decoded image for a server path, loading it when needed.
    func load(path: String, size: ArtworkSize) async -> UIImage? {
        await image(request(path: path, size: size))
    }

    /// The cache key a public image would use (`c` kept, the rest of the query dropped).
    func publicCacheKey(_ url: URL) -> String? { publicRequest(url).map(pipeline.cache.makeDataCacheKey) }

    /// Waits for staged disk writes and removals.
    func flushDisk() { dataCache?.flush() }

    // MARK: lifetime

    /// Follows the session: a sign-out clears every cache; the server ID is kept through connecting and
    /// offline states (ArtworkCachePolicy).
    func start(session: PlexSession) {
        observeTask?.cancel()
        observeTask = Task { [weak self] in
            let stream = await session.updates()
            let first = await session.snapshot().state
            let firstID = await session.currentServerID
            self?.observe(Self.policyState(first, serverID: firstID))
            for await snapshot in stream {
                let id = await session.currentServerID
                guard let self else { return }
                self.observe(Self.policyState(snapshot.state, serverID: id))
            }
        }
    }

    nonisolated private static func policyState(_ state: PlexSessionState, serverID: String?)
        -> ArtworkCachePolicy.SessionState
    {
        if case .signedOut = state { return .signedOut }
        if case .ready = state, let serverID { return .ready(serverID: serverID) }
        return .connecting
    }

    /// One session state through the policy: clears when it says so, keeps the server ID otherwise.
    func observe(_ state: ArtworkCachePolicy.SessionState) {
        if policy.observe(state) {
            removeAll()
            Self.log.info("Artwork caches cleared (sign-out or another server)")
        }
        setServerID(policy.serverID)
    }

    /// An explicit sign-out from the app (PlexSignInModel), straight after the session forgot its tokens.
    func signedOut() {
        policy.signedOut()
        removeAll()
        setServerID(nil)
        Self.log.info("Artwork caches cleared after sign-out")
    }

    /// Clears the memory and disk caches and the remembered picker backdrop. Loads still in flight drop
    /// their bytes (generation check), so nothing from before the clear is stored after it.
    func removeAll() {
        generation.bump()
        pipeline.cache.removeAll()
        dataCache?.flush()
        defaults.removeObject(forKey: LibraryBackdrop.defaultsKey)
        onClear?()
    }

    private func setServerID(_ id: String?) {
        if serverID != id { serverID = id }
        if defaults.string(forKey: Self.serverIDKey) != id { defaults.set(id, forKey: Self.serverIDKey) }
    }

    // MARK: disk

    /// App Group `Library/Caches/Artwork`, or the app's own Caches when the group is not available.
    nonisolated static func diskDirectory() -> URL {
        let base =
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PerchConstants.appGroupID)?
            .appending(path: "Library/Caches", directoryHint: .isDirectory)
            ?? appCaches()
        return base.appending(path: "Artwork", directoryHint: .isDirectory)
    }

    /// For `-PerchResetSetup` and `-PerchClearArtwork`, before any pipeline exists: both possible locations,
    /// the old cache and the remembered picker backdrop.
    nonisolated static func removeDiskCache() {
        try? FileManager.default.removeItem(at: diskDirectory())
        try? FileManager.default.removeItem(at: appCaches().appending(path: "Artwork", directoryHint: .isDirectory))
        CoreServices.plexDefaults().removeObject(forKey: LibraryBackdrop.defaultsKey)
        removeLegacyCache()
    }

    /// The WP-05 ImageDiskCache folder, replaced by this service.
    nonisolated private static func removeLegacyCache() {
        let legacy = appCaches().appending(path: "PerchImages", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: legacy.path) { try? FileManager.default.removeItem(at: legacy) }
    }

    nonisolated private static func appCaches() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }
}
