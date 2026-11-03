import Foundation
import Testing

@testable import PerchPlex

@Suite("PlexWatchState")
struct PlexWatchStateTests {
    @Test func watchedSendsScrobbleAndUnwatchedSendsUnscrobble() async throws {
        let transport = GatedTransport(holding: false)
        let state = PlexWatchState(transport: transport, endpoints: testEndpoints)
        try await state.setWatched(true, itemID: "7", context: reporterContext)
        try await state.setWatched(false, itemID: "7", context: reporterContext)
        let requests = await transport.requests
        #expect(requests.map { $0.url?.path } == ["/:/scrobble", "/:/unscrobble"])
        #expect(requests[0].query("key") == "7")
        #expect(requests[0].query("identifier") == "com.plexapp.plugins.library")
        #expect(requests[0].value(forHTTPHeaderField: "X-Plex-Token") == "SECRET-TOKEN")
        #expect(requests[0].url?.absoluteString.contains("SECRET-TOKEN") == false)
    }

    @Test func revisionIsBumpedBeforeTheRequestIsSent() async {
        let transport = GatedTransport(holding: true)
        let state = PlexWatchState(transport: transport, endpoints: testEndpoints)
        #expect(await state.revision(of: "7") == 0)
        let task = Task { try await state.setWatched(true, itemID: "7", context: reporterContext) }
        await transport.waitForRequests(1)
        #expect(await state.revision(of: "7") == 1)
        await transport.releaseAll()
        _ = try? await task.value
        #expect(await state.revision(of: "7") == 1)
    }

    @Test func revisionsAreKeptPerItem() async throws {
        let transport = GatedTransport(holding: false)
        let state = PlexWatchState(transport: transport, endpoints: testEndpoints)
        try await state.setWatched(true, itemID: "7", context: reporterContext)
        try await state.setWatched(false, itemID: "7", context: reporterContext)
        try await state.setWatched(true, itemID: "8", context: reporterContext)
        #expect(await state.revision(of: "7") == 2)
        #expect(await state.revision(of: "8") == 1)
        #expect(await state.revision(of: "9") == 0)
        #expect(await state.revisions() == ["7": 2, "8": 1])
    }

    @Test func aFailedSendStillBumpsTheRevisionAndThrows() async {
        let fake = FakeTransport()
        await fake.script(path: "/:/scrobble", .response(status: 500, body: Data()))
        let state = PlexWatchState(transport: fake, endpoints: testEndpoints)
        await #expect(throws: PlexError.http(500)) {
            try await state.setWatched(true, itemID: "7", context: reporterContext)
        }
        #expect(await state.revision(of: "7") == 1)
    }

    @Test func restoreProgressSendsTheOffsetAndLeavesRevisionsAlone() async throws {
        let transport = GatedTransport(holding: false)
        let state = PlexWatchState(transport: transport, endpoints: testEndpoints)
        try await state.restoreProgress(itemID: "7", positionMs: 61_000, context: reporterContext)
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests[0].url?.path == "/:/progress")
        #expect(requests[0].query("time") == "61000")
        #expect(requests[0].query("key") == "7")
        #expect(await state.revision(of: "7") == 0)
    }
}
