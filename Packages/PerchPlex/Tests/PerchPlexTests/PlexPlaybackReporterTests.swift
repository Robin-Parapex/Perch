import Foundation
import PerchCore
import Testing

@testable import PerchPlex

private struct Rig {
    let reporter: PlexPlaybackReporter
    let transport: GatedTransport
    let source: FakeContextSource
    let sink: RecordingSink
    let gate: TickGate
    let watchState: PlexWatchState

    init(holding: Bool = false, durationMs: Int? = 100_000, sessionID: String? = "SESS") {
        transport = GatedTransport(holding: holding)
        source = FakeContextSource()
        sink = RecordingSink()
        gate = TickGate()
        watchState = PlexWatchState(transport: transport, endpoints: testEndpoints)
        let gate = gate
        reporter = PlexPlaybackReporter(
            itemID: "42", durationMs: durationMs, sessionID: sessionID, context: reporterContext,
            contextSource: source, transport: transport, endpoints: testEndpoints,
            watchState: watchState, sink: sink, interval: .seconds(10), sleep: { _ in try await gate.sleep() })
    }

    func states() async -> [String] {
        await transport.requests.compactMap { $0.url?.path == "/:/timeline" ? $0.query("state") : nil }
    }

    func times() async -> [String] {
        await transport.requests.compactMap { $0.url?.path == "/:/timeline" ? $0.query("time") : nil }
    }

    /// Gives stray work a chance to run so "nothing was sent" is a real check.
    func settle() async {
        for _ in 0..<500 { await Task.yield() }
    }
}

@Suite("PlexPlaybackReporter")
struct PlexPlaybackReporterTests {
    @Test func firstReportIsSentAtOnceWithMilliseconds() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 1234)
        let requests = await rig.transport.requests
        #expect(requests.count == 1)
        #expect(requests[0].url?.path == "/:/timeline")
        #expect(requests[0].query("time") == "1234")
        #expect(requests[0].query("duration") == "100000")
        #expect(requests[0].query("ratingKey") == "42")
    }

    @Test func stateChangeIsSentAtOnce() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 1000)
        await rig.reporter.report(.paused, positionMs: 2000)
        #expect(await rig.states() == ["playing", "paused"])
        #expect(await rig.times() == ["1000", "2000"])
    }

    @Test func sameStateOnlyUpdatesThePositionUntilTheNextTick() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 1000)
        await rig.reporter.report(.playing, positionMs: 3000)
        await rig.reporter.report(.playing, positionMs: 5000)
        #expect(await rig.transport.requests.count == 1)
        await rig.gate.waitUntilSleeping()
        await rig.gate.tick()
        await rig.transport.waitForRequests(2)
        #expect(await rig.times() == ["1000", "5000"])
    }

    @Test func everyTickSendsTheLatestStateAndPosition() async {
        let rig = Rig()
        await rig.reporter.report(.paused, positionMs: 7000)
        for expected in 2...4 {
            await rig.gate.waitUntilSleeping()
            await rig.gate.tick()
            await rig.transport.waitForRequests(expected)
        }
        #expect(await rig.states() == ["paused", "paused", "paused", "paused"])
        #expect(await rig.times() == ["7000", "7000", "7000", "7000"])
    }

    @Test func bufferingRepeatsTheLastGoodPosition() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 4000)
        await rig.reporter.report(.buffering, positionMs: 9000)
        #expect(await rig.states() == ["playing", "buffering"])
        #expect(await rig.times() == ["4000", "4000"])
        await rig.gate.waitUntilSleeping()
        await rig.gate.tick()
        await rig.transport.waitForRequests(3)
        #expect(await rig.times() == ["4000", "4000", "4000"])
    }

    @Test func seekingBackIsReportedAsIs() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 80_000)
        await rig.reporter.report(.paused, positionMs: 20_000)
        await rig.reporter.report(.playing, positionMs: 10_000)
        #expect(await rig.times() == ["80000", "20000", "10000"])
    }

    @Test func sendsGoOutInTheOrderTheyWereMade() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 1000)
        await rig.reporter.report(.paused, positionMs: 2000)
        await rig.reporter.report(.playing, positionMs: 3000)
        await rig.reporter.report(.buffering, positionMs: 4000)
        await rig.reporter.report(.playing, positionMs: 5000)
        #expect(await rig.states() == ["playing", "paused", "playing", "buffering", "playing"])
        #expect(await rig.times() == ["1000", "2000", "3000", "3000", "5000"])
    }

    @Test func onlyTheNewestPendingReportIsSentAfterOneInFlight() async {
        let rig = Rig(holding: true)
        let first = Task { await rig.reporter.report(.playing, positionMs: 1000) }
        await rig.transport.waitForRequests(1)
        let second = Task { await rig.reporter.report(.paused, positionMs: 2000) }
        await rig.settle()
        let third = Task { await rig.reporter.report(.playing, positionMs: 3000) }
        await rig.settle()
        #expect(await rig.transport.requests.count == 1)
        await rig.transport.releaseAll()
        await first.value
        await second.value
        await third.value
        #expect(await rig.states() == ["playing", "playing"])
        #expect(await rig.times() == ["1000", "3000"])
    }

    @Test func oneRequestIsInFlightAtATime() async {
        let rig = Rig(holding: true)
        let first = Task { await rig.reporter.report(.playing, positionMs: 1000) }
        await rig.transport.waitForRequests(1)
        let second = Task { await rig.reporter.report(.paused, positionMs: 2000) }
        await rig.settle()
        await rig.settle()
        #expect(await rig.transport.requests.count == 1)
        await rig.transport.releaseOne()
        await rig.transport.waitForRequests(2)
        await rig.transport.releaseAll()
        await first.value
        await second.value
        #expect(await rig.states() == ["playing", "paused"])
    }

    @Test func theSinkHearsOnlyOfSentReportsWithTheHeldTimeForBuffering() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 4000)
        await rig.reporter.report(.playing, positionMs: 6000)
        await rig.reporter.report(.buffering, positionMs: 9000)
        let progress = await rig.sink.progress
        #expect(
            progress == [
                PlaybackProgress(itemID: "42", state: .playing, positionMs: 4000, durationMs: 100_000),
                PlaybackProgress(itemID: "42", state: .buffering, positionMs: 6000, durationMs: 100_000),
            ])
        #expect(await rig.sink.generations == [1, 1])
    }

    @Test func aFailedSendDoesNotReachTheSink() async {
        let fake = FakeTransport()
        await fake.script(path: "/:/timeline", .failure(.notConnectedToInternet))
        let sink = RecordingSink()
        let reporter = PlexPlaybackReporter(
            itemID: "42", durationMs: 100_000, sessionID: "S", context: reporterContext,
            contextSource: FakeContextSource(), transport: fake, endpoints: testEndpoints,
            watchState: PlexWatchState(transport: fake, endpoints: testEndpoints), sink: sink,
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        await reporter.report(.playing, positionMs: 1000)
        await reporter.stop(positionMs: 2000)
        #expect(await fake.requests.count == 2)
        #expect(await sink.progress.isEmpty)
    }

    @Test func aReportAfterAGenerationChangeDoesNotReachTheSink() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 1000)
        await rig.source.setGeneration(2)
        await rig.reporter.report(.paused, positionMs: 2000)
        await rig.reporter.stop(positionMs: 3000)
        await rig.settle()
        #expect(await rig.sink.progress.map(\.positionMs) == [1000])
    }

    // MARK: stop

    @Test func stopSendsStoppedAndCancelsTheLoop() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 1000)
        await rig.gate.waitUntilSleeping()
        await rig.reporter.stop(positionMs: 5000)
        #expect(await rig.states() == ["playing", "stopped"])
        #expect(await rig.times() == ["1000", "5000"])
        for _ in 0..<20_000 where await rig.gate.sleeping > 0 { await Task.yield() }
        #expect(await rig.gate.sleeping == 0)
    }

    @Test func nothingIsSentAfterStop() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 1000)
        await rig.reporter.stop(positionMs: 2000)
        let count = await rig.transport.requests.count
        await rig.reporter.report(.playing, positionMs: 3000)
        await rig.reporter.stop(positionMs: 4000)
        await rig.settle()
        #expect(await rig.transport.requests.count == count)
    }

    @Test func stopCancelsAPendingReport() async {
        let rig = Rig(holding: true)
        let first = Task { await rig.reporter.report(.playing, positionMs: 1000) }
        await rig.transport.waitForRequests(1)
        let second = Task { await rig.reporter.report(.paused, positionMs: 2000) }
        await rig.settle()
        let stop = Task { await rig.reporter.stop(positionMs: 3000) }
        await rig.settle()
        await rig.transport.releaseAll()
        await first.value
        await second.value
        await stop.value
        #expect(await rig.states() == ["playing", "stopped"])
    }

    @Test func stopAtNinetyPercentMarksWatched() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 1000)
        await rig.reporter.stop(positionMs: 90_000)
        let scrobbles = await rig.transport.requests.filter { $0.url?.path == "/:/scrobble" }
        #expect(scrobbles.count == 1)
        #expect(scrobbles.first?.query("key") == "42")
        let paths = await rig.transport.requests.compactMap { $0.url?.path }
        #expect(paths == ["/:/timeline", "/:/timeline", "/:/scrobble"])
        let watched = await rig.sink.watched
        #expect(watched.count == 1 && watched[0].itemID == "42" && watched[0].watched)
        #expect(await rig.watchState.revision(of: "42") == 1)
    }

    @Test func stopBelowNinetyPercentDoesNotMarkWatched() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 1000)
        await rig.reporter.stop(positionMs: 89_999)
        #expect(await rig.transport.requests.filter { $0.url?.path == "/:/scrobble" }.isEmpty)
        #expect(await rig.sink.watched.isEmpty)
        #expect(await rig.watchState.revision(of: "42") == 0)
    }

    @Test func noScrobbleWhenThePositionIsPastTheDuration() async {
        let rig = Rig(durationMs: 600_000)
        await rig.reporter.report(.playing, positionMs: 1000)
        await rig.reporter.stop(positionMs: 720_000)
        #expect(await rig.transport.requests.filter { $0.url?.path == "/:/scrobble" }.isEmpty)
        #expect(await rig.sink.watched.isEmpty)
    }

    @Test func noScrobbleWithoutASaneDuration() async {
        for duration in [nil, 0] as [Int?] {
            let rig = Rig(durationMs: duration)
            await rig.reporter.report(.playing, positionMs: 1000)
            await rig.reporter.stop(positionMs: 500_000)
            #expect(await rig.transport.requests.filter { $0.url?.path == "/:/scrobble" }.isEmpty)
            #expect(await rig.sink.watched.isEmpty)
        }
    }

    // MARK: generation

    @Test func aGenerationChangeMakesTheReporterInert() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 1000)
        await rig.gate.waitUntilSleeping()
        await rig.source.setGeneration(2)
        await rig.reporter.report(.paused, positionMs: 2000)
        await rig.reporter.stop(positionMs: 100_000)
        await rig.settle()
        #expect(await rig.states() == ["playing"])
        #expect(await rig.transport.requests.filter { $0.url?.path == "/:/scrobble" }.isEmpty)
        #expect(await rig.sink.watched.isEmpty)
    }

    @Test func aGenerationChangeStopsTheLoop() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 1000)
        await rig.gate.waitUntilSleeping()
        await rig.source.setGeneration(2)
        await rig.gate.tick()
        await rig.settle()
        #expect(await rig.transport.requests.count == 1)
        #expect(await rig.gate.sleeping == 0)
    }

    @Test func aGenerationChangeBeforeStopSendsNoStoppedAndNoScrobble() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 1000)
        await rig.source.setGeneration(2)
        await rig.reporter.stop(positionMs: 100_000)
        #expect(await rig.transport.requests.count == 1)
    }

    // MARK: identity and secrets

    @Test func sessionIDHeaderIsPresentAndStable() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 1000)
        await rig.reporter.report(.paused, positionMs: 2000)
        await rig.reporter.stop(positionMs: 3000)
        let ids = await rig.transport.requests.map { $0.value(forHTTPHeaderField: "X-Plex-Session-Identifier") }
        #expect(ids == ["SESS", "SESS", "SESS"])
        #expect(rig.reporter.sessionID == "SESS")
    }

    @Test func aMissingSessionIDBecomesAStableUUID() async {
        let rig = Rig(sessionID: nil)
        let id = rig.reporter.sessionID
        #expect(UUID(uuidString: id) != nil)
        await rig.reporter.report(.playing, positionMs: 1000)
        await rig.reporter.report(.paused, positionMs: 2000)
        let ids = await rig.transport.requests.map { $0.value(forHTTPHeaderField: "X-Plex-Session-Identifier") }
        #expect(ids == [id, id])
    }

    @Test func theTokenIsOnlyInTheHeader() async {
        let rig = Rig()
        await rig.reporter.report(.playing, positionMs: 1000)
        await rig.reporter.stop(positionMs: 95_000)
        let requests = await rig.transport.requests
        #expect(requests.count == 3)
        for request in requests {
            #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "SECRET-TOKEN")
            #expect(!(request.url?.absoluteString.contains("SECRET-TOKEN") ?? true))
            #expect(request.url?.query?.lowercased().contains("token") != true)
        }
    }

    @Test func networkFailuresAreSwallowed() async {
        let fake = FakeTransport()
        await fake.script(path: "/:/timeline", .failure(.notConnectedToInternet))
        let source = FakeContextSource()
        let reporter = PlexPlaybackReporter(
            itemID: "42", durationMs: 100_000, sessionID: "S", context: reporterContext,
            contextSource: source, transport: fake, endpoints: testEndpoints,
            watchState: PlexWatchState(transport: fake, endpoints: testEndpoints), sink: nil,
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        await reporter.report(.playing, positionMs: 1000)
        await reporter.stop(positionMs: 2000)
        #expect(await fake.requests.count == 2)
    }
}
