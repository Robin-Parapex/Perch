import Foundation
import Observation
import OSLog
import PerchCore
import PerchPlayer
import PerchPlex
import UIKit

/// Turns a library item into a running PlaybackSession and holds it while the player is on screen.
/// The root presents `activeSession` in a full-screen cover; the screen underneath stays alive.
@MainActor @Observable
final class PlaybackCoordinator {
    private(set) var activeSession: PlaybackSession?
    /// Set when playback could not start (refused, unreachable); cleared by the next `play`.
    var startError: String?
    /// "Next: S1, E4 · Title" once the session has been offered the next episode, for the still-watching overlay.
    private(set) var nextEpisodeLine: String?

    @ObservationIgnored private let library: PlexLibrary
    @ObservationIgnored private let plexSession: PlexSession
    @ObservationIgnored private let modules: ModuleRegistry
    @ObservationIgnored private let log: PlaybackLog
    /// Stored roles (Admin can change them); nil falls back to the Plex Home defaults for the profile.
    @ObservationIgnored private let settings: SettingsStore?
    @ObservationIgnored private var starting = false

    init(
        library: PlexLibrary, plexSession: PlexSession, modules: ModuleRegistry, logFileURL: URL,
        settings: SettingsStore? = nil
    ) {
        self.library = library
        self.plexSession = plexSession
        self.modules = modules
        self.settings = settings
        log = PlaybackLog(fileURL: logFileURL)
    }

    /// Failure copy (GLOSSARY "Couldn't play this", "Try again" for parents): the line under the title.
    nonisolated static let failureLineParent = "It may be a network hiccup. Try again, or come back later."
    nonisolated static let failureLineChild = "Ask a grown-up to try again."
    nonisolated static let failureLineOther = "Try again later, or ask a parent."

    /// Only parents may retry a failed playback; teens, kids and an unknown profile get Back only.
    /// Kids get the grown-up line; teens (and any other non-parent role) the "ask a parent" line.
    nonisolated static func failureCopy(for role: Role) -> (message: String, canRetry: Bool) {
        switch role {
        case .parent: (failureLineParent, true)
        case .kid: (failureLineChild, false)
        default: (failureLineOther, false)
        }
    }

    /// The playback log in the App Group Caches (the app's Caches when the group is not available).
    nonisolated static func logFileURL() -> URL {
        CoreServices.homeSnapshotsDirectory().deletingLastPathComponent()
            .appending(path: "playback-log.jsonl", directoryHint: .notDirectory)
    }

    /// Starts `item`, resuming at its saved offset unless `startMs` is given.
    func play(_ item: MediaSummary, startMs: Int? = nil) {
        guard activeSession == nil, !starting else { return }
        starting = true
        startError = nil
        Task {
            defer { starting = false }
            // The active Plex Home profile, for the log, the player hooks and what a failure may offer.
            let profile = await plexSession.currentProfile()
            let profileID = profile?.id.rawValue
            let role = await role(of: profile)
            do {
                let first = try await prepare(item, startMs: startMs ?? item.viewOffsetMs, profileID: profileID)
                activeSession = makeSession(first: first, item: item, profileID: profileID, role: role)
            } catch {
                startError = String(describing: error)
                Logger.playback.error("playback did not start: \(String(describing: error), privacy: .public)")
                // No decision was made, so no method is logged.
                await log.append(
                    PlaybackLogEntry(
                        profileID: profileID, ratingKey: item.id, title: Self.logTitle(for: item), outcome: .failure,
                        error: String(describing: error)))
            }
        }
    }

    /// The cover closed (Back, or the session finished).
    func dismissActive() {
        activeSession = nil
        nextEpisodeLine = nil
    }

    /// The profile's role as the rest of the app reads it: the stored setting, else the Plex Home default
    /// (owner and unrestricted users parent, restricted users kid). No profile means the strictest role.
    private func role(of profile: PlexActiveProfile?) async -> Role {
        guard let profile else { return .kid }
        if let settings, let stored = await settings.document.profiles[profile.id]?.role { return stored }
        return ProfileSettings.defaults(
            plexUserID: profile.id, displayName: profile.displayName, isOwner: profile.isOwner,
            restriction: profile.restriction
        ).role
    }

    // MARK: building

    /// Only the decision (which authorises the play) is waited for. The artwork is fetched alongside it and
    /// used only if it is already here; the timeline reporter starts in parallel with presentation and
    /// `engine.load`, behind a `DeferredReporter` that holds every report until it exists (same session ID).
    private func prepare(_ item: MediaSummary, startMs: Int?, profileID: String?) async throws -> PlaybackItem {
        let sessionID = UUID().uuidString
        let artwork = ArtworkBox()
        if let path = item.thumbPath {
            let plexSession = plexSession
            artwork.task = Task { @MainActor in artwork.data = try? await plexSession.imageData(for: path) }
        }
        var source = try await library.playbackSource(
            for: item.id, startMs: startMs, subtitleStreamID: nil, sessionID: sessionID)
        #if DEBUG
        source = Self.fakeSource(source)
        #endif
        source.title = Self.logTitle(for: item)
        let library = library
        let log = log
        let logTitle = source.title
        let ratingKey = item.id
        let reporterTask = Task { () async throws -> any PlaybackReporting in
            try await library.startPlayback(item: item, sessionID: sessionID)
        }
        var metadata = PlayerItemMetadata(title: Self.displayTitle(for: item), subtitle: Self.displaySubtitle(for: item))
        metadata.artworkData = artwork.data  // nil when it has not arrived: the info panel goes without
        return PlaybackItem(
            source: source, metadata: metadata,
            reporter: DeferredReporter(sessionID: sessionID, task: reporterTask) {
                // Feedback reports must show that the server saw no progress for this play. No raw error: it
                // may carry a host.
                await log.append(
                    PlaybackLogEntry(
                        profileID: profileID, ratingKey: ratingKey, title: logTitle, outcome: .failure,
                        error: DeferredReporter.notReportedLine))
            })
    }

    @MainActor private final class ArtworkBox {
        var data: Data?
        var task: Task<Void, Never>?
    }

    private func makeSession(first: PlaybackItem, item: MediaSummary, profileID: String?, role: Role) -> PlaybackSession {
        let library = library
        let log = log
        let current = CurrentItem(item)
        let failure = Self.failureCopy(for: role)
        let engine = NativeEngine()
        #if DEBUG
        let policy = Self.debugPolicy(.household)
        #else
        let policy = PlaybackPolicy.household
        #endif
        let session = PlaybackSession(
            engine: engine, source: first.source, metadata: first.metadata, policy: policy,
            reporter: first.reporter, hooks: modules.playerHooks, profileID: profileID,
            log: { entry in await log.append(entry) },
            nextItem: { [weak self] in
                guard let self else { return nil }
                guard let next = try? await library.nextEpisode(after: current.item) else {
                    current.pending = nil
                    self.nextEpisodeLine = nil
                    return nil
                }
                current.pending = next
                self.nextEpisodeLine = Self.nextLine(for: next)
                return await self.proposal(for: next)
            },
            resolveNext: { [weak self] proposal in
                guard let self, let next = current.pending, next.id == proposal.ratingKey else {
                    throw PlaybackCoordinatorError.noNext
                }
                #if DEBUG
                let startMs = Self.debugChainStartMs ?? 0
                #else
                let startMs = 0
                #endif
                let resolved: PlaybackItem
                do {
                    resolved = try await self.prepare(next, startMs: startMs, profileID: profileID)
                } catch PlexError.notAllowed {
                    // The session ends instead of offering a retry that would be refused again.
                    throw PlaybackNotAllowed()
                }
                current.item = next
                current.pending = nil
                return resolved
            },
            onTranscodeStop: { id in await library.stopTranscode(sessionID: id) },
            failureMessage: failure.message, canRetry: failure.canRetry)
        session.onFinished = { [weak self] in self?.dismissActive() }
        #if DEBUG
        Self.forceOverlayIfAsked(session)
        #endif
        return session
    }

    /// The item being played and the next episode the session was offered (the session's closures share it).
    @MainActor private final class CurrentItem {
        var item: MediaSummary
        var pending: MediaSummary?
        init(_ item: MediaSummary) { self.item = item }
    }

    private func proposal(for item: MediaSummary) async -> UpNextProposal {
        var image: Data?
        if let path = item.thumbPath { image = try? await plexSession.imageData(for: path) }
        return UpNextProposal(
            title: Self.displayTitle(for: item), subtitle: Self.displaySubtitle(for: item), previewImageData: image,
            ratingKey: item.id)
    }

    // MARK: one episode format everywhere: "S1, E6 · First Light"

    /// "S1, E6", or nil when the item is not an episode or lacks numbers.
    nonisolated static func episodeCode(for item: MediaSummary) -> String? {
        guard item.kind == .episode, let season = item.seasonNumber, let number = item.episodeNumber else { return nil }
        return "S\(season), E\(number)"
    }

    /// "S1, E6 · First Light" for an episode (the name alone without numbers).
    nonisolated static func episodeLine(for item: MediaSummary) -> String {
        [episodeCode(for: item), item.title].compactMap { $0 }.joined(separator: " · ")
    }

    /// Player title (AVKit's title and the info panel): the series for an episode, the title for a film.
    nonisolated static func displayTitle(for item: MediaSummary) -> String {
        item.kind == .episode ? (item.seriesTitle ?? item.title) : item.title
    }

    /// Player subtitle: "S1, E6 · First Light" for an episode, the year for a film.
    nonisolated static func displaySubtitle(for item: MediaSummary) -> String? {
        if item.kind == .episode { return item.seriesTitle == nil && episodeCode(for: item) == nil ? nil : episodeLine(for: item) }
        return item.year.map(String.init)
    }

    /// The still-watching context: "Next: S1, E6 · First Light".
    nonisolated static func nextLine(for item: MediaSummary) -> String { "Next: \(episodeLine(for: item))" }

    /// Playback log title: "The Lantern Keepers · S1, E6 · First Light"; a film by its title.
    nonisolated static func logTitle(for item: MediaSummary) -> String {
        guard item.kind == .episode else { return item.title }
        return [item.seriesTitle, episodeLine(for: item)].compactMap { $0 }.joined(separator: " · ")
    }

    #if DEBUG
    private static func argument(_ flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// `-PerchPolicy upNextCountdown=2,stillWatchingAfter=2`: shorter rules for the UI tests' real chain.
    private static func debugPolicy(_ base: PlaybackPolicy) -> PlaybackPolicy {
        guard let spec = argument("-PerchPolicy") else { return base }
        var policy = base
        for pair in spec.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let value = Int(parts[1]) else { continue }
            switch parts[0] {
            case "upNextCountdown": policy.upNextCountdownSeconds = value
            case "stillWatchingAfter": policy.stillWatchingAfter = value
            default: Logger.playback.error("unknown -PerchPolicy key \(parts[0], privacy: .public)")
            }
        }
        return policy
    }

    /// `-PerchChainStartMs <ms>`: where each next episode starts (normally 0), so a chain reaches its credits fast.
    private static var debugChainStartMs: Int? { argument("-PerchChainStartMs").flatMap(Int.init) }

    /// `-PerchForceOverlay stillWatching|failed`: the session raises that overlay shortly after playback starts.
    private static func forceOverlayIfAsked(_ session: PlaybackSession) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PerchForceOverlay"), arguments.indices.contains(index + 1)
        else { return }
        let failed = arguments[index + 1] == "failed"
        Task { @MainActor in
            for _ in 0..<100 where session.phase != .playing { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .seconds(2))
            // A failure goes through the session's real path, so the overlay shows the app's copy.
            if failed { session.debugFail() } else { session.debugRaiseOverlay(.stillWatching) }
        }
    }

    /// `-PerchFakeHousehold`: the fake server has no media, so play the bundled 60 s clip with no headers,
    /// keeping the item's markers and duration, and starting at 0 when the saved offset is past the clip.
    private static func fakeSource(_ source: PlaybackSource) -> PlaybackSource {
        guard ProcessInfo.processInfo.arguments.contains("-PerchFakeHousehold"),
            let url = Bundle.main.url(forResource: "PlayerSpikeClip", withExtension: "mp4")
        else { return source }
        var fake = source
        fake.url = url
        fake.headers = [:]
        fake.isTranscodeSession = false
        if fake.startMs >= 55_000 { fake.startMs = 0 }
        return fake
    }
    #endif
}

enum PlaybackCoordinatorError: Error { case noNext }

/// The Plex timeline reporter while `startPlayback` is still running: reports and the stop wait for it in
/// order (the session's outbox is serial, so playback never waits). If it fails, nothing is reported; the
/// play was already authorised by the decision call.
actor DeferredReporter: PlaybackReporting {
    /// The playback-log line when the reporter never started (no URLs, no codes).
    static let notReportedLine = "progress not reported: the timeline did not start"

    nonisolated let sessionID: String
    private let task: Task<any PlaybackReporting, any Error>
    private let onStartFailed: @Sendable () async -> Void
    private var resolved: (any PlaybackReporting)?
    private var failed = false

    init(
        sessionID: String, task: Task<any PlaybackReporting, any Error>,
        onStartFailed: @escaping @Sendable () async -> Void = {}
    ) {
        self.sessionID = sessionID
        self.task = task
        self.onStartFailed = onStartFailed
    }

    private func reporter() async -> (any PlaybackReporting)? {
        if let resolved { return resolved }
        if failed { return nil }
        do {
            let real = try await task.value
            resolved = real
            return real
        } catch {
            failed = true
            Logger.playback.error("timeline reporter did not start: \(String(describing: error), privacy: .public)")
            await onStartFailed()
            return nil
        }
    }

    func report(_ state: PlaybackState, positionMs: Int) async {
        await reporter()?.report(state, positionMs: positionMs)
    }

    func stop(positionMs: Int) async {
        await reporter()?.stop(positionMs: positionMs)
    }
}

extension Logger {
    static let playback = Logger(subsystem: "com.robrolabs.perch", category: "playback")
}
