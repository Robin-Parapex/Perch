import Foundation
import PerchCore
import Testing

@testable import PerchPlex

private let owner = PlexUserID("1001")
private let partner = PlexUserID("1002")
private let kid = PlexUserID("1003")
private let switchPath = "/api/home/users/1002/switch"
private let kidSwitchPath = "/api/home/users/1003/switch"
private let switchOK = FakeTransport.Reply.response(status: 200, body: Fixture.data("switch_ok"))

private func signedIn() async throws -> (SessionRig, PlexSession) {
    let rig = SessionRig()
    await rig.transport.scriptHealthyAccount()
    let session = rig.makeSession()
    try await session.signIn(accountToken: "TOKEN-OWNER")
    return (rig, session)
}

@Suite("Home user cache", .timeLimit(.minutes(1)))
struct PlexHomeUserCacheTests {
    @Test func theCacheRoundTripsAndHoldsNoToken() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }

        let data = try #require(rig.defaults.data(forKey: PlexSession.DefaultsKey.homeUsersCache))
        let text = String(decoding: data, as: UTF8.self)
        for secret in ["TOKEN-OWNER", "FAKE-TOKEN", "FAKE-SERVER", "token", "Token"] {
            #expect(!text.contains(secret), "cache must not hold \(secret)")
        }

        // A relaunch with plex.tv never asked still knows the household.
        let relaunch = rig.makeSession(transport: FakeTransport())
        let users = await relaunch.cachedHomeUsers()
        #expect(users.map(\.id) == ["1001", "1002", "1003", "1004"])
        #expect(users.map(\.title) == ["Owner", "Partner", "Little One", "Teen"])
        #expect(users.map(\.protected) == [false, true, false, true])
        #expect(users.map(\.restricted) == [false, false, true, true])
        #expect(users.first?.admin == true)
        #expect(users.first?.thumb == "https://plex.tv/users/aaa/avatar")
        #expect(await session.cachedHomeUsers().map(\.id) == users.map(\.id))
    }

    @Test func signOutClearsTheCache() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        await session.signOut()
        #expect(rig.defaults.data(forKey: PlexSession.DefaultsKey.homeUsersCache) == nil)
        #expect(await session.cachedHomeUsers().isEmpty)
    }
}

@Suite("Policy-checked profile switching", .timeLimit(.minutes(1)))
struct PlexPolicySwitchTests {
    private let adminPINValue = "2580"

    private func makeAdmin(_ rig: SessionRig) async throws -> AdminPIN {
        let admin = AdminPIN(
            secrets: rig.secrets, keyValues: InMemoryKeyValueStore(), plexVerifier: nil, ownerHasPlexPIN: false)
        try await admin.setPerchPIN(adminPINValue)
        return admin
    }

    /// Signed in as the owner with an Admin PIN set.
    private func rigWithAdmin() async throws -> (SessionRig, PlexSession, AdminPIN) {
        let rig = SessionRig()
        await rig.transport.scriptHealthyAccount()
        let admin = try await makeAdmin(rig)
        let session = rig.makeSession(adminPIN: admin)
        try await session.signIn(accountToken: "TOKEN-OWNER")
        return (rig, session, admin)
    }

    @Test func aStalePickerCannotSkipTheAdminPINForAnUnprotectedAdult() async throws {
        // Replies for /api/v2/home/users: sign-in, the switch to the kid, then the stale-switch refresh
        // in which the partner's Plex PIN has been removed.
        let original = Fixture.data("home_users")
        let unprotected = Data(
            String(decoding: original, as: UTF8.self)
                .replacingOccurrences(
                    of: "\"protected\": true, \"home\": true, \"restrictionProfile\": null",
                    with: "\"protected\": false, \"home\": true, \"restrictionProfile\": null"
                ).utf8)
        #expect(unprotected != original)
        let rig = SessionRig()
        await rig.transport.script(
            path: "/api/v2/home/users",
            .response(status: 200, body: original), .response(status: 200, body: original),
            .response(status: 200, body: unprotected))
        await rig.transport.scriptHealthyAccount()
        let admin = try await makeAdmin(rig)
        let session = rig.makeSession(adminPIN: admin)
        defer { rig.cleanup() }
        try await session.signIn(accountToken: "TOKEN-OWNER")
        await rig.transport.scriptSwitch(userID: "1003", switchOK)
        await rig.transport.scriptSwitch(userID: "1002", switchOK)
        try await session.switchProfile(to: kid, pin: nil)
        #expect(await session.currentProfile()?.id == kid)

        // The picker still thinks the partner is protected.
        let stale = try #require(await session.cachedHomeUsers().first { $0.id == "1002" })
        #expect(stale.protected)
        let asked = await session.switchRequirement(for: stale)
        #expect(asked == .targetPlexPIN)

        await #expect(throws: PlexError.requirementChanged(.adminPIN)) {
            try await session.switchProfile(to: partner, pin: "1234", expecting: asked)
        }
        // Not even without the UI's expectation can any 4 digits do: they are checked as the Admin PIN.
        await #expect(throws: PlexError.pinIncorrect) {
            try await session.switchProfile(to: partner, pin: "1234")
        }
        #expect(await rig.transport.requests(forPath: switchPath).isEmpty)
        #expect(await session.currentProfile()?.id == kid)
    }

    @Test func aKidToAnUnprotectedAdultNeedsTheAdminPIN() async throws {
        let (rig, session, _) = try await rigWithAdmin()
        defer { rig.cleanup() }
        await rig.transport.scriptSwitch(userID: "1003", switchOK)
        try await session.switchProfile(to: kid, pin: nil)

        let ownerUser = try #require(await session.cachedHomeUsers().first { $0.id == "1001" })
        #expect(await session.switchRequirement(for: ownerUser) == .adminPIN)
        await #expect(throws: PlexError.pinRequired) { try await session.switchProfile(to: owner, pin: nil) }
        #expect(await session.currentProfile()?.id == kid)

        try await session.switchProfile(to: owner, pin: adminPINValue, expecting: .adminPIN)
        #expect(await session.currentProfile()?.id == owner)
    }

    @Test func aWrongAdminPINDoesNotSwitchAndCountsTowardTheLockout() async throws {
        let (rig, session, admin) = try await rigWithAdmin()
        defer { rig.cleanup() }
        await rig.transport.scriptSwitch(userID: "1003", switchOK)
        try await session.switchProfile(to: kid, pin: nil)

        await #expect(throws: PlexError.pinIncorrect) { try await session.switchProfile(to: owner, pin: "0000") }
        #expect(await session.currentProfile()?.id == kid)
        #expect(await admin.lockoutState().failedAttempts == 1)

        var locked = false
        for _ in 0..<PINLockout.maxAttempts {
            do { try await session.switchProfile(to: owner, pin: "0000") } catch PlexError.lockedOut {
                locked = true
            } catch PlexError.pinIncorrect {}
        }
        #expect(locked)
        #expect(await session.currentProfile()?.id == kid)
    }

    @Test func withoutAnAdminPINHolderAKidCannotLeave() async throws {
        let rig = SessionRig()
        await rig.transport.scriptHealthyAccount()
        let session = rig.makeSession()
        defer { rig.cleanup() }
        try await session.signIn(accountToken: "TOKEN-OWNER")
        await rig.transport.scriptSwitch(userID: "1003", switchOK)
        try await session.switchProfile(to: kid, pin: nil)

        await #expect(throws: PlexError.adminVerificationRequired) {
            try await session.switchProfile(to: owner, pin: adminPINValue)
        }
        #expect(await session.currentProfile()?.id == kid)
    }

    @Test func anUnknownStartingRoleCountsAsAKid() async throws {
        let (rig, first, admin) = try await rigWithAdmin()
        defer { rig.cleanup() }
        _ = first
        // A relaunch that has not resumed, whose last profile has no stored settings.
        let session = rig.makeSession(adminPIN: admin)
        rig.defaults.set("9999", forKey: PlexSession.DefaultsKey.lastProfileID)
        #expect(await session.currentProfile() == nil)

        let ownerUser = try #require(await session.cachedHomeUsers().first { $0.id == "1001" })
        #expect(await session.switchRequirement(for: ownerUser) == .adminPIN)
        await #expect(throws: PlexError.pinRequired) { try await session.switchProfile(to: owner, pin: nil) }
        #expect(await rig.transport.requests(forPath: switchPath).isEmpty)
    }

    @Test func adultToUnprotectedAdultNeedsNothing() async throws {
        let (rig, session, _) = try await rigWithAdmin()
        defer { rig.cleanup() }
        await rig.transport.scriptSwitch(userID: "1002", switchOK)
        try await session.switchProfile(to: partner, pin: "1234", expecting: .targetPlexPIN)
        #expect(await session.currentProfile()?.id == partner)

        let ownerUser = try #require(await session.cachedHomeUsers().first { $0.id == "1001" })
        #expect(await session.switchRequirement(for: ownerUser) == .none)
        try await session.switchProfile(to: owner, pin: nil, expecting: SwitchRequirement.none)
        #expect(await session.currentProfile()?.id == owner)
    }

    @Test func aProtectedTargetStillNeedsItsPIN() async throws {
        let (rig, session, _) = try await rigWithAdmin()
        defer { rig.cleanup() }
        await rig.transport.scriptSwitch(userID: "1002", switchOK)
        for pin in [nil, ""] as [String?] {
            await #expect(throws: PlexError.pinRequired) { try await session.switchProfile(to: partner, pin: pin) }
        }
        #expect(await rig.transport.requests(forPath: switchPath).isEmpty)
        #expect(await session.currentProfile()?.id == owner)
    }

    @Test func offlineSwitchThrowsUnreachableAndKeepsTheProfile() async throws {
        let (rig, first) = try await signedIn()
        defer { rig.cleanup() }
        _ = first

        // Relaunch with plex.tv down and the server up.
        let relaunch = FakeTransport()
        await relaunch.script(path: "/identity", fixture: "identity")
        let down = FakeTransport.Reply.failure(.notConnectedToInternet)
        for path in ["/api/v2/user", "/api/v2/home/users", "/api/v2/resources", kidSwitchPath] {
            await relaunch.script(path: path, down)
        }
        let session = rig.makeSession(transport: relaunch)
        #expect(await session.resume())
        #expect(await session.currentProfile()?.id == owner)

        await #expect(throws: PlexError.plexTVUnreachable) {
            try await session.switchProfile(to: kid, pin: nil)
        }

        #expect(await session.currentProfile()?.id == owner)
        guard case .ready(let profile, _) = await session.snapshot().state else {
            Issue.record("expected the owner to stay ready")
            return
        }
        #expect(profile.id == owner)
        #expect(rig.defaults.string(forKey: PlexSession.DefaultsKey.lastProfileID) == "1001")
        #expect(await session.snapshot().plexTVReachable == false)
    }
}

@Suite("Server images", .timeLimit(.minutes(1)))
struct PlexServerImageTests {
    private let listJSON = """
        {"MediaContainer":{"size":7,"Metadata":[
        {"title":"A","art":"/library/metadata/1/art/10","contentRating":"U"},
        {"title":"B"},
        {"title":"C","art":"/library/metadata/1/art/10","contentRating":"G"},
        {"title":"D","art":"/library/metadata/4/art/40","contentRating":"gb/PG"},
        {"title":"E","art":"/library/metadata/5/art/50","contentRating":"R"},
        {"title":"F","art":"/library/metadata/6/art/60"},
        {"title":"G","art":"/library/metadata/7/art/70","contentRating":"TV-MA-ish"}]}}
        """

    @Test func theTokenTravelsOnlyInTheHeader() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        await rig.transport.script(
            path: "/library/recentlyAdded", .response(status: 200, body: Data(listJSON.utf8)))
        await rig.transport.script(
            path: "/library/metadata/1/art/10", .response(status: 200, body: Data([1, 2, 3])))

        let paths = try await session.libraryArt(limit: 5, ceiling: .pg)
        #expect(paths == ["/library/metadata/1/art/10", "/library/metadata/4/art/40"])
        #expect(paths.allSatisfy { !$0.contains("TOKEN") && !$0.contains("?") })

        let image = try await session.imageData(for: paths[0])
        #expect(image == Data([1, 2, 3]))

        for path in ["/library/recentlyAdded", "/library/metadata/1/art/10"] {
            let request = try #require(await rig.transport.requests(forPath: path).last)
            #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "FAKE-SERVER-TOKEN-1")
            let url = request.url?.absoluteString ?? ""
            #expect(!url.contains("FAKE-SERVER-TOKEN-1") && !url.localizedCaseInsensitiveContains("token"))
        }
    }

    @Test func artIsFilteredByRatingAndUnratedOrUnknownIsDropped() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        await rig.transport.script(
            path: "/library/recentlyAdded", .response(status: 200, body: Data(listJSON.utf8)))

        // Default is the strictest: only U.
        #expect(try await session.libraryArt(limit: 9) == ["/library/metadata/1/art/10"])
        #expect(
            try await session.libraryArt(limit: 9, ceiling: .fifteen)
                == ["/library/metadata/1/art/10", "/library/metadata/4/art/40", "/library/metadata/5/art/50"])
        // The household ceiling comes from the stored profiles (the little one is U).
        #expect(await session.householdArtCeiling() == .u)
    }

    @Test func aPathThatIsNotAPlainServerPathIsRefusedWithoutARequest() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        let before = await rig.transport.requests.count

        for path in [
            "http://evil.example/x", "//evil.example/x", "relative/path",
            "/library/metadata/1/art/10?X-Plex-Token=abc",
        ] {
            await #expect(throws: PlexError.unauthorized) { _ = try await session.imageData(for: path) }
        }
        #expect(await rig.transport.requests.count == before)
    }
}
