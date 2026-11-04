import CoreMedia
import Foundation
import PerchCore
import Testing
import UIKit

@testable import PerchPlayer

// MARK: fakes

@MainActor
final class FakeEngine: PlaybackEngine {
    let name = "fake"
    let viewController = UIViewController()
    let events: AsyncStream<EngineEvent>
    private let continuation: AsyncStream<EngineEvent>.Continuation

    var positionMs = 0
    var loads: [PlaybackSource] = []
    var seeks: [Int] = []
    var plays = 0
    var tornDown = 0
    var loadError: (any Error)?
    var skip: SkipOffer?
    var onSkip: (@MainActor () -> Void)?
    var upNext: UpNextProposal?
    var upNextMode: UpNextMode?
    var upNextShows = 0
    var onAccept: (@MainActor (UpNextAcceptance) -> Void)?
    var onDismiss: (@MainActor () -> Void)?

    init() {
        (events, continuation) = AsyncStream.makeStream(of: EngineEvent.self)
    }

    func load(_ source: PlaybackSource, metadata: PlayerItemMetadata) async throws {
        loads.append(source)
        if let loadError { throw loadError }
        positionMs = source.startMs
    }

    func play() {
        plays += 1
        continuation.yield(.playing)
    }

    func pause() { continuation.yield(.paused) }

    func seek(toMs ms: Int) async {
        seeks.append(ms)
        positionMs = ms
    }

    func showSkip(_ offer: SkipOffer?, onSkip: @escaping @MainActor () -> Void) {
        skip = offer
        self.onSkip = offer == nil ? nil : onSkip
    }

    func showUpNext(
        _ proposal: UpNextProposal?, mode: UpNextMode,
        onAccept: @escaping @MainActor (UpNextAcceptance) -> Void, onDismiss: @escaping @MainActor () -> Void
    ) {
        upNext = proposal
        upNextMode = proposal == nil ? nil : mode
        if proposal != nil { upNextShows += 1 }
        self.onAccept = proposal == nil ? nil : onAccept
        self.onDismiss = proposal == nil ? nil : onDismiss
    }

    /// Every `setNativeChromeHidden` call, in order.
    var chromeHiddenCalls: [Bool] = []
    var chromeHidden: Bool { chromeHiddenCalls.last ?? false }
    func setNativeChromeHidden(_ hidden: Bool) { chromeHiddenCalls.append(hidden) }

    func teardown() {
        tornDown += 1
        continuation.finish()
    }

    func send(_ event: EngineEvent) {
        if case .positionTick(let ms) = event { positionMs = ms }
        continuation.yield(event)
    }
}

actor FakeReporter: PlaybackReporting {
    nonisolated let sessionID = "s1"
    var reports: [(PlaybackState, Int)] = []
    var stops: [Int] = []
    func report(_ state: PlaybackState, positionMs: Int) async { reports.append((state, positionMs)) }
    func stop(positionMs: Int) async { stops.append(positionMs) }
}

actor Recorder<T: Sendable> {
    var items: [T] = []
    func add(_ item: T) { items.append(item) }
}

let token = "secret-token-1234"

func makeSource(
    key: String = "100", startMs: Int = 0, durationMs: Int = 60_000, markers: [MediaMarker] = clipMarkers,
    transcode: Bool = false
) -> PlaybackSource {
    PlaybackSource(
        ratingKey: key, title: "Episode \(key)",
        url: URL(string: "https://plex.example:32400/library/parts/1/file.mkv?X-Plex-Token=\(token)")!,
        headers: ["X-Plex-Token": token], decision: PlaybackDecision(method: transcode ? .transcode : .directPlay),
        startMs: startMs, durationMs: durationMs, sessionID: "session-\(key)", markers: markers,
        isTranscodeSession: transcode)
}

let clipMarkers = [
    MediaMarker(kind: .intro, startMs: 5_000, endMs: 15_000),
    MediaMarker(kind: .credits, startMs: 45_000, endMs: 60_000, isFinal: true),
]

@MainActor
final class Harness {
    let engine = FakeEngine()
    let reporter = FakeReporter()
    let log = Recorder<PlaybackLogEntry>()
    let transcodeStops = Recorder<String>()
    let session: PlaybackSession
    var hasNext = true
    var finished = 0

    static let failureCopy = "App copy for the failure line."

    init(
        source: PlaybackSource = makeSource(), policy: PlaybackPolicy = .household, hasNext: Bool = true,
        canRetry: Bool = true
    ) {
        self.hasNext = hasNext
        let log = log, stops = transcodeStops, reporter = reporter
        var box: Harness?
        session = PlaybackSession(
            engine: engine, source: source, metadata: PlayerItemMetadata(title: source.title), policy: policy,
            reporter: reporter, log: { await log.add($0) },
            nextItem: { box?.hasNext == true ? UpNextProposal(title: "Next", ratingKey: "next") : nil },
            resolveNext: { proposal in
                PlaybackItem(
                    source: makeSource(key: proposal.ratingKey), metadata: PlayerItemMetadata(title: "Next"),
                    reporter: reporter)
            },
            onTranscodeStop: { await stops.add($0) },
            failureMessage: Harness.failureCopy, canRetry: canRetry,
            sleep: { _ in })
        box = self
        session.onFinished = { [weak self] in self?.finished += 1 }
    }

    func start() async {
        session.start()
        await until { self.session.phase == .playing }
    }

    func tick(_ ms: Int) async {
        let seeks = engine.seeks.count
        engine.send(.positionTick(ms))
        // Done when the session saw it, or an auto-skip it caused already moved it on.
        await until {
            self.session.positionMs == ms || self.session.phase == .finished || self.engine.seeks.count > seeks
        }
    }

    /// Plays to the credits and lets the countdown accept.
    func autoAdvance() async {
        let items = session.itemsStarted
        await tick(46_000)
        await until { self.engine.onAccept != nil }
        engine.onAccept?(.countdown)
        await until { self.session.itemsStarted == items + 1 && self.session.phase == .playing }
    }
}

@MainActor
func until(_ condition: @MainActor () -> Bool, timeout: Duration = .seconds(2)) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(2))
    }
}

// MARK: tests

@MainActor
@Suite struct PlaybackSessionTests {
    @Test func resumePositionIsPassedToLoad() async {
        let h = Harness(source: makeSource(startMs: 1_234_000, durationMs: 2_000_000))
        await h.start()
        #expect(h.engine.loads.first?.startMs == 1_234_000)
        #expect(h.engine.plays == 1)
        await h.session.settle()
        let reports = await h.reporter.reports
        #expect(reports.first?.0 == .playing)
        let log = await h.log.items
        #expect(log.first?.outcome == .start)
        #expect(log.first?.startLatencyMs != nil)
        #expect(log.first?.engine == "fake")
    }

    @Test func skipOfferedInsideIntroAndClearedAfter() async {
        let h = Harness()
        await h.start()
        await h.tick(3_000)
        #expect(h.engine.skip == nil)
        await h.tick(6_000)
        #expect(h.engine.skip?.kind == .intro)
        #expect(h.session.skipOffer?.targetMs == 15_500)
        await h.tick(16_000)
        #expect(h.engine.skip == nil)
        #expect(h.session.skipOffer == nil)
    }

    @Test func takingSkipSeeksAndMarksSpent() async {
        let h = Harness(policy: PlaybackPolicy(autoSkipIntro: true))
        h.session.start()
        await until { h.session.phase == .playing }
        // Auto-skip would fire at once with the fake sleep; take it by hand first via a marker that was spent.
        await h.tick(6_000)
        await until { h.engine.seeks.count == 1 }
        #expect(h.engine.seeks == [15_500])
        #expect(h.session.skipsTaken == 1)
        // Back inside the intro: offered again but never auto-skipped (spent).
        await h.tick(7_000)
        #expect(h.session.skipOffer?.autoSkipAfterSeconds == nil)
        #expect(h.engine.skip != nil)
        h.engine.onSkip?()
        await until { h.engine.seeks.count == 2 }
        #expect(h.engine.seeks == [15_500, 15_500])
        #expect(h.session.skipsTaken == 2)
    }

    @Test func manualSkipWithHouseholdPolicy() async {
        let h = Harness()
        await h.start()
        await h.tick(6_000)
        #expect(h.session.skipOffer?.autoSkipAfterSeconds == nil)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(h.engine.seeks.isEmpty)
        h.engine.onSkip?()
        await until { h.engine.seeks == [15_500] }
        #expect(h.engine.seeks == [15_500])
        #expect(h.session.positionMs == 15_500)
        #expect(h.engine.skip == nil)
    }

    @Test func autoSkipFiresOnce() async {
        let h = Harness(policy: PlaybackPolicy(autoSkipIntro: true))
        await h.start()
        await h.tick(6_000)
        await until { !h.engine.seeks.isEmpty }
        await h.tick(8_000)
        await h.tick(9_000)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(h.engine.seeks == [15_500])
    }

    @Test func upNextTimedAtCreditsAndCountdownCountsAutomaticAdvance() async {
        let h = Harness()
        await h.start()
        await h.tick(44_000)
        #expect(h.engine.upNext == nil)
        await h.tick(45_500)
        #expect(h.engine.upNext?.ratingKey == "next")
        #expect(h.engine.upNextMode == .timed(seconds: 10))
        h.engine.onAccept?(.countdown)
        await until { h.session.itemsStarted == 2 && h.session.phase == .playing }
        #expect(h.session.autoChainCount == 1)
        #expect(h.engine.loads.map(\.ratingKey) == ["100", "next"])
        await h.session.settle()
        #expect(await h.reporter.stops.count == 1)
    }

    @Test func threeAutomaticAdvancesThenEndAsksStillWatching() async {
        let h = Harness()
        await h.start()
        await h.autoAdvance()
        await h.autoAdvance()
        await h.autoAdvance()
        #expect(h.session.autoChainCount == 3)
        // Fourth item: nothing is proposed at the credits, and the end asks once, with the chrome hidden.
        let shows = h.engine.upNextShows
        await h.tick(46_000)
        await h.tick(55_000)
        #expect(h.engine.upNext == nil)
        #expect(h.engine.upNextShows == shows)
        #expect(h.engine.chromeHiddenCalls.isEmpty)
        h.engine.send(.ended)
        await until { h.session.overlayRequest != nil }
        #expect(h.session.overlayRequest == .stillWatching)
        #expect(h.engine.upNext == nil && h.session.upNextShown == nil)
        #expect(h.engine.chromeHiddenCalls == [true])
        h.session.continueWatching()
        await until { h.session.itemsStarted == 5 && h.session.phase == .playing }
        #expect(h.session.overlayRequest == nil)
        #expect(h.session.autoChainCount == 0)
        #expect(h.engine.chromeHiddenCalls == [true, false])
        #expect(h.engine.loads.last?.ratingKey == "next")
        // The next item is back under the limit: a timed proposal again.
        await h.tick(46_000)
        #expect(h.engine.upNextMode == .timed(seconds: 10))
    }

    @Test func manualProposalIsWithdrawnBeforeStillWatching() async {
        // Estimated credits give a manual proposal; reaching the limit mid-item (count rebuilt from 3
        // automatic advances) must not leave it under the prompt.
        let h = Harness(source: makeSource(durationMs: 1_200_000, markers: []))
        await h.start()
        await h.tick(1_160_000)
        #expect(h.engine.upNextMode == .manual)
        h.session.setAutoChainCountForTesting(3)
        h.engine.send(.ended)
        await until { h.session.overlayRequest != nil }
        #expect(h.session.overlayRequest == .stillWatching)
        #expect(h.engine.upNext == nil && h.session.upNextShown == nil)
        #expect(h.engine.chromeHidden)
    }

    @Test func failureOverlayHidesChromeAndRetryRestoresIt() async {
        let h = Harness()
        await h.start()
        h.engine.send(.failed("boom"))
        await until { h.session.overlayRequest != nil }
        #expect(h.engine.chromeHiddenCalls == [true])
        h.session.retry()
        await until { h.session.phase == .playing }
        #expect(h.engine.chromeHiddenCalls == [true, false])
        await h.session.exit()
        // Exit after a cleared overlay does not touch the torn-down engine.
        #expect(h.engine.chromeHiddenCalls == [true, false])
    }

    @Test func positionTicksAdvanceTheReportedPosition() async {
        let h = Harness()
        await h.start()
        for ms in [10_000, 20_000, 30_000] { h.engine.send(.positionTick(ms)) }
        await until { h.session.positionMs == 30_000 }
        await h.session.settle()
        let positions = await h.reporter.reports.filter { $0.0 == .playing }.map(\.1).filter { $0 >= 10_000 }
        #expect(positions == [10_000, 20_000, 30_000])
    }

    @Test func retryIsRefusedWhenTheProfileMayNotRetry() async {
        let h = Harness(canRetry: false)
        await h.start()
        h.engine.send(.failed("boom"))
        await until { h.session.overlayRequest != nil }
        #expect(h.session.overlayRequest == .playbackFailed(message: Harness.failureCopy))
        let loads = h.engine.loads.count
        h.session.retry()
        await h.session.settle()
        #expect(h.session.phase == .failed)
        #expect(h.engine.loads.count == loads)
        #expect(h.session.overlayRequest == .playbackFailed(message: Harness.failureCopy))
        h.session.stopWatching()
        await until { h.session.phase == .finished }
    }

    /// A caller that says nothing about retry gets none: "Try Again" is opt-in (parents only).
    @Test func retryIsOffByDefault() {
        let source = makeSource()
        let session = PlaybackSession(
            engine: FakeEngine(), source: source, metadata: PlayerItemMetadata(title: source.title),
            policy: .household, reporter: FakeReporter(), log: { _ in }, nextItem: { nil },
            resolveNext: { _ in throw CancellationError() }, onTranscodeStop: { _ in }, sleep: { _ in })
        #expect(session.canRetry == false)
    }

    @Test func userInputResetsTheCount() async {
        let h = Harness()
        await h.start()
        await h.autoAdvance()
        await h.autoAdvance()
        #expect(h.session.autoChainCount == 2)
        h.engine.send(.userInput)
        await until { h.session.autoChainCount == 0 }
        #expect(h.session.autoChainCount == 0)
        // The end with no accepted proposal advances automatically (count 1), no still-watching.
        h.engine.send(.ended)
        await until { h.session.itemsStarted == 4 && h.session.phase == .playing }
        #expect(h.session.autoChainCount == 1)
        #expect(h.session.overlayRequest == nil)
    }

    @Test func userAcceptIsUserInput() async {
        let h = Harness()
        await h.start()
        await h.autoAdvance()
        await h.tick(46_000)
        h.engine.onAccept?(.user)
        await until { h.session.itemsStarted == 3 && h.session.phase == .playing }
        #expect(h.session.autoChainCount == 0)
    }

    @Test func estimatedCreditsAreManual() async {
        let h = Harness(source: makeSource(durationMs: 1_200_000, markers: []))
        await h.start()
        // Estimated credits: 1_200_000 - 48_000.
        await h.tick(1_160_000)
        #expect(h.engine.upNext != nil)
        #expect(h.engine.upNextMode == .manual)
    }

    @Test func failureLogsAndRequestsOverlay() async {
        let h = Harness()
        await h.start()
        h.engine.send(.failed("AVFoundationErrorDomain -11800: https://plex.example/x?X-Plex-Token=\(token)"))
        await until { h.session.overlayRequest != nil }
        guard case .playbackFailed(let message) = h.session.overlayRequest else {
            Issue.record("no failure overlay")
            return
        }
        // The overlay gets the app's line, never any of the raw error (scrubbed or not).
        #expect(message == Harness.failureCopy)
        #expect(!message.contains("-11800") && !message.contains("AVFoundation") && !message.contains("(link)"))
        #expect(!message.contains(token))
        await h.session.settle()
        let failure = await h.log.items.first { $0.outcome == .failure }
        #expect(failure?.error?.contains("-11800") == true)
        #expect(failure?.error?.contains("plex.example") == false)
    }

    @Test func loadFailureLogsAndRequestsOverlay() async {
        let h = Harness()
        h.engine.loadError = NativeEngineError.failed("CoreMediaErrorDomain -12938")
        h.session.start()
        await until { h.session.overlayRequest != nil }
        #expect(h.session.phase == .failed)
        await h.session.settle()
        #expect(await h.log.items.map(\.outcome) == [.failure])
    }

    @Test func exitReportsStopOnceAndStopsTranscodeOnlyForTranscodes() async {
        for transcode in [false, true] {
            let h = Harness(source: makeSource(transcode: transcode))
            await h.start()
            await h.tick(20_000)
            await h.session.exit()
            await h.session.exit()
            #expect(await h.reporter.stops == [20_000])
            #expect(await h.transcodeStops.items == (transcode ? ["session-100"] : []))
            #expect(h.engine.tornDown == 1)
            #expect(h.finished == 1)
            #expect(await h.log.items.map(\.outcome) == [.start, .stop])
        }
    }

    @Test func endWithNoNextStops() async {
        let h = Harness(hasNext: false)
        await h.start()
        await h.tick(59_000)
        h.engine.send(.ended)
        await until { h.session.phase == .finished }
        await h.session.settle()
        #expect(h.finished == 1)
        #expect(await h.reporter.stops.count == 1)
    }

    @Test func noHeaderValueInAnyLogEntry() async throws {
        let h = Harness(source: makeSource(transcode: true))
        await h.start()
        await h.tick(46_000)
        h.engine.onAccept?(.countdown)
        await until { h.session.itemsStarted == 2 && h.session.phase == .playing }
        h.engine.send(.failed("Failed loading https://plex.example/a?X-Plex-Token=\(token) token \(token)"))
        await until { h.session.overlayRequest != nil }
        await h.session.exit()
        let entries = await h.log.items
        #expect(entries.count >= 4)
        let encoded = String(decoding: try JSONEncoder().encode(entries), as: UTF8.self)
        #expect(!encoded.contains(token))
        #expect(!encoded.contains("plex.example"))
    }
}

@MainActor
@Suite struct DisplayCriteriaTests {
    @Test func formatDescriptionsCarryColour() {
        let hdr = DisplayCriteriaMatcher.formatDescription(for: PlaybackDecision(method: .directPlay, videoRange: .hdr10))
        let transfer = hdr.flatMap {
            CMFormatDescriptionGetExtension($0, extensionKey: kCMFormatDescriptionExtension_TransferFunction)
        }
        #expect(transfer as? String == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
        let dv = DisplayCriteriaMatcher.formatDescription(for: PlaybackDecision(method: .directPlay, videoRange: .dolbyVision))
        #expect(dv.map(CMFormatDescriptionGetMediaSubType) == kCMVideoCodecType_DolbyVisionHEVC)
        let sdr = DisplayCriteriaMatcher.formatDescription(for: PlaybackDecision(method: .directPlay))
        let primaries = sdr.flatMap {
            CMFormatDescriptionGetExtension($0, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries)
        }
        #expect(primaries as? String == kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String)
    }

    @Test func criteriaNeedAFrameRateAndApplySkipsWithoutWindow() {
        #expect(DisplayCriteriaMatcher.criteria(for: PlaybackDecision(method: .directPlay)) == nil)
        #expect(DisplayCriteriaMatcher.criteria(for: PlaybackDecision(method: .directPlay, frameRate: 23.976)) != nil)
        let matcher = DisplayCriteriaMatcher()
        #expect(!matcher.apply(PlaybackDecision(method: .directPlay, frameRate: 24), window: nil))
        #expect(!matcher.isApplied)
    }
}
