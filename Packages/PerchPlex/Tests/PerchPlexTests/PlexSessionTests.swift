import Foundation
import PerchCore
import Testing

@testable import PerchPlex

private let owner = PlexUserID("1001")
private let partner = PlexUserID("1002")
private let loungeURL = URL(string: "http://192.168.1.20:32400")!
private let switchPath = "/api/home/users/1002/switch"
private func serverTokenKey(_ id: PlexUserID) -> SecretKey {
    .module(ModuleID("plex"), "server.\(id.rawValue)")
}

private func switchOK() -> FakeTransport.Reply { .response(status: 200, body: Fixture.data("switch_ok")) }

/// A rig signed in as the owner on the single healthy server ("TOKEN-OWNER" is the account token).
private func signedIn(resources: String = "resources_single") async throws -> (SessionRig, PlexSession) {
    let rig = SessionRig()
    await rig.transport.scriptHealthyAccount(resources: resources)
    let session = rig.makeSession()
    try await session.signIn(accountToken: "TOKEN-OWNER")
    return (rig, session)
}

@Suite("Session sign-in", .timeLimit(.minutes(1)))
struct PlexSessionSignInTests {
    @Test func oneServerIsChosenAutomaticallyAndTheOwnerTokenIsStored() async throws {
        let rig = SessionRig()
        defer { rig.cleanup() }
        await rig.transport.scriptHealthyAccount()
        let session = rig.makeSession()

        let servers = try await session.signIn(accountToken: "TOKEN-OWNER")

        #expect(servers.map(\.name) == ["Lounge Server"])
        let snapshot = await session.snapshot()
        guard case .ready(let profile, let server) = snapshot.state else {
            Issue.record("expected ready, got \(snapshot.state)")
            return
        }
        #expect(profile.id == owner)
        #expect(profile.isOwner)
        #expect(server.machineID == "FAKE-MACHINE-LOUNGE")
        #expect(server.baseURL == loungeURL)
        #expect(server.tier == .local)
        #expect(try rig.secrets.string(for: .plexOwnerToken) == "TOKEN-OWNER")
        #expect(try rig.secrets.string(for: .plexUserToken(owner)) == "TOKEN-OWNER")
        #expect(try rig.secrets.string(for: serverTokenKey(owner)) == "FAKE-SERVER-TOKEN-1")
        #expect(rig.defaults.string(forKey: PlexSession.DefaultsKey.lastProfileID) == "1001")
        let doc = await rig.settings.document
        #expect(doc.household.ownerPlexUserID == owner)
        #expect(doc.modules[ModuleID("plex")]?.config["machineID"] == "FAKE-MACHINE-LOUNGE")
        #expect(doc.modules[ModuleID("plex")]?.config["lastURI"] == loungeURL.absoluteString)
    }

    @Test func severalServersWaitForAChoice() async throws {
        let rig = SessionRig()
        defer { rig.cleanup() }
        await rig.transport.scriptHealthyAccount(resources: "resources")
        let session = rig.makeSession()

        let servers = try await session.signIn(accountToken: "TOKEN-OWNER")

        #expect(servers.map(\.name) == ["Lounge Server", "Garage Server"])
        #expect(await session.snapshot().state == .connecting)
        #expect(try rig.secrets.string(for: .plexOwnerToken) == "TOKEN-OWNER")

        try await session.choose(server: servers[0])

        guard case .ready(_, let server) = await session.snapshot().state else {
            Issue.record("expected ready after choosing")
            return
        }
        #expect(server.name == "Lounge Server")
        #expect(try rig.secrets.string(for: serverTokenKey(owner)) == "FAKE-SERVER-TOKEN-1")
    }

    @Test func aWrongTokenIsUnauthorizedAndNothingIsStored() async throws {
        let rig = SessionRig()
        defer { rig.cleanup() }
        await rig.transport.scriptHealthyAccount(userStatus: 401)
        let session = rig.makeSession()

        await #expect(throws: PlexError.unauthorized) {
            try await session.signIn(accountToken: "BAD")
        }

        #expect(await session.snapshot().state == .signedOut)
        #expect(try rig.secrets.string(for: .plexOwnerToken) == nil)
        #expect(try rig.secrets.string(for: .plexUserToken(owner)) == nil)
        #expect(rig.defaults.string(forKey: PlexSession.DefaultsKey.lastProfileID) == nil)
        #expect(await rig.settings.document.profiles.isEmpty)
    }
}

@Suite("Session manual sign-in", .timeLimit(.minutes(1)))
struct PlexSessionManualTests {
    @Test func aGoodAddressAndTokenGoReady() async throws {
        let rig = SessionRig()
        defer { rig.cleanup() }
        await rig.transport.scriptHealthyAccount()
        let session = rig.makeSession()

        try await session.signInManually(address: "192.168.1.20", token: "TOKEN-MANUAL")

        guard case .ready(let profile, let server) = await session.snapshot().state else {
            Issue.record("expected ready")
            return
        }
        #expect(profile.id == owner)
        #expect(server.baseURL == loungeURL)
        #expect(await session.snapshot().profileSwitchingAvailable)
        #expect(try rig.secrets.string(for: .plexOwnerToken) == "TOKEN-MANUAL")
        #expect(try rig.secrets.string(for: serverTokenKey(owner)) == "TOKEN-MANUAL")
        #expect(await rig.settings.document.modules[ModuleID("plex")]?.config["manualURL"] == loungeURL.absoluteString)
        // The token was checked against a call that needs one, not only /identity.
        let sections = try #require(await rig.transport.requests(forPath: "/library/sections").first)
        #expect(sections.value(forHTTPHeaderField: "X-Plex-Token") == "TOKEN-MANUAL")
        let identity = try #require(await rig.transport.requests(forPath: "/identity").first)
        #expect(identity.value(forHTTPHeaderField: "X-Plex-Token") == nil)
    }

    @Test func aWrongTokenIsUnauthorizedAndNotKept() async throws {
        let rig = SessionRig()
        defer { rig.cleanup() }
        await rig.transport.scriptHealthyAccount(sectionsStatus: 401)
        let session = rig.makeSession()

        await #expect(throws: PlexError.unauthorized) {
            try await session.signInManually(address: "192.168.1.20", token: "BAD")
        }

        #expect(await session.snapshot().state == .signedOut)
        #expect(try rig.secrets.string(for: .plexOwnerToken) == nil)
    }

    @Test func aDeadAddressIsServerUnreachable() async throws {
        let rig = SessionRig()
        defer { rig.cleanup() }
        await rig.transport.scriptHealthyAccount(identityFailure: .cannotConnectToHost)
        let session = rig.makeSession()

        await #expect(throws: PlexError.serverUnreachable) {
            try await session.signInManually(address: "192.168.1.99", token: "TOKEN-MANUAL")
        }

        #expect(await session.snapshot().state == .signedOut)
        #expect(try rig.secrets.string(for: .plexOwnerToken) == nil)
    }

    @Test func aServerOnlyTokenGivesOneProfileAndNoSwitching() async throws {
        let rig = SessionRig()
        defer { rig.cleanup() }
        await rig.transport.scriptHealthyAccount(userStatus: 401)
        let session = rig.makeSession()

        try await session.signInManually(address: "192.168.1.20", token: "SERVER-ONLY")

        let snapshot = await session.snapshot()
        guard case .ready(let profile, _) = snapshot.state else {
            Issue.record("expected ready")
            return
        }
        #expect(profile.id == PlexSession.singleProfileID)
        #expect(profile.isOwner)
        #expect(profile.restriction == .unrestricted)
        #expect(snapshot.profileSwitchingAvailable == false)
        #expect(rig.defaults.bool(forKey: PlexSession.DefaultsKey.singleProfile))
        let users = try await session.homeUsers()
        #expect(users.map(\.id) == ["manual"])
    }
}

@Suite("Session profile switching", .timeLimit(.minutes(1)))
struct PlexSessionSwitchingTests {
    @Test func theRightPINCommitsTheProfile() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        await rig.transport.scriptSwitch(userID: "1002", switchOK())

        try await session.switchProfile(to: partner, pin: "1234")

        #expect(await session.currentProfile()?.id == partner)
        guard case .ready(let profile, _) = await session.snapshot().state else {
            Issue.record("expected ready")
            return
        }
        #expect(profile.id == partner)
        #expect(try rig.secrets.string(for: .plexUserToken(partner)) == "FAKE-TOKEN-PROFILE-1")
        #expect(try rig.secrets.string(for: serverTokenKey(partner)) == "FAKE-SERVER-TOKEN-1")
        #expect(rig.defaults.string(forKey: PlexSession.DefaultsKey.lastProfileID) == "1002")
        // The owner token is untouched.
        #expect(try rig.secrets.string(for: .plexOwnerToken) == "TOKEN-OWNER")
    }

    @Test func anXMLSwitchResponseCommitsTheProfile() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        let xml = #"<?xml version="1.0" encoding="UTF-8"?><user id="1002" authenticationToken="FAKE-TOKEN-PROFILE-1"/>"#
        await rig.transport.scriptSwitch(userID: "1002", .response(status: 201, body: Data(xml.utf8)))

        try await session.switchProfile(to: partner, pin: "1234")

        #expect(await session.currentProfile()?.id == partner)
        #expect(try rig.secrets.string(for: .plexUserToken(partner)) == "FAKE-TOKEN-PROFILE-1")
    }

    @Test func aWrongPINIsRefusedAndChangesNothing() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        await rig.transport.scriptSwitch(userID: "1002", .response(status: 401, body: Data()))

        await #expect(throws: PlexError.pinIncorrect) {
            try await session.switchProfile(to: partner, pin: "0000")
        }

        #expect(await session.currentProfile()?.id == owner)
        #expect(rig.defaults.string(forKey: PlexSession.DefaultsKey.lastProfileID) == "1001")
        #expect(try rig.secrets.string(for: .plexUserToken(partner)) == nil)
        #expect(try rig.secrets.string(for: serverTokenKey(partner)) == nil)
        guard case .ready(let profile, _) = await session.snapshot().state else {
            Issue.record("expected the owner to stay ready")
            return
        }
        #expect(profile.id == owner)
        #expect(rig.lockout()?.failedAttempts == 1)
    }

    @Test func aTransportFailureIsUnreachableAndNeverCountsAsAnAttempt() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        let down = FakeTransport.Reply.failure(.notConnectedToInternet)
        // Six outages (more than the five-try limit), then plex.tv is back.
        await rig.transport.script(
            path: switchPath, method: "POST", down, down, down, down, down, down, switchOK())

        for _ in 0..<6 {
            await #expect(throws: PlexError.plexTVUnreachable) {
                try await session.switchProfile(to: partner, pin: "1234")
            }
        }
        #expect(await session.snapshot().plexTVReachable == false)
        #expect((rig.lockout()?.failedAttempts ?? 0) == 0)
        #expect(await session.currentProfile()?.id == owner)

        // Not locked out: the right PIN still works.
        try await session.switchProfile(to: partner, pin: "1234")
        #expect(await session.currentProfile()?.id == partner)
    }

    @Test func fiveWrongPINsLockOutAndTheSixthNeverReachesTheNetwork() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        await rig.transport.scriptSwitch(userID: "1002", .response(status: 401, body: Data()))
        let until = fixedNow.addingTimeInterval(PINLockout.baseLockout)

        for _ in 0..<4 {
            await #expect(throws: PlexError.pinIncorrect) {
                try await session.switchProfile(to: partner, pin: "0000")
            }
        }
        await #expect(throws: PlexError.lockedOut(until: until)) {
            try await session.switchProfile(to: partner, pin: "0000")
        }

        let before = await rig.transport.requests.count
        await #expect(throws: PlexError.lockedOut(until: until)) {
            try await session.switchProfile(to: partner, pin: "1234")
        }
        #expect(await rig.transport.requests.count == before)
        #expect(await session.currentProfile()?.id == owner)
    }

    @Test func aProtectedUserWithoutAPINNeedsOne() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        await rig.transport.scriptSwitch(userID: "1002", switchOK())

        await #expect(throws: PlexError.pinRequired) {
            try await session.switchProfile(to: partner, pin: nil)
        }

        #expect(await rig.transport.requests(forPath: switchPath).isEmpty)
        #expect(await session.currentProfile()?.id == owner)
    }
}

@Suite("Session resume", .timeLimit(.minutes(1)))
struct PlexSessionResumeTests {
    @Test func resumesTheLastProfileWithPlexTVDownUsingStoredTokens() async throws {
        let (rig, first) = try await signedIn()
        defer { rig.cleanup() }
        await rig.transport.scriptSwitch(userID: "1002", switchOK())
        try await first.switchProfile(to: partner, pin: "1234")

        // Relaunch: a new session over the same stores; plex.tv is down, the server is up.
        let relaunch = FakeTransport()
        await relaunch.script(path: "/identity", fixture: "identity")
        for path in ["/api/v2/user", "/api/v2/home/users", "/api/v2/resources", switchPath] {
            await relaunch.script(path: path, .failure(.notConnectedToInternet))
        }
        let session = rig.makeSession(transport: relaunch)

        #expect(await session.resume() == true)

        guard case .ready(let profile, let server) = await session.snapshot().state else {
            Issue.record("expected ready, got \(await session.snapshot().state)")
            return
        }
        #expect(profile.id == partner)
        #expect(server.baseURL == loungeURL)
        // No PIN was asked for, and the launch did not wait on plex.tv.
        #expect(await relaunch.requests(forPath: switchPath).isEmpty)
        #expect(await relaunch.requests(forPath: "/api/v2/resources").isEmpty)

        // Once plex.tv is tried and fails, the session says PIN checks are unavailable but stays ready.
        await #expect(throws: PlexError.plexTVUnreachable) { try await session.homeUsers() }
        let snapshot = await session.snapshot()
        #expect(snapshot.plexTVReachable == false)
        if case .ready(let still, _) = snapshot.state { #expect(still.id == partner) } else {
            Issue.record("profile should keep playing while plex.tv is down")
        }
    }

    /// A relaunch over the same stores: the server answers, plex.tv is down or up with `homeUsers`.
    private func relaunch(
        _ rig: SessionRig, plexTVDown: Bool, homeUsersBody: Data? = nil
    ) async -> PlexSession {
        let transport = FakeTransport()
        await transport.script(path: "/identity", fixture: "identity")
        if plexTVDown {
            for path in ["/api/v2/user", "/api/v2/home/users", "/api/v2/resources"] {
                await transport.script(path: path, .failure(.notConnectedToInternet))
            }
        } else {
            await transport.script(path: "/api/v2/user", fixture: "user")
            await transport.script(
                path: "/api/v2/home/users", .response(status: 200, body: homeUsersBody ?? Fixture.data("home_users")))
            await transport.script(path: "/api/v2/resources", fixture: "resources_single")
        }
        return rig.makeSession(transport: transport)
    }

    @Test func refreshAfterResumeWithPlexTVDownFlagsItAndKeepsTheProfile() async throws {
        let (rig, _) = try await signedIn()
        defer { rig.cleanup() }
        let session = await relaunch(rig, plexTVDown: true)
        #expect(await session.resume() == true)
        #expect(await session.snapshot().plexTVReachable == true)  // resume alone never asked plex.tv

        await session.refreshFromPlexTV()

        let snapshot = await session.snapshot()
        #expect(snapshot.plexTVReachable == false)
        if case .ready(let profile, _) = snapshot.state { #expect(profile.id == owner) } else {
            Issue.record("profile should stay ready while plex.tv is down")
        }
        #expect(await session.currentProfile()?.id == owner)
    }

    @Test func refreshAfterResumeWithPlexTVUpFlagsItAndSyncsRestrictions() async throws {
        let (rig, _) = try await signedIn()
        defer { rig.cleanup() }
        let before = await rig.settings.document.profiles[PlexUserID("1003")]?.plexRestriction
        #expect(before == .littleKid)
        // plex.tv now says the little one is a teen.
        let changed = String(decoding: Fixture.data("home_users"), as: UTF8.self)
            .replacingOccurrences(of: "little_kid", with: "teen")
        let session = await relaunch(rig, plexTVDown: false, homeUsersBody: Data(changed.utf8))
        #expect(await session.resume() == true)

        await session.refreshFromPlexTV()

        #expect(await session.snapshot().plexTVReachable == true)
        #expect(await session.currentProfile()?.id == owner)
        #expect(await rig.settings.document.profiles[PlexUserID("1003")]?.plexRestriction == .teen)
    }

    @Test func switchingWhilePlexTVIsDownIsUnreachableNotAWrongPIN() async throws {
        let (rig, first) = try await signedIn()
        defer { rig.cleanup() }
        _ = first
        let relaunch = FakeTransport()
        await relaunch.script(path: "/identity", fixture: "identity")
        for path in ["/api/v2/user", "/api/v2/home/users", "/api/v2/resources", switchPath] {
            await relaunch.script(path: path, .failure(.notConnectedToInternet))
        }
        let session = rig.makeSession(transport: relaunch)
        #expect(await session.resume() == true)

        await #expect(throws: PlexError.plexTVUnreachable) {
            try await session.switchProfile(to: partner, pin: "1234")
        }
        #expect(await session.currentProfile()?.id == owner)
        #expect((rig.lockout()?.failedAttempts ?? 0) == 0)
    }

    // A remembered public address: resume goes ready on it at once, then looks for the LAN address.
    private static let publicURL = URL(string: "https://203-0-113-5.abc.plex.direct:32400")!

    private func relaunchOnPublicAddress(
        _ rig: SessionRig, resources: RoutedTransport.Reply, resourcesDelay: Duration = .zero
    ) async throws -> PlexSession {
        try await rig.settings.update { doc in
            doc.modules[ModuleID("plex")]?.config["lastURI"] = Self.publicURL.absoluteString
        }
        let transport = RoutedTransport()
        let identity = Fixture.data("identity")
        await transport.route(host: "203-0-113-5.abc.plex.direct", .ok(identity))
        await transport.route(host: "192.168.1.20", .ok(identity))
        await transport.route(
            host: "clients.plex.tv", path: "/api/v2/resources", delay: resourcesDelay, resources)
        return rig.makeSession(transport: transport)
    }

    private func readyServer(_ session: PlexSession) async -> PlexConnectedServer? {
        if case .ready(_, let server) = await session.snapshot().state { return server }
        Issue.record("expected ready, got \(await session.snapshot().state)")
        return nil
    }

    private func savedURI(_ rig: SessionRig) async -> String? {
        await rig.settings.document.modules[ModuleID("plex")]?.config["lastURI"]
    }

    @Test func resumeOnAPublicAddressGoesReadyWithoutWaitingForPlexTV() async throws {
        let (rig, _) = try await signedIn()
        defer { rig.cleanup() }
        // plex.tv never answers within the test: a resume that waited for it would hit the time limit.
        let session = try await relaunchOnPublicAddress(
            rig, resources: .ok(Fixture.data("resources_single")), resourcesDelay: .seconds(3600))

        #expect(await session.resume() == true)

        let server = await readyServer(session)
        #expect(server?.baseURL == Self.publicURL)
        #expect(server?.tier == .remote)
    }

    @Test func theBackgroundCheckSwitchesToTheLocalAddressAndKeepsTheGeneration() async throws {
        let (rig, _) = try await signedIn()
        defer { rig.cleanup() }
        let session = try await relaunchOnPublicAddress(rig, resources: .ok(Fixture.data("resources_single")))
        #expect(await session.resume() == true)
        let generation = await session.currentGeneration()

        await session.awaitConnectionUpgrade()

        let server = await readyServer(session)
        #expect(server?.baseURL == loungeURL)
        #expect(server?.tier == .local)
        #expect(await savedURI(rig) == loungeURL.absoluteString)
        // Same server: work already started (playback, timeline reports) stays valid.
        #expect(await session.currentGeneration() == generation)
    }

    @Test func aFailedBackgroundCheckLeavesThePublicAddressAndReachability() async throws {
        let (rig, _) = try await signedIn()
        defer { rig.cleanup() }
        let session = try await relaunchOnPublicAddress(rig, resources: .fail(.notConnectedToInternet))
        #expect(await session.resume() == true)

        await session.awaitConnectionUpgrade()

        let server = await readyServer(session)
        #expect(server?.baseURL == Self.publicURL)
        #expect(server?.tier == .remote)
        #expect(await savedURI(rig) == Self.publicURL.absoluteString)
        #expect(await session.snapshot().plexTVReachable == true)
    }

    @Test func nothingSavedReturnsFalse() async {
        let rig = SessionRig()
        defer { rig.cleanup() }
        let session = rig.makeSession()

        #expect(await session.resume() == false)
        #expect(await session.snapshot().state == .signedOut)
        #expect(await rig.transport.requests.isEmpty)
    }
}

@Suite("Session secrecy", .timeLimit(.minutes(1)))
struct PlexSessionSecrecyTests {
    private static let tokens = ["TOKEN-OWNER", "FAKE-TOKEN-PROFILE-1", "FAKE-SERVER-TOKEN-1"]

    @Test func noTokenAppearsInAnyURL() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        await rig.transport.scriptSwitch(userID: "1002", switchOK())
        try await session.switchProfile(to: partner, pin: "1234")

        let requests = await rig.transport.requests
        #expect(requests.count > 5)
        for request in requests {
            let url = try #require(request.url).absoluteString
            for token in Self.tokens { #expect(!url.contains(token), "\(token) leaked into \(url)") }
            let names = URLComponents(string: url)?.queryItems?.map { $0.name.lowercased() } ?? []
            #expect(!names.contains { $0.contains("token") })
        }
        // Not vacuous: the tokens do travel, as headers.
        let sent = Set(requests.compactMap { $0.value(forHTTPHeaderField: "X-Plex-Token") })
        #expect(sent.contains("TOKEN-OWNER"))
        #expect(sent.contains("FAKE-TOKEN-PROFILE-1"))
    }

    @Test func theSavedServerChoiceContainsNoTokenValues() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        await rig.transport.scriptSwitch(userID: "1002", switchOK())
        try await session.switchProfile(to: partner, pin: "1234")

        let doc = await rig.settings.document
        let config = try #require(doc.modules[ModuleID("plex")]?.config)
        #expect(Set(config.keys).isSubset(of: ["machineID", "serverName", "lastURI", "manualURL"]))
        let json = String(decoding: try JSONEncoder().encode(doc), as: UTF8.self)
        for token in Self.tokens { #expect(!json.contains(token), "\(token) leaked into settings") }
        try doc.validate()
    }
}
