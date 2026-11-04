import Foundation
import Testing

@testable import PerchPlex

private let localURL = URL(string: "http://192.168.1.20:32400")!
private let remoteURL = URL(string: "https://203-0-113-5.abc.plex.direct:32400")!
private let relayURL = URL(string: "https://relay.example.net:8443")!

private let local = PlexConnection(
    protocol: "http", address: "192.168.1.20", port: 32400, uri: localURL.absoluteString,
    local: true, relay: false)
private let remote = PlexConnection(
    protocol: "https", address: "203-0-113-5.abc.plex.direct", port: 32400, uri: remoteURL.absoluteString,
    local: false, relay: false)
private let relay = PlexConnection(
    protocol: "https", address: "relay.example.net", port: 8443, uri: relayURL.absoluteString,
    local: false, relay: true)

private let localHost = "192.168.1.20"
private let remoteHost = "203-0-113-5.abc.plex.direct"
private let relayHost = "relay.example.net"

private func prober(_ transport: RoutedTransport) -> ConnectionProber {
    ConnectionProber(transport: transport, endpoints: testEndpoints, timing: fastTiming)
}

/// For the grace tests: per-address timeouts that never fire during a test, so the outcome depends on
/// the order of answers and the grace period alone, not on how fast a loaded machine schedules tasks.
/// (A whole-suite run starved the prober for ~375 ms, which broke 150 ms vs 320 ms wall-clock margins.)
private func prober(_ transport: RoutedTransport, grace: Duration) -> ConnectionProber {
    ConnectionProber(
        transport: transport, endpoints: testEndpoints,
        timing: ConnectionProber.Timing(
            localTimeout: .seconds(3600), remoteTimeout: .seconds(3600), grace: grace))
}

private func identity(_ machineID: String = "FAKE-MACHINE-LOUNGE") -> RoutedTransport.Reply {
    .ok(Data("{\"MediaContainer\": {\"machineIdentifier\": \"\(machineID)\"}}".utf8))
}

@Suite("Server discovery")
struct ServerDiscoveryTests {
    @Test func ownedServersComeFirstThenByNameAndPlayersAreDropped() async throws {
        func server(_ name: String, owned: Bool) -> String {
            """
            {"name": "\(name)", "provides": "server", "clientIdentifier": "ID-\(name)", "owned": \(owned),
             "accessToken": "T", "connections": []}
            """
        }
        let body =
            "["
            + [
                server("Zed", owned: true), server("beta", owned: false), server("Alpha", owned: true),
                #"{"name": "Phone", "provides": "client,player", "clientIdentifier": "P", "owned": true, "connections": []}"#,
                server("Mid", owned: false),
            ].joined(separator: ",") + "]"
        let transport = FakeTransport()
        await transport.script(path: "/api/v2/resources", .response(status: 200, body: Data(body.utf8)))

        let servers = try await ServerDiscovery(transport: transport, endpoints: testEndpoints)
            .servers(token: "T")

        #expect(servers.map(\.name) == ["Alpha", "Zed", "beta", "Mid"])
    }

    @Test func fixtureYieldsOwnedLoungeBeforeGarageAndNoPlayer() async throws {
        let transport = FakeTransport()
        await transport.script(path: "/api/v2/resources", fixture: "resources")

        let servers = try await ServerDiscovery(transport: transport, endpoints: testEndpoints)
            .servers(token: "T")

        #expect(servers.map(\.name) == ["Lounge Server", "Garage Server"])
        #expect(servers.first?.owned == true)
    }
}

@Suite("Connection prober", .timeLimit(.minutes(1)))
struct ConnectionProberTests {
    @Test func localWinsOverRemoteWhenBothAnswer() async throws {
        let transport = RoutedTransport()
        await transport.route(host: localHost, identity())
        await transport.route(host: remoteHost, identity())

        let result = try await prober(transport).probe(connections: [remote, local])

        #expect(result.tier == .local)
        #expect(result.url == localURL)
    }

    @Test func remoteAnsweringFirstLosesToLocalAnsweringWithinGrace() async throws {
        let transport = RoutedTransport()
        await transport.route(host: remoteHost, identity())
        await transport.route(host: localHost, delay: .milliseconds(30), identity())

        // A grace period that cannot run out, so local always answers within it however loaded the machine.
        let result = try await prober(transport, grace: .seconds(3600)).probe(connections: [local, remote])

        #expect(result.tier == .local)
    }

    @Test func remoteIsUsedWhenLocalMissesTheGracePeriod() async throws {
        let transport = RoutedTransport()
        await transport.route(host: remoteHost, identity())
        // Local would answer, but only long after the grace period (the prober cancels it first).
        await transport.route(host: localHost, delay: .seconds(3000), identity())

        let result = try await prober(transport, grace: .milliseconds(150)).probe(connections: [local, remote])

        // Timeouts never fire, so only the grace period can end the wait with remote; a prober that kept
        // waiting for local would hit the suite time limit instead.
        #expect(result.tier == .remote)
    }

    @Test func remoteBeatsRelayWhenBothAnswer() async throws {
        let transport = RoutedTransport()
        await transport.route(host: relayHost, identity())
        await transport.route(host: remoteHost, delay: .milliseconds(30), identity())

        // A 2 s grace keeps the 30 ms remote answer inside it however loaded the machine is.
        let result = try await prober(transport, grace: .seconds(2)).probe(connections: [relay, remote])

        #expect(result.tier == .remote)
    }

    @Test func relayIsUsedOnlyWhenNothingElseAnswers() async throws {
        let transport = RoutedTransport()
        await transport.route(host: localHost, .fail(.cannotConnectToHost))
        await transport.route(host: remoteHost, .fail(.timedOut))
        await transport.route(host: relayHost, identity())

        let result = try await prober(transport).probe(connections: [local, remote, relay])

        #expect(result.tier == .relay)
        #expect(result.url == relayURL)
    }

    @Test func aLocalLastGoodAddressThatAnswersWinsWithoutProbingTheRest() async throws {
        let transport = RoutedTransport()
        await transport.route(host: localHost, identity())
        await transport.route(host: remoteHost, identity())

        let result = try await prober(transport).probe(connections: [local, remote], lastGood: localURL)

        #expect(result.url == localURL)
        #expect(result.tier == .local)
        #expect(await transport.requests(forHost: remoteHost).isEmpty)
    }

    @Test func aRemoteLastGoodLosesToALocalAddressThatAnswers() async throws {
        let transport = RoutedTransport()
        await transport.route(host: remoteHost, identity())
        await transport.route(host: localHost, delay: .milliseconds(30), identity())

        let result = try await prober(transport, grace: .seconds(3600))
            .probe(connections: [local, remote], lastGood: remoteURL)

        #expect(result.url == localURL)
        #expect(result.tier == .local)
    }

    @Test func aRemoteLastGoodStillWinsWhenNoLocalAddressAnswers() async throws {
        let transport = RoutedTransport()
        await transport.route(host: remoteHost, identity())
        await transport.route(host: localHost, .fail(.cannotFindHost))

        let result = try await prober(transport).probe(connections: [local], lastGood: remoteURL)

        #expect(result.url == remoteURL)
        #expect(result.tier == .remote)
    }

    @Test func aPlexDirectNameForAPrivateAddressCountsAsLocal() {
        let lan = URL(string: "https://192-168-90-10.e3609fd3c80241619d7aa807c6d2c109.plex.direct:32400")!
        let wan = URL(string: "https://178-79-141-27.e3609fd3c80241619d7aa807c6d2c109.plex.direct:8443")!
        #expect(PlexConnection.manual(url: lan).tier == .local)
        #expect(PlexConnection.manual(url: wan).tier == .remote)
        func tier(_ label: String) -> PlexConnectionTier {
            PlexConnection.manual(url: URL(string: "https://\(label).abc.plex.direct:32400")!).tier
        }
        #expect(tier("fd12-3456-789a--1") == .local)  // IPv6 unique local
        #expect(tier("fe80--1c2d-3e4f-5a6b-7c8d") == .local)  // IPv6 link-local
        #expect(tier("2a02-c7c-abcd-ef01-10-0-0-1") == .remote)  // public IPv6, numeric-looking tail
        #expect(tier("2a02-c7c--10-0-0-1") == .remote)
        #expect(tier("10-0-0-1-5") == .remote)  // not four groups, not an IPv4 address
        #expect(tier("10-0-0-300") == .remote)
    }

    @Test func plexTVsTierWinsForAnAddressAlsoListedAsCached() async throws {
        let transport = RoutedTransport()
        await transport.route(host: relayHost, identity())
        await transport.route(host: remoteHost, delay: .milliseconds(30), identity())

        // plex.tv's relay entry first, then the same URL remembered (which looks direct). A 2 s grace
        // keeps the 30 ms remote answer inside it; only a local answer ends the wait early.
        let result = try await prober(transport, grace: .seconds(2))
            .probe(connections: [relay, remote, .manual(url: relayURL)], lastGood: relayURL)

        #expect(result.url == remoteURL)
        #expect(result.tier == .remote)
    }

    @Test func aDeadLastGoodFallsBackToTheRest() async throws {
        let transport = RoutedTransport()
        await transport.route(host: remoteHost, .fail(.timedOut))
        await transport.route(host: localHost, identity())

        let result = try await prober(transport).probe(connections: [local, remote], lastGood: remoteURL)

        #expect(result.url == localURL)
    }

    @Test func allFailingIsServerUnreachable() async {
        let transport = RoutedTransport()
        await transport.route(host: localHost, .fail(.cannotConnectToHost))
        await transport.route(host: remoteHost, .status(500))
        // relay host unrouted: 404

        await #expect(throws: PlexError.serverUnreachable) {
            try await prober(transport).probe(connections: [local, remote, relay])
        }
    }

    @Test func aManualAddressAnsweringAsAnotherServerIsAMismatch() async {
        let transport = RoutedTransport()
        await transport.route(host: localHost, identity("SOME-OTHER-MACHINE"))

        await #expect(throws: PlexError.serverMismatch) {
            try await prober(transport).probe(
                connections: [.manual(url: localURL)], expectedMachineID: "FAKE-MACHINE-LOUNGE")
        }
    }

    @Test func aMatchingMachineIdentifierIsAccepted() async throws {
        let transport = RoutedTransport()
        await transport.route(host: localHost, identity())

        let result = try await prober(transport).probe(
            connections: [.manual(url: localURL)], expectedMachineID: "FAKE-MACHINE-LOUNGE")

        #expect(result.identity.machineIdentifier == "FAKE-MACHINE-LOUNGE")
    }
}
