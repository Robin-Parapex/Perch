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
    @Test func adminPINRequirementWithoutAcceptedVerificationIsRefused() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        await rig.transport.scriptSwitch(userID: "1003", switchOK)
        let before = await rig.transport.requests.count

        for verification in [nil, PINResult.rejected(attemptsLeft: 2), .lockedOut(until: fixedNow), .setupRequired] {
            await #expect(throws: PlexError.adminVerificationRequired) {
                try await session.switchProfile(
                    to: kid, pin: nil, requirement: .adminPIN, adminVerification: verification)
            }
        }
        #expect(await rig.transport.requests.count == before)
        #expect(await session.currentProfile()?.id == owner)
    }

    @Test func adminPINRequirementWithAcceptedVerificationSwitches() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        await rig.transport.scriptSwitch(userID: "1003", switchOK)

        try await session.switchProfile(
            to: kid, pin: nil, requirement: .adminPIN, adminVerification: .accepted)

        #expect(await session.currentProfile()?.id == kid)
    }

    @Test func targetPINRequirementWithoutAPINIsRefused() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        await rig.transport.scriptSwitch(userID: "1002", switchOK)
        let before = await rig.transport.requests.count

        for pin in [nil, ""] as [String?] {
            await #expect(throws: PlexError.pinRequired) {
                try await session.switchProfile(to: partner, pin: pin, requirement: .targetPlexPIN)
            }
        }
        #expect(await rig.transport.requests.count == before)
        #expect(await rig.transport.requests(forPath: switchPath).isEmpty)
        #expect(await session.currentProfile()?.id == owner)
    }

    @Test func targetPINRequirementWithThePINSwitches() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        await rig.transport.scriptSwitch(userID: "1002", switchOK)

        try await session.switchProfile(to: partner, pin: "1234", requirement: .targetPlexPIN)

        #expect(await session.currentProfile()?.id == partner)
    }

    @Test func aNoneDecisionStillCannotOpenAProtectedUserWithoutItsPIN() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        await rig.transport.scriptSwitch(userID: "1002", switchOK)

        await #expect(throws: PlexError.pinRequired) {
            try await session.switchProfile(to: partner, pin: nil, requirement: .none)
        }
        #expect(await rig.transport.requests(forPath: switchPath).isEmpty)
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
            try await session.switchProfile(to: kid, pin: nil, requirement: .none)
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
        {"MediaContainer":{"size":3,"Metadata":[
        {"title":"A","art":"/library/metadata/1/art/10"},
        {"title":"B"},
        {"title":"C","art":"/library/metadata/1/art/10"},
        {"title":"D","art":"/library/metadata/4/art/40"}]}}
        """

    @Test func theTokenTravelsOnlyInTheHeader() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        await rig.transport.script(
            path: "/library/recentlyAdded", .response(status: 200, body: Data(listJSON.utf8)))
        await rig.transport.script(
            path: "/library/metadata/1/art/10", .response(status: 200, body: Data([1, 2, 3])))

        let paths = try await session.libraryArt(limit: 5)
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
