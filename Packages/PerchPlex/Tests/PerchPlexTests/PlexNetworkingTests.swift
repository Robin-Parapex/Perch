import Foundation
import Testing

@testable import PerchPlex

private func freshDefaults() -> (UserDefaults, () -> Void) {
    let name = "perch.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (defaults, { defaults.removePersistentDomain(forName: name) })
}

@Suite("Client identity headers")
struct PlexClientIdentityTests {
    @Test func everyPlexHeaderIsPresent() {
        let identity = PlexClientIdentity(clientIdentifier: "CLIENT-1", version: "1.2.3")
        let h = identity.headers()
        #expect(h["Accept"] == "application/json")
        #expect(h["X-Plex-Product"] == "Perch")
        #expect(h["X-Plex-Platform"] == "tvOS")
        #expect(h["X-Plex-Device"] == "Apple TV")
        #expect(h["X-Plex-Device-Name"] == "Perch")
        #expect(h["X-Plex-Version"] == "1.2.3")
        #expect(h["X-Plex-Client-Identifier"] == "CLIENT-1")
        #expect(h["X-Plex-Token"] == nil)
    }

    @Test func tokenOnlyWhenGiven() {
        let identity = PlexClientIdentity(clientIdentifier: "C", version: "1")
        #expect(identity.headers(token: "T")["X-Plex-Token"] == "T")
        #expect(identity.headers(token: nil)["X-Plex-Token"] == nil)
        #expect(identity.headers(token: "")["X-Plex-Token"] == nil)
    }

    @Test func identifierGeneratedOnceAndReused() {
        let (defaults, cleanup) = freshDefaults()
        defer { cleanup() }
        let first = PlexClientIdentity(defaults: defaults)
        let second = PlexClientIdentity(defaults: defaults)
        #expect(!first.clientIdentifier.isEmpty)
        #expect(first.clientIdentifier == second.clientIdentifier)
        #expect(defaults.string(forKey: PlexClientIdentity.defaultsKey) == first.clientIdentifier)
    }

    @Test func differentSuitesGetDifferentIdentifiers() {
        let (a, cleanA) = freshDefaults()
        let (b, cleanB) = freshDefaults()
        defer { cleanA(); cleanB() }
        #expect(PlexClientIdentity(defaults: a).clientIdentifier != PlexClientIdentity(defaults: b).clientIdentifier)
    }

    @Test func existingIdentifierIsKept() {
        let (defaults, cleanup) = freshDefaults()
        defer { cleanup() }
        defaults.set("EXISTING", forKey: PlexClientIdentity.defaultsKey)
        #expect(PlexClientIdentity(defaults: defaults).clientIdentifier == "EXISTING")
    }
}

@Suite("Endpoint builders")
struct PlexEndpointsTests {
    static let secret = "SECRET-TOKEN-XYZ"
    let endpoints = PlexEndpoints(identity: PlexClientIdentity(clientIdentifier: "CID", version: "9"))
    let base = URL(string: "http://192.168.1.20:32400")!

    private func check(_ r: URLRequest, _ method: String, _ host: String, _ path: String) {
        #expect(r.httpMethod == method)
        #expect(r.url?.host == host)
        #expect(r.url?.path == path)
    }

    private func items(_ r: URLRequest) -> [String: String] {
        let comps = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)!
        return Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    @Test func createPin() {
        let r = endpoints.createPin()
        check(r, "POST", "plex.tv", "/api/v2/pins")
        #expect(items(r)["strong"] == "false")
        #expect(r.value(forHTTPHeaderField: "X-Plex-Client-Identifier") == "CID")
        #expect(r.value(forHTTPHeaderField: "X-Plex-Token") == nil)
    }

    @Test func checkPin() {
        let r = endpoints.checkPin(id: 42)
        check(r, "GET", "plex.tv", "/api/v2/pins/42")
        #expect(r.value(forHTTPHeaderField: "X-Plex-Token") == nil)
    }

    @Test func user() {
        check(endpoints.user(token: Self.secret), "GET", "plex.tv", "/api/v2/user")
    }

    @Test func homeUsers() {
        check(endpoints.homeUsers(token: Self.secret), "GET", "plex.tv", "/api/v2/home/users")
    }

    @Test func switchUserWithPin() {
        let r = endpoints.switchUser(id: "1002", pin: "1234", ownerToken: Self.secret)
        check(r, "POST", "plex.tv", "/api/home/users/1002/switch")
        #expect(items(r)["pin"] == "1234")
    }

    @Test(arguments: [nil, ""] as [String?])
    func switchUserWithoutPinHasNoPinItem(pin: String?) {
        let r = endpoints.switchUser(id: "1002", pin: pin, ownerToken: Self.secret)
        check(r, "POST", "plex.tv", "/api/home/users/1002/switch")
        #expect(items(r)["pin"] == nil)
        #expect(r.url?.query == nil)
    }

    @Test func resources() {
        let r = endpoints.resources(token: Self.secret)
        check(r, "GET", "clients.plex.tv", "/api/v2/resources")
        #expect(items(r)["includeHttps"] == "1")
        #expect(items(r)["includeRelay"] == "1")
        #expect(items(r)["includeIPv6"] == "1")
    }

    @Test func serverIdentity() {
        let r = endpoints.serverIdentity(base: base, token: nil)
        check(r, "GET", "192.168.1.20", "/identity")
        #expect(r.url?.port == 32400)
        #expect(r.value(forHTTPHeaderField: "X-Plex-Token") == nil)
    }

    @Test func librarySections() {
        let r = endpoints.librarySections(base: base, token: Self.secret)
        check(r, "GET", "192.168.1.20", "/library/sections")
    }

    @Test func tokenIsAHeaderAndNeverInAnyURL() {
        let all: [URLRequest] = [
            endpoints.user(token: Self.secret),
            endpoints.homeUsers(token: Self.secret),
            endpoints.switchUser(id: "1", pin: nil, ownerToken: Self.secret),
            endpoints.switchUser(id: "1", pin: "9999", ownerToken: Self.secret),
            endpoints.resources(token: Self.secret),
            endpoints.serverIdentity(base: base, token: Self.secret),
            endpoints.librarySections(base: base, token: Self.secret),
        ]
        for r in all {
            #expect(r.value(forHTTPHeaderField: "X-Plex-Token") == Self.secret)
            let urlText = r.url?.absoluteString ?? ""
            let leaked = urlText.contains(Self.secret)
            #expect(leaked == false)
            #expect(items(r)["X-Plex-Token"] == nil)
        }
    }
}

@Suite("Error mapping")
struct PlexErrorTests {
    @Test(arguments: [401, 403]) func authFailuresAreUnauthorized(status: Int) {
        #expect(PlexError.forStatus(status) == .unauthorized)
    }

    @Test func serverErrorIsHTTP() {
        #expect(PlexError.forStatus(500) == .http(500))
        #expect(PlexError.forStatus(404) == .http(404))
    }

    @Test(arguments: [200, 201, 204, 299]) func successIsNil(status: Int) {
        #expect(PlexError.forStatus(status) == nil)
    }

    @Test(arguments: [URLError.Code.timedOut, .cannotConnectToHost, .notConnectedToInternet])
    func transportFailuresMapByHost(code: URLError.Code) {
        #expect(PlexError.transport(URLError(code), host: .plexTV) == .plexTVUnreachable)
        #expect(PlexError.transport(URLError(code), host: .server) == .serverUnreachable)
    }

    @Test func plexErrorsPassThrough() {
        #expect(PlexError.transport(PlexError.pinIncorrect, host: .plexTV) == .pinIncorrect)
    }

    private let request = URLRequest(url: URL(string: "https://plex.tv/x")!)

    @Test func performReturnsBodyOn200() async throws {
        let fake = FakeTransport()
        await fake.script(path: "/x", .response(status: 200, body: Data("hi".utf8)))
        let data = try await fake.perform(request, host: .plexTV)
        #expect(data == Data("hi".utf8))
    }

    @Test(arguments: [(401, PlexError.unauthorized), (403, .unauthorized), (500, .http(500))])
    func performMapsStatus(status: Int, expected: PlexError) async {
        let fake = FakeTransport()
        await fake.script(path: "/x", .response(status: status, body: Data()))
        await #expect(throws: expected) { try await fake.perform(request, host: .plexTV) }
    }

    @Test func performMapsTransportFailure() async {
        let fake = FakeTransport()
        await fake.script(path: "/x", .failure(.timedOut))
        await #expect(throws: PlexError.plexTVUnreachable) { try await fake.perform(request, host: .plexTV) }
        await #expect(throws: PlexError.serverUnreachable) { try await fake.perform(request, host: .server) }
    }

    @Test func badJSONThrowsDecoding() {
        #expect(throws: PlexError.decoding) { try PlexJSON.decode(PlexPin.self, from: Data("nope".utf8)) }
        #expect(throws: PlexError.decoding) { try PlexServerIdentity.decode(from: Data("{}".utf8)) }
    }
}
