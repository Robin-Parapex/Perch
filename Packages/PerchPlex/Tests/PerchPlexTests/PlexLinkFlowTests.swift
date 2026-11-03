import Foundation
import Testing

@testable import PerchPlex

private let pinPath = "/api/v2/pins"
private let checkPath = "/api/v2/pins/987654321"

private func pinJSON(code: String, expiresAt: String, token: String? = nil) -> FakeTransport.Reply {
    let tokenField = token.map { "\"\($0)\"" } ?? "null"
    let body =
        "{\"id\": 987654321, \"code\": \"\(code)\", \"expiresAt\": \"\(expiresAt)\", \"authToken\": \(tokenField)}"
    return .response(status: 200, body: Data(body.utf8))
}

private func makeFlow(_ transport: FakeTransport, now: Date = isoDate("2026-11-02T10:00:00Z")) -> PlexLinkFlow {
    PlexLinkFlow(
        transport: transport, endpoints: testEndpoints, pollInterval: .milliseconds(5),
        sleep: { try await Task.sleep(for: $0) }, now: { now })
}

private func collect(_ stream: AsyncStream<LinkState>) async -> [LinkState] {
    var states: [LinkState] = []
    for await state in stream { states.append(state) }
    return states
}

@Suite("Link flow", .timeLimit(.minutes(1)))
struct PlexLinkFlowTests {
    @Test func emitsCodeThenLinkedWhenThePinGainsAToken() async {
        let transport = FakeTransport()
        await transport.script(path: pinPath, method: "POST", fixture: "pin_created")
        await transport.script(
            path: checkPath,
            .response(status: 200, body: Fixture.data("pin_created")),
            .response(status: 200, body: Fixture.data("pin_created")),
            .response(status: 200, body: Fixture.data("pin_linked")))

        let states = await collect(makeFlow(transport).start())

        #expect(
            states == [
                .code("ABCD", expiresAt: isoDate("2026-11-02T10:15:00Z")),
                .linked(token: "FAKE-TOKEN-1"),
            ])
        #expect(await transport.requests(forPath: checkPath).count == 3)
    }

    @Test func anExpiredPinIsReplacedByAFreshCode() async {
        let transport = FakeTransport()
        // First pin is already past its expiry by the injected clock (10:00); the second is not.
        await transport.script(
            path: pinPath, method: "POST",
            pinJSON(code: "OLD1", expiresAt: "2026-11-02T09:59:00Z"),
            pinJSON(code: "NEW2", expiresAt: "2026-11-02T10:15:00Z"))
        await transport.script(path: checkPath, .response(status: 200, body: Fixture.data("pin_linked")))

        let states = await collect(makeFlow(transport).start())

        #expect(
            states == [
                .code("OLD1", expiresAt: isoDate("2026-11-02T09:59:00Z")),
                .code("NEW2", expiresAt: isoDate("2026-11-02T10:15:00Z")),
                .linked(token: "FAKE-TOKEN-1"),
            ])
    }

    @Test func plexTVForgettingThePinRenewsTheCode() async {
        let transport = FakeTransport()
        await transport.script(
            path: pinPath, method: "POST",
            pinJSON(code: "OLD1", expiresAt: "2026-11-02T10:15:00Z"),
            pinJSON(code: "NEW2", expiresAt: "2026-11-02T10:15:00Z"))
        await transport.script(
            path: checkPath,
            .response(status: 404, body: Data()),
            .response(status: 200, body: Fixture.data("pin_linked")))

        let states = await collect(makeFlow(transport).start())

        #expect(
            states == [
                .code("OLD1", expiresAt: isoDate("2026-11-02T10:15:00Z")),
                .code("NEW2", expiresAt: isoDate("2026-11-02T10:15:00Z")),
                .linked(token: "FAKE-TOKEN-1"),
            ])
    }

    @Test func plexTVUnreachableOnCreateFailsAtOnce() async {
        let transport = FakeTransport()
        await transport.script(path: pinPath, method: "POST", .failure(.notConnectedToInternet))

        let states = await collect(makeFlow(transport).start())

        #expect(states == [.failed(.plexTVUnreachable)])
        #expect(await transport.requests(forPath: checkPath).isEmpty)
    }

    @Test func threeConsecutivePollFailuresGiveUp() async {
        let transport = FakeTransport()
        await transport.script(path: pinPath, method: "POST", fixture: "pin_created")
        await transport.script(path: checkPath, .failure(.timedOut))

        let states = await collect(makeFlow(transport).start())

        #expect(
            states == [
                .code("ABCD", expiresAt: isoDate("2026-11-02T10:15:00Z")),
                .failed(.plexTVUnreachable),
            ])
        #expect(await transport.requests(forPath: checkPath).count == 3)
    }

    @Test func occasionalPollFailuresAreTolerated() async {
        let transport = FakeTransport()
        await transport.script(path: pinPath, method: "POST", fixture: "pin_created")
        await transport.script(
            path: checkPath, .failure(.timedOut), .failure(.timedOut),
            .response(status: 200, body: Fixture.data("pin_linked")))

        let states = await collect(makeFlow(transport).start())

        #expect(states.last == .linked(token: "FAKE-TOKEN-1"))
    }

    @Test func stopsPollingWhenTheConsumerStops() async throws {
        let transport = FakeTransport()
        await transport.script(path: pinPath, method: "POST", fixture: "pin_created")
        await transport.script(path: checkPath, .response(status: 200, body: Fixture.data("pin_created")))
        let flow = makeFlow(transport)

        let consumer = Task {
            for await state in flow.start() {
                if case .code = state { break }
            }
        }
        await consumer.value
        // Let any request already in flight land, then no more may follow.
        try await Task.sleep(for: .milliseconds(60))
        let settled = await transport.requests.count
        try await Task.sleep(for: .milliseconds(120))

        #expect(await transport.requests.count == settled)
    }
}
