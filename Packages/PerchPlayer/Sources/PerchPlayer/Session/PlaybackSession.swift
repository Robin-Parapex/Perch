import Foundation
import Observation
import PerchCore

/// A full-screen overlay the app must render above the player. `playbackFailed` carries the app's own
/// family-facing line (`PlaybackSession.failureMessage`), never the engine's error text: that goes, scrubbed,
/// to the playback log only.
public enum PlayerOverlayRequest: Sendable, Equatable {
    case stillWatching
    case playbackFailed(message: String)
}

/// One item ready to play: what to open, what to show, and its own reporter (one per playback).
public struct PlaybackItem: Sendable {
    public var source: PlaybackSource
    public var metadata: PlayerItemMetadata
    public var reporter: any PlaybackReporting

    public init(source: PlaybackSource, metadata: PlayerItemMetadata, reporter: any PlaybackReporting) {
        self.source = source
        self.metadata = metadata
        self.reporter = reporter
    }
}

/// Drives one stretch of playback (possibly several items in a row) through an engine: start and stop
/// logging, timeline reports, player hooks, Skip offers and up next from the rules, the end-of-item
/// action, and overlay requests the app renders. Engine-agnostic.
@MainActor
@Observable
public final class PlaybackSession {
    public enum Phase: Sendable, Equatable {
        case idle, loading, playing, paused, buffering, ended, failed, finished
    }

    public private(set) var phase: Phase = .idle
    public private(set) var source: PlaybackSource
    public private(set) var metadata: PlayerItemMetadata
    public private(set) var positionMs: Int
    public private(set) var skipOffer: SkipOffer?
    /// The proposal on screen and its mode, nil when none.
    public private(set) var upNextShown: UpNextProposal?
    public private(set) var upNextMode: UpNextMode?
    public private(set) var overlayRequest: PlayerOverlayRequest?
    /// Items started in this session (1 for the first).
    public private(set) var itemsStarted = 0
    public private(set) var skipsTaken = 0
    public private(set) var automaticAdvances = 0
    public var autoChainCount: Int { counter.count }

    public let engine: any PlaybackEngine
    /// The line under "Couldn't Play This", supplied by the app (GLOSSARY: no codes, links or service names).
    public let failureMessage: String
    /// Whether "Try Again" is allowed for the active profile (parents only, GLOSSARY). `retry()` refuses
    /// otherwise, whatever the overlay shows.
    public let canRetry: Bool
    /// Called once when the session ends (Back, stop at the end, "stop watching").
    @ObservationIgnored public var onFinished: (() -> Void)?
    /// Called whenever `overlayRequest` changes (the container shows or hides the overlay window).
    @ObservationIgnored public var onOverlayRequestChange: ((PlayerOverlayRequest?) -> Void)?

    private let policy: PlaybackPolicy
    @ObservationIgnored private var reporter: any PlaybackReporting
    private let hooks: [any PlayerHook]
    private let profileID: String?
    private let logSink: @Sendable (PlaybackLogEntry) async -> Void
    private let nextItem: @MainActor () async -> UpNextProposal?
    private let resolveNext: @MainActor (UpNextProposal) async throws -> PlaybackItem
    private let onTranscodeStop: @Sendable (String) async -> Void
    private let sleep: @Sendable (Duration) async throws -> Void

    @ObservationIgnored private var counter = AutoChainCounter()
    @ObservationIgnored private var skipRules: SkipRules
    @ObservationIgnored private var upNextRules: UpNextRules?
    @ObservationIgnored private var upNextDismissed = false
    @ObservationIgnored private var nextProposal: UpNextProposal?
    @ObservationIgnored private var nextTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var autoSkipTask: Task<Void, Never>?
    @ObservationIgnored private var loadStartedAt: ContinuousClock.Instant?
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var isTransitioning = false
    @ObservationIgnored private var itemStopped = false
    @ObservationIgnored private var creditsSent = false
    private let outbox: AsyncStream<@Sendable () async -> Void>.Continuation
    private let outboxTask: Task<Void, Never>

    public init(
        engine: any PlaybackEngine, source: PlaybackSource, metadata: PlayerItemMetadata,
        policy: PlaybackPolicy = .household, reporter: any PlaybackReporting,
        hooks: [any PlayerHook] = [], profileID: String? = nil,
        log: @escaping @Sendable (PlaybackLogEntry) async -> Void,
        nextItem: @escaping @MainActor () async -> UpNextProposal?,
        resolveNext: @escaping @MainActor (UpNextProposal) async throws -> PlaybackItem,
        onTranscodeStop: @escaping @Sendable (String) async -> Void,
        failureMessage: String = PlaybackSession.defaultFailureMessage, canRetry: Bool = true,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.engine = engine
        self.failureMessage = failureMessage
        self.canRetry = canRetry
        self.source = source
        self.metadata = metadata
        self.policy = policy
        self.reporter = reporter
        self.hooks = hooks
        self.profileID = profileID
        self.logSink = log
        self.nextItem = nextItem
        self.resolveNext = resolveNext
        self.onTranscodeStop = onTranscodeStop
        self.sleep = sleep
        positionMs = source.startMs
        skipRules = SkipRules(markers: source.markers, durationMs: source.durationMs, policy: policy)
        // Reports, hooks and log writes run in order on one queue, so slow I/O never stalls playback.
        let (stream, continuation) = AsyncStream.makeStream(of: (@Sendable () async -> Void).self)
        outbox = continuation
        outboxTask = Task {
            for await work in stream { await work() }
        }
    }

    deinit {
        // Never exited (dropped before start): let the outbox drain and end.
        outbox.finish()
    }

    // MARK: lifecycle

    /// Starts the first item. Call once, when the engine's view is in a window.
    public func start() {
        guard phase == .idle else { return }
        let events = engine.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
        Task { await loadCurrent() }
    }

    /// Back, or the end of the session: report stop, log, stop a transcode, tear the engine down.
    public func exit() async {
        guard phase != .finished else { return }
        let position = currentPosition
        phase = .finished
        eventTask?.cancel()
        autoSkipTask?.cancel()
        nextTask?.cancel()
        engine.teardown()
        setOverlay(nil)
        onFinished?()
        onFinished = nil
        stopCurrentItem(at: position)
        await settle()
        outbox.finish()
    }

    /// "Are you still watching?" answered yes: play the next item.
    public func continueWatching() {
        guard overlayRequest == .stillWatching else { return }
        setOverlay(nil)
        counter.userInput()
        guard let next = nextProposal else {
            Task { await exit() }
            return
        }
        Task { await advance(to: next) }
    }

    /// "Are you still watching?" answered no, or the failure overlay closed.
    public func stopWatching() {
        setOverlay(nil)
        Task { await exit() }
    }

    /// Fallback for `failureMessage` when the app supplies none.
    public static let defaultFailureMessage = "It may be a network hiccup. Try again, or come back later."

    /// Try the current item again from where it stopped. Refused when the profile may not retry.
    public func retry() {
        guard case .playbackFailed = overlayRequest, canRetry else { return }
        setOverlay(nil)
        source.startMs = positionMs
        Task { await loadCurrent() }
    }

    /// Waits until every queued report, hook call and log write has run (tests, exit).
    func settle() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let result = outbox.yield { done.resume() }
            if case .terminated = result { done.resume() }
        }
    }

    // MARK: items

    private func loadCurrent() async {
        guard phase != .finished else { return }
        phase = .loading
        resetItemState()
        itemsStarted += 1
        fetchNext()
        loadStartedAt = .now
        do {
            try await engine.load(source, metadata: metadata)
        } catch {
            guard phase != .finished else { return }
            if error is CancellationError { return }
            fail(String(describing: error))
            return
        }
        guard phase == .loading else { return }
        engine.play()
    }

    private func resetItemState() {
        autoSkipTask?.cancel()
        nextTask?.cancel()
        skipRules = SkipRules(markers: source.markers, durationMs: source.durationMs, policy: policy)
        upNextRules = nil
        upNextDismissed = false
        nextProposal = nil
        skipOffer = nil
        upNextShown = nil
        upNextMode = nil
        creditsSent = false
        itemStopped = false
        positionMs = source.startMs
    }

    private func fetchNext() {
        nextTask = Task { [weak self] in
            guard let self else { return }
            let proposal = await self.nextItem()
            guard !Task.isCancelled else { return }
            self.nextProposal = proposal
            self.rebuildUpNextRules()
            if self.phase == .playing || self.phase == .paused { self.evaluate() }
        }
    }

    private func rebuildUpNextRules() {
        var rules = UpNextRules(
            markers: source.markers, durationMs: source.durationMs, hasNext: nextProposal != nil,
            policy: policy, autoChainCount: counter.count)
        if upNextDismissed { rules.dismiss() }
        upNextRules = rules
    }

    private func advance(to proposal: UpNextProposal) async {
        guard !isTransitioning, phase != .finished else { return }
        isTransitioning = true
        defer { isTransitioning = false }
        stopCurrentItem(at: currentPosition)
        engine.showSkip(nil, onSkip: {})
        engine.showUpNext(nil, mode: .manual, onAccept: { _ in }, onDismiss: {})
        do {
            let item = try await resolveNext(proposal)
            guard phase != .finished else { return }
            source = item.source
            metadata = item.metadata
            reporter = item.reporter
        } catch {
            guard phase != .finished else { return }
            fail(String(describing: error))
            return
        }
        await loadCurrent()
    }

    /// Reports stop, logs it, tells hooks and stops a transcode; once per item.
    private func stopCurrentItem(at position: Int) {
        guard !itemStopped, itemsStarted > 0 else { return }
        itemStopped = true
        let reporter = reporter
        let logEntry = entry(.stop, positionMs: position)
        let transcodeID = source.isTranscodeSession ? source.sessionID : nil
        let onTranscodeStop = onTranscodeStop
        let logSink = logSink
        enqueue {
            await reporter.stop(positionMs: position)
            await logSink(logEntry)
        }
        sendHook(.stop, at: position)
        if let transcodeID { enqueue { await onTranscodeStop(transcodeID) } }
    }

    // MARK: events

    private func handle(_ event: EngineEvent) async {
        guard phase != .finished else { return }
        switch event {
        case .playing:
            guard phase != .failed, phase != .ended else { return }
            if let started = loadStartedAt {
                loadStartedAt = nil
                let ms = Int((started.duration(to: .now) / .milliseconds(1)).rounded())
                enqueueLog(entry(.start, positionMs: currentPosition, startLatencyMs: ms))
            }
            phase = .playing
            report(.playing)
            sendHook(.play, at: currentPosition)
        case .paused:
            guard phase == .playing || phase == .buffering else { return }
            phase = .paused
            report(.paused)
            sendHook(.pause, at: currentPosition)
        case .buffering:
            guard phase == .playing || phase == .paused else { return }
            phase = .buffering
            report(.buffering)
        case .positionTick(let ms):
            guard phase != .loading || loadStartedAt == nil else { return }
            positionMs = ms
            reportPosition(ms)
            evaluate()
        case .ended:
            guard phase != .loading, phase != .failed else { return }
            await handleEnd()
        case .failed(let message):
            fail(message)
        case .userInput:
            counter.userInput()
            if nextProposal != nil, upNextRules != nil { rebuildUpNextRules() }
        }
    }

    private func evaluate() {
        let position = positionMs
        let offer = skipRules.offer(atMs: position, isSeeking: isSeeking)
        if offer != skipOffer {
            let previous = skipOffer
            skipOffer = offer
            engine.showSkip(offer) { [weak self] in self?.takeSkip() }
            if offer?.markerID != previous?.markerID || offer?.autoSkipAfterSeconds == nil {
                autoSkipTask?.cancel()
                autoSkipTask = nil
            }
            if let offer, let seconds = offer.autoSkipAfterSeconds, autoSkipTask == nil {
                autoSkipTask = Task { [weak self, sleep = self.sleep] in
                    do { try await sleep(.seconds(seconds)) } catch { return }
                    guard let self, !Task.isCancelled, self.skipOffer?.markerID == offer.markerID else { return }
                    await self.performSkip(offer)
                }
            }
        }

        guard var rules = upNextRules else { return }
        let upNextPhase = rules.phase(atMs: position)
        upNextRules = rules
        // The credits hook fires on reaching the final credits, also when no proposal shows (chain limit).
        if !creditsSent, let start = rules.creditsStartMs, position >= start {
            creditsSent = true
            sendHook(.credits, at: position)
        }
        switch upNextPhase {
        case .proposed(let mode):
            guard upNextShown == nil, let proposal = nextProposal, !isTransitioning else { return }
            upNextShown = proposal
            upNextMode = mode
            engine.showUpNext(
                proposal, mode: mode,
                onAccept: { [weak self] acceptance in self?.acceptUpNext(acceptance) },
                onDismiss: { [weak self] in self?.dismissUpNext() })
        case .idle:
            guard upNextShown != nil else { return }
            upNextShown = nil
            upNextMode = nil
            engine.showUpNext(nil, mode: .manual, onAccept: { _ in }, onDismiss: {})
        case .dismissed:
            break
        }
    }

    private func takeSkip() {
        guard let offer = skipOffer else { return }
        counter.userInput()
        Task { await performSkip(offer) }
    }

    private func performSkip(_ offer: SkipOffer) async {
        skipRules.markSpent(offer.markerID)
        autoSkipTask?.cancel()
        autoSkipTask = nil
        skipsTaken += 1
        isSeeking = true
        await engine.seek(toMs: offer.targetMs)
        isSeeking = false
        guard phase != .finished else { return }
        positionMs = offer.targetMs
        evaluate()
    }

    private func acceptUpNext(_ acceptance: UpNextAcceptance) {
        guard let proposal = upNextShown ?? nextProposal else { return }
        upNextShown = nil
        upNextMode = nil
        switch acceptance {
        case .user: counter.userInput()
        case .countdown:
            counter.automaticAdvance()
            automaticAdvances += 1
        }
        Task { await advance(to: proposal) }
    }

    private func withdrawUpNext() {
        guard upNextShown != nil else { return }
        upNextShown = nil
        upNextMode = nil
        engine.showUpNext(nil, mode: .manual, onAccept: { _ in }, onDismiss: {})
    }

    private func dismissUpNext() {
        upNextDismissed = true
        upNextRules?.dismiss()
        upNextShown = nil
        upNextMode = nil
    }

    private func handleEnd() async {
        guard !isTransitioning else { return }
        phase = .ended
        report(.paused)
        engine.showSkip(nil, onSkip: {})
        skipOffer = nil
        if upNextRules == nil { await nextTask?.value }
        guard phase == .ended else { return }
        let action = upNextRules?.endAction() ?? .stop
        switch action {
        case .advance:
            guard let next = nextProposal else {
                await exit()
                return
            }
            counter.automaticAdvance()
            automaticAdvances += 1
            await advance(to: next)
        case .stillWatching:
            // Only our prompt: never a proposal underneath it.
            withdrawUpNext()
            setOverlay(.stillWatching)
        case .stop:
            await exit()
        }
    }

    /// The raw error is scrubbed and kept for the log and the hooks; the overlay gets the app's line only.
    private func fail(_ raw: String) {
        guard phase != .finished else { return }
        let message = scrub(raw)
        phase = .failed
        autoSkipTask?.cancel()
        engine.showSkip(nil, onSkip: {})
        skipOffer = nil
        withdrawUpNext()
        enqueueLog(entry(.failure, positionMs: currentPosition, error: message))
        sendHook(.failure(message), at: currentPosition)
        setOverlay(.playbackFailed(message: failureMessage))
    }

    // MARK: outputs

    private var currentPosition: Int {
        let live = engine.positionMs
        return live > 0 ? live : positionMs
    }

    #if DEBUG
    /// UI tests (`-PerchForceOverlay`): raise an overlay as if the rules or the engine had asked for it.
    public func debugRaiseOverlay(_ request: PlayerOverlayRequest) { setOverlay(request) }

    /// UI tests (`-PerchForceOverlay failed`): fail as if the engine had, through the real failure path.
    public func debugFail() { fail("forced failure (debug)") }

    /// Unit tests: set the chain count mid-item (unreachable in use) to prove a shown proposal is withdrawn.
    func setAutoChainCountForTesting(_ count: Int) {
        counter = AutoChainCounter(count: count)
        if upNextRules != nil { rebuildUpNextRules() }
    }
    #endif

    private func setOverlay(_ request: PlayerOverlayRequest?) {
        guard overlayRequest != request else { return }
        overlayRequest = request
        // Raising: the overlay window takes key and focus first, then the engine's chrome goes (hiding it
        // first left focus nowhere). Clearing: the chrome comes back first, so the container has something
        // to focus when the window hands key back. Never after exit (the engine is torn down).
        let live = phase != .finished
        if request == nil, live { engine.setNativeChromeHidden(false) }
        onOverlayRequestChange?(request)
        if request != nil, live { engine.setNativeChromeHidden(true) }
    }

    /// Every tick refreshes the reporter's position for the current state. The reporter sends on a state
    /// change and otherwise resends its latest value on its own cadence, so without this the server keeps
    /// seeing the position of the last state change.
    private func reportPosition(_ ms: Int) {
        let state: PlaybackState
        switch phase {
        case .playing: state = .playing
        case .paused: state = .paused
        case .buffering: state = .buffering
        default: return
        }
        let reporter = reporter
        enqueue { await reporter.report(state, positionMs: ms) }
    }

    private func report(_ state: PlaybackState) {
        let reporter = reporter
        let position = state == .buffering ? positionMs : currentPosition
        enqueue { await reporter.report(state, positionMs: position) }
    }

    private func sendHook(_ event: PlayerEvent, at position: Int) {
        guard !hooks.isEmpty else { return }
        let hooks = hooks
        let context = PlayerEventContext(
            ratingKey: source.ratingKey, profileID: profileID, positionMs: position,
            durationMs: source.durationMs, sessionID: source.sessionID)
        enqueue {
            for hook in hooks { await hook.handle(event, context: context) }
        }
    }

    private func enqueueLog(_ entry: PlaybackLogEntry) {
        let logSink = logSink
        enqueue { await logSink(entry) }
    }

    private func enqueue(_ work: @escaping @Sendable () async -> Void) {
        outbox.yield(work)
    }

    private func entry(
        _ outcome: PlaybackLogEntry.Outcome, positionMs: Int, startLatencyMs: Int? = nil, error: String? = nil
    ) -> PlaybackLogEntry {
        PlaybackLogEntry(
            profileID: profileID, ratingKey: source.ratingKey, title: source.title,
            method: source.decision.method, reasons: source.decision.reasons, notes: source.decision.notes,
            engine: engine.name, outcome: outcome, positionMs: positionMs, startLatencyMs: startLatencyMs,
            error: error)
    }

    /// No URLs and no header values (the token) in anything logged or shown.
    private func scrub(_ text: String) -> String {
        var result = text.replacingOccurrences(
            of: #"[A-Za-z][A-Za-z0-9+.-]*://\S+"#, with: "(link)", options: .regularExpression)
        for value in source.headers.values where value.count >= 4 {
            result = result.replacingOccurrences(of: value, with: "(hidden)")
        }
        return result
    }
}
