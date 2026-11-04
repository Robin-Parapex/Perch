import Foundation
import PerchCore

/// Reports one playback to the Plex server. One reporter per playback; after `stop` it sends nothing.
/// One report in flight, newest pending replaces older, approach from Swiftfin (MPL-2.0).
/// Buffering repeats the last known time, approach from Dusk (MIT).
public actor PlexPlaybackReporter: PlaybackReporting {
    public nonisolated let sessionID: String

    private struct Pending {
        var state: PlaybackState
        var positionMs: Int
    }

    private let itemID: String
    private let durationMs: Int?
    private let context: PlexServerContext
    private let contextSource: any PlexServerContextProviding
    private let transport: any PlexTransport
    private let endpoints: PlexEndpoints
    private let watchState: PlexWatchState
    private let sink: (any PlexWatchStateSink)?
    private let interval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    private var lastQueuedState: PlaybackState?
    private var latest: Pending?
    private var lastGoodPosition: Int?
    private var pending: Pending?
    private var drainTask: Task<Void, Never>?
    private var loopTask: Task<Void, Never>?
    private var finished = false
    private var inert = false

    init(
        itemID: String, durationMs: Int?, sessionID: String?, context: PlexServerContext,
        contextSource: any PlexServerContextProviding, transport: any PlexTransport,
        endpoints: PlexEndpoints, watchState: PlexWatchState, sink: (any PlexWatchStateSink)?,
        interval: Duration = .seconds(10),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.itemID = itemID
        self.durationMs = durationMs
        self.sessionID = sessionID ?? UUID().uuidString
        self.context = context
        self.contextSource = contextSource
        self.transport = transport
        self.endpoints = endpoints
        self.watchState = watchState
        self.sink = sink
        self.interval = interval
        self.sleep = sleep
    }

    public func report(_ state: PlaybackState, positionMs: Int) async {
        guard !finished, !inert else { return }
        let position: Int
        if state == .buffering, let lastGoodPosition {
            position = lastGoodPosition
        } else {
            position = positionMs
            if state != .buffering { lastGoodPosition = positionMs }
        }
        latest = Pending(state: state, positionMs: position)
        startLoopIfNeeded()
        // Queued before any suspension, so the order of calls is the order of sends.
        let send = state != lastQueuedState
        if send { queue(Pending(state: state, positionMs: position)) }
        if send { await flush() }
    }

    public func stop(positionMs: Int) async {
        guard !finished, !inert else { return }
        finished = true
        loopTask?.cancel()
        loopTask = nil
        pending = nil
        queue(Pending(state: .stopped, positionMs: positionMs))
        await flush()
        guard !inert, let durationMs, durationMs > 0, positionMs <= durationMs,
            positionMs * 10 >= durationMs * 9
        else { return }
        guard await contextSource.currentGeneration() == context.generation else {
            goInert()
            return
        }
        do {
            try await watchState.setWatched(true, itemID: itemID, context: context)
            await sink?.watchStateChanged(itemID: itemID, watched: true, generation: context.generation)
        } catch {
            plexLog.error("Marking watched failed after stop")
        }
    }

    // MARK: sending

    private func queue(_ item: Pending) {
        pending = item
        lastQueuedState = item.state
    }

    /// Joins the running drain, or starts one, and returns when the queue is empty.
    private func flush() async {
        let task: Task<Void, Never>
        if let existing = drainTask {
            task = existing
        } else {
            task = Task { await self.drain() }
            drainTask = task
        }
        await task.value
    }

    private func drain() async {
        while let next = pending {
            pending = nil
            guard !inert else { break }
            guard await contextSource.currentGeneration() == context.generation else {
                goInert()
                break
            }
            let request = endpoints.timeline(
                base: context.baseURL, token: context.token, ratingKey: itemID, state: next.state,
                timeMs: next.positionMs, durationMs: durationMs, sessionID: sessionID)
            do {
                _ = try await transport.perform(request, host: .server)
                Self.logReport(next, outcome: "ok")
                // Accepted by the server; tell the sink only while this playback is still current.
                if await contextSource.currentGeneration() == context.generation {
                    await sink?.playbackProgressed(
                        PlaybackProgress(
                            itemID: itemID, state: next.state, positionMs: next.positionMs,
                            durationMs: durationMs),
                        generation: context.generation)
                }
            } catch {
                // perform has already logged the path and status; reporting never throws to the player.
                Self.logReport(next, outcome: "failed")
            }
        }
        drainTask = nil
    }

    /// One status line per report: state, position and outcome. Never the token, URL or session id.
    /// Info level (shown by `log show --info`); failures at error level.
    private static func logReport(_ item: Pending, outcome: String) {
        let seconds = item.positionMs / 1000
        if outcome == "ok" {
            plexLog.info("timeline state=\(item.state.rawValue, privacy: .public) pos=\(seconds, privacy: .public)s \(outcome, privacy: .public)")
        } else {
            plexLog.error("timeline state=\(item.state.rawValue, privacy: .public) pos=\(seconds, privacy: .public)s \(outcome, privacy: .public)")
        }
    }

    private func goInert() {
        inert = true
        pending = nil
        loopTask?.cancel()
        loopTask = nil
    }

    // MARK: periodic loop

    private func startLoopIfNeeded() {
        guard loopTask == nil else { return }
        let interval = interval
        let sleep = sleep
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await sleep(interval) } catch { return }
                guard let self, !Task.isCancelled else { return }
                await self.tick()
            }
        }
    }

    private func tick() async {
        guard !finished, !inert, let latest else { return }
        queue(latest)
        await flush()
    }
}
