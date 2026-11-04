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
    @ObservationIgnored private var starting = false

    init(library: PlexLibrary, plexSession: PlexSession, modules: ModuleRegistry, logFileURL: URL) {
        self.library = library
        self.plexSession = plexSession
        self.modules = modules
        log = PlaybackLog(fileURL: logFileURL)
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
            do {
                let first = try await prepare(item, startMs: startMs ?? item.viewOffsetMs)
                activeSession = makeSession(first: first, item: item)
            } catch {
                startError = String(describing: error)
                Logger.playback.error("playback did not start: \(String(describing: error), privacy: .public)")
                await log.append(
                    PlaybackLogEntry(
                        ratingKey: item.id, title: item.title, method: .directPlay, outcome: .failure,
                        error: String(describing: error)))
            }
        }
    }

    /// The cover closed (Back, or the session finished).
    func dismissActive() {
        activeSession = nil
        nextEpisodeLine = nil
    }

    // MARK: building

    private func prepare(_ item: MediaSummary, startMs: Int?) async throws -> PlaybackItem {
        let sessionID = UUID().uuidString
        var source = try await library.playbackSource(
            for: item.id, startMs: startMs, subtitleStreamID: nil, sessionID: sessionID)
        #if DEBUG
        source = Self.fakeSource(source)
        #endif
        let reporter = try await library.startPlayback(item: item, sessionID: sessionID)
        return PlaybackItem(source: source, metadata: await metadata(for: item), reporter: reporter)
    }

    private func makeSession(first: PlaybackItem, item: MediaSummary) -> PlaybackSession {
        let library = library
        let log = log
        let current = CurrentItem(item)
        let engine = NativeEngine()
        let session = PlaybackSession(
            engine: engine, source: first.source, metadata: first.metadata, policy: .household,
            reporter: first.reporter, hooks: modules.playerHooks,
            log: { entry in await log.append(entry) },
            nextItem: { [weak self] in
                guard let self, let next = try? await library.nextEpisode(after: current.item) else { return nil }
                current.pending = next
                self.nextEpisodeLine = Self.nextLine(for: next)
                return await self.proposal(for: next)
            },
            resolveNext: { [weak self] proposal in
                guard let self, let next = current.pending, next.id == proposal.ratingKey else {
                    throw PlaybackCoordinatorError.noNext
                }
                let resolved = try await self.prepare(next, startMs: 0)
                current.item = next
                current.pending = nil
                return resolved
            },
            onTranscodeStop: { id in await library.stopTranscode(sessionID: id) })
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

    private func metadata(for item: MediaSummary) async -> PlayerItemMetadata {
        var data = PlayerItemMetadata(title: item.title, subtitle: Self.subtitle(for: item))
        if let path = item.thumbPath { data.artworkData = try? await plexSession.imageData(for: path) }
        return data
    }

    private func proposal(for item: MediaSummary) async -> UpNextProposal {
        var image: Data?
        if let path = item.thumbPath { image = try? await plexSession.imageData(for: path) }
        return UpNextProposal(
            title: item.title, subtitle: Self.subtitle(for: item), previewImageData: image, ratingKey: item.id)
    }

    private static func nextLine(for item: MediaSummary) -> String {
        guard let season = item.seasonNumber, let number = item.episodeNumber else { return "Next: \(item.title)" }
        return "Next: S\(season), E\(number) · \(item.title)"
    }

    private static func subtitle(for item: MediaSummary) -> String? {
        guard item.kind == .episode else { return nil }
        var code: String?
        if let season = item.seasonNumber, let number = item.episodeNumber { code = "S\(season) E\(number)" }
        let parts = [item.seriesTitle, code].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    #if DEBUG
    /// `-PerchForceOverlay stillWatching|failed`: the session raises that overlay shortly after playback starts.
    private static func forceOverlayIfAsked(_ session: PlaybackSession) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PerchForceOverlay"), arguments.indices.contains(index + 1)
        else { return }
        let request: PlayerOverlayRequest =
            arguments[index + 1] == "failed"
            ? .playbackFailed(message: "Something went wrong while playing. Check the connection and try again.")
            : .stillWatching
        Task { @MainActor in
            for _ in 0..<100 where session.phase != .playing { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .seconds(2))
            session.debugRaiseOverlay(request)
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

extension Logger {
    static let playback = Logger(subsystem: "com.robrolabs.perch", category: "playback")
}
