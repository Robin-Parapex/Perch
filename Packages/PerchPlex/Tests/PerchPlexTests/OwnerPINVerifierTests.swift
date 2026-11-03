import Foundation
import PerchCore
import Testing

@testable import PerchPlex

private let switchPath = "/api/home/users/1001/switch"

private func makeVerifier(
    _ transport: FakeTransport, ownerToken: String? = "OWNER-TOKEN"
) async throws -> (PlexOwnerPINVerifier, InMemorySecretStore) {
    let secrets = InMemorySecretStore()
    if let ownerToken { try secrets.setString(ownerToken, for: .plexOwnerToken) }
    let settings = SettingsStore(store: InMemoryKeyValueStore())
    try await settings.update { $0.household.ownerPlexUserID = PlexUserID("1001") }
    let verifier = PlexOwnerPINVerifier(
        transport: transport, endpoints: testEndpoints, secrets: secrets, settings: settings)
    return (verifier, secrets)
}

@Suite("Owner PIN verifier")
struct PlexOwnerPINVerifierTests {
    @Test func trueWhenPlexAcceptsThePIN() async throws {
        let transport = FakeTransport()
        await transport.script(path: switchPath, method: "POST", fixture: "switch_ok")
        let (verifier, _) = try await makeVerifier(transport)

        #expect(try await verifier.verifyOwnerPIN("1234") == true)

        let request = try #require(await transport.requests(forPath: switchPath).first)
        #expect(request.url?.query?.contains("pin=1234") == true)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "OWNER-TOKEN")
    }

    @Test func falseWhenPlexRefusesThePIN() async throws {
        let transport = FakeTransport()
        await transport.script(path: switchPath, method: "POST", fixture: "switch_ok", status: 401)
        let (verifier, _) = try await makeVerifier(transport)

        #expect(try await verifier.verifyOwnerPIN("0000") == false)
    }

    @Test func throwsUnreachableWhenPlexTVCannotBeReached() async throws {
        let transport = FakeTransport()
        await transport.script(path: switchPath, method: "POST", .failure(.notConnectedToInternet))
        let (verifier, _) = try await makeVerifier(transport)

        await #expect(throws: PlexPINError.self) { try await verifier.verifyOwnerPIN("1234") }
    }

    @Test func throwsUnreachableWhenSignedOut() async throws {
        let (verifier, _) = try await makeVerifier(FakeTransport(), ownerToken: nil)

        await #expect(throws: PlexPINError.self) { try await verifier.verifyOwnerPIN("1234") }
    }

    @Test func neverStoresTheTokenPlexReturns() async throws {
        let transport = FakeTransport()
        await transport.script(path: switchPath, method: "POST", fixture: "switch_ok")
        let (verifier, secrets) = try await makeVerifier(transport)

        _ = try await verifier.verifyOwnerPIN("1234")

        #expect(try secrets.string(for: .plexOwnerToken) == "OWNER-TOKEN")
        #expect(try secrets.string(for: .plexUserToken(PlexUserID("1001"))) == nil)
        #expect(try secrets.string(for: .module(ModuleID("plex"), "server.1001")) == nil)
    }
}
