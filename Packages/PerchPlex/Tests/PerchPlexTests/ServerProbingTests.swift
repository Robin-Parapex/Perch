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

        let result = try await prober(transport).probe(connections: [local, remote])

        #expect(result.tier == .local)
    }

    @Test func remoteIsUsedWhenLocalMissesTheGracePeriod() async throws {
        let transport = RoutedTransport()
        await transport.route(host: remoteHost, identity())
        await transport.route(host: localHost, delay: .milliseconds(320), identity())

        let result = try await prober(transport).probe(connections: [local, remote])

        #expect(result.tier == .remote)
    }

    @Test func remoteBeatsRelayWhenBothAnswer() async throws {
        let transport = RoutedTransport()
        await transport.route(host: relayHost, identity())
        await transport.route(host: remoteHost, delay: .milliseconds(30), identity())

        let result = try await prober(transport).probe(connections: [relay, remote])

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

    @Test func aLastGoodAddressThatAnswersWinsWithoutProbingTheRest() async throws {
        let transport = RoutedTransport()
        await transport.route(host: localHost, identity())
        await transport.route(host: remoteHost, identity())

        let result = try await prober(transport).probe(connections: [local, remote], lastGood: remoteURL)

        #expect(result.url == remoteURL)
        #expect(result.tier == .remote)
        #expect(await transport.requests(forHost: localHost).isEmpty)
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
