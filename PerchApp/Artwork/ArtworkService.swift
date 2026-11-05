import Foundation
import Nuke
import Observation
import OSLog
import PerchCore
import PerchPlex
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

/// Sized, cached artwork for every screen (WP-08). Owns the one Nuke pipeline: memory cache (Nuke default)
/// and a 300 MB LRU disk cache in the App Group Caches. Cache keys are `server|path|size` or `public|url`
/// (ArtworkCacheKey), never the request URL, so an address change does not miss and no token reaches a key.
@MainActor @Observable
final class ArtworkService {
    nonisolated let pipeline: ImagePipeline
    nonisolated private let sources: [any ArtworkSource]
    @ObservationIgnored private let session: PlexSession
    @ObservationIgnored private let dataCache: DataCache?
    @ObservationIgnored private var observeTask: Task<Void, Never>?
    @ObservationIgnored private var lastWasSignedOut: Bool?

    /// The connected server's machine identifier; nil when not connected (views show the gradient).
    private(set) var serverID: String?

    nonisolated static let diskSizeLimit = 300 * 1024 * 1024
    nonisolated static let log = Logger(subsystem: "com.robrolabs.perch", category: "artwork")

    init(session: PlexSession, transport: any PlexTransport) {
        self.session = session
        sources = [PlexArtworkSource(session: session, transport: transport)]
        let cache = try? DataCache(path: Self.diskDirectory())
        cache?.sizeLimit = Self.diskSizeLimit
        dataCache = cache
        // Public images (plex.tv avatars) go through Nuke's loader: no URLCache, so this is the only disk copy.
        let loaderConfiguration = URLSessionConfiguration.default
        loaderConfiguration.urlCache = nil
        loaderConfiguration.timeoutIntervalForRequest = 15
        var configuration = ImagePipeline.Configuration(dataLoader: DataLoader(configuration: loaderConfiguration))
        configuration.dataCache = cache
        configuration.dataCachePolicy = .storeOriginalData
        pipeline = ImagePipeline(configuration: configuration)
        // So a view that forgets `.pipeline(_:)` still uses this cache, never a second one.
        ImagePipeline.shared = pipeline
        Self.removeLegacyCache()
    }

    // MARK: requests

    /// A request for a server image path at a size, or nil without a path or a connected server.
    func request(path: String?, size: ArtworkSize, priority: ImageRequest.Priority = .normal) -> ImageRequest? {
        guard let path, !path.isEmpty, let serverID else { return nil }
        return Self.serverRequest(serverID: serverID, path: path, size: size, sources: sources, priority: priority)
    }

    /// As `request`, but asks the session for the server when the observer has not caught up yet.
    func resolvedRequest(path: String?, size: ArtworkSize) async -> ImageRequest? {
        if serverID == nil { serverID = await session.currentServerID }
        return request(path: path, size: size)
    }

    /// A public absolute https image (plex.tv avatars): fetched plainly, keyed without its query.
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
        serverID: String, path: String, size: ArtworkSize, sources: [any ArtworkSource],
        priority: ImageRequest.Priority
    ) -> ImageRequest {
        ImageRequest(
            id: ArtworkCacheKey.server(serverID: serverID, path: path, size: size),
            data: {
                for source in sources {
                    guard let data = try await source.data(path: path, size: size) else { continue }
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

    func isCached(_ request: ImageRequest) -> Bool {
        pipeline.cache.containsCachedImage(for: request, caches: .all)
    }

    // MARK: lifetime

    /// Follows the session: a sign-out clears every cache. The first state seen at launch does not, since
    /// `resume()` has not run yet (as PlexLibrary.observe).
    func start() {
        observeTask?.cancel()
        let session = session
        observeTask = Task { [weak self] in
            let stream = await session.updates()
            let first = await session.snapshot().state
            let firstID = await session.currentServerID
            self?.sessionChanged(first, serverID: firstID)
            for await snapshot in stream {
                guard let self else { return }
                self.sessionChanged(snapshot.state, serverID: await session.currentServerID)
            }
        }
    }

    private func sessionChanged(_ state: PlexSessionState, serverID: String?) {
        let signedOut: Bool
        if case .signedOut = state { signedOut = true } else { signedOut = false }
        defer { lastWasSignedOut = signedOut }
        if signedOut, lastWasSignedOut == false {
            removeAll()
            Self.log.info("Artwork caches cleared after sign-out")
        }
        if self.serverID != serverID { self.serverID = serverID }
    }

    /// Clears the memory and disk caches and the remembered picker backdrop.
    func removeAll() {
        pipeline.cache.removeAll()
        dataCache?.flush()
        CoreServices.plexDefaults().removeObject(forKey: LibraryBackdrop.defaultsKey)
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

    /// For `-PerchResetSetup`, before any pipeline exists: both possible locations and the old cache.
    nonisolated static func removeDiskCache() {
        try? FileManager.default.removeItem(at: diskDirectory())
        try? FileManager.default.removeItem(at: appCaches().appending(path: "Artwork", directoryHint: .isDirectory))
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
