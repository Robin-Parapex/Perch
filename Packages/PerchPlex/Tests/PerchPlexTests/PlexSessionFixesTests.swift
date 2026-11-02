import Foundation
import PerchCore
import Testing

@testable import PerchPlex

private let owner = PlexUserID("1001")
private let partner = PlexUserID("1002")
private let kid = PlexUserID("1003")
private let switchOK = FakeTransport.Reply.response(status: 200, body: Fixture.data("switch_ok"))
private let unauthorized = FakeTransport.Reply.response(status: 401, body: Data())

/// A rig whose `/api/v2/user` answers `userReplies` in turn, then a healthy account.
private func rig(userReplies: [FakeTransport.Reply], sectionsStatus: Int = 200) async -> SessionRig {
    let rig = SessionRig()
    let t = rig.transport
    switch userReplies.count {
    case 1: await t.script(path: "/api/v2/user", userReplies[0])
    case 2: await t.script(path: "/api/v2/user", userReplies[0], userReplies[1])
    default: break
    }
    await t.scriptHealthyAccount(sectionsStatus: sectionsStatus)
    return rig
}

private func userOK() -> FakeTransport.Reply { .response(status: 200, body: Fixture.data("user")) }

private func expectReady(_ session: PlexSession, token: String?, rig: SessionRig) async throws {
    guard case .ready(let profile, _) = await session.snapshot().state else {
        Issue.record("expected ready, got \(await session.snapshot().state)")
        return
    }
    #expect(profile.id == owner)
    #expect(try rig.secrets.string(for: .plexOwnerToken) == token)
    #expect(rig.defaults.string(forKey: PlexSession.DefaultsKey.lastProfileID) == "1001")
}

@Suite("Failed re-sign-in keeps the existing sign-in", .timeLimit(.minutes(1)))
struct PlexReSignInTests {
    @Test func aFailedManualSignInKeepsAReadySession() async throws {
        // Sections answers 401 once the first (account-token) sign-in is done: only the manual route calls it.
        let rig = await rig(userReplies: [userOK()], sectionsStatus: 401)
        defer { rig.cleanup() }
        let session = rig.makeSession()
        try await session.signIn(accountToken: "TOKEN-OWNER")

        await #expect(throws: PlexError.unauthorized) {
            try await session.signInManually(address: "192.168.1.20", token: "BAD")
        }

        try await expectReady(session, token: "TOKEN-OWNER", rig: rig)
    }

    @Test func aFailedLinkSignInKeepsAReadySession() async throws {
        let rig = await rig(userReplies: [userOK(), unauthorized])
        defer { rig.cleanup() }
        let session = rig.makeSession()
        try await session.signIn(accountToken: "TOKEN-OWNER")

        await #expect(throws: PlexError.unauthorized) {
            try await session.signIn(accountToken: "TOKEN-LINKED-BAD")
        }

        try await expectReady(session, token: "TOKEN-OWNER", rig: rig)
    }

    @Test func aCancelledLinkSignInKeepsAReadySession() async throws {
        let rig = await rig(userReplies: [userOK(), .failure(.cancelled)])
        defer { rig.cleanup() }
        let session = rig.makeSession()
        try await session.signIn(accountToken: "TOKEN-OWNER")

        await #expect(throws: (any Error).self) {
            try await session.signIn(accountToken: "TOKEN-OTHER")
        }

        try await expectReady(session, token: "TOKEN-OWNER", rig: rig)
    }
}

@Suite("Owner is the Plex Home admin", .timeLimit(.minutes(1)))
struct PlexHomeOwnerTests {
    /// Account 1001 is a restricted Home member; 1002 is the admin.
    private static let body = Data(
        """
        {"id": 5000, "users": [
          {"id": 1001, "uuid": "u1", "title": "Owner", "admin": false, "restricted": true, "restrictionProfile": "little_kid"},
          {"id": 1002, "uuid": "u2", "title": "Partner", "admin": true}
        ]}
        """.utf8)

    @Test func aRestrictedNonAdminAccountIsRefusedAndNothingIsStored() async throws {
        let rig = SessionRig()
        defer { rig.cleanup() }
        await rig.transport.script(path: "/api/v2/home/users", .response(status: 200, body: Self.body))
        await rig.transport.scriptHealthyAccount()
        let session = rig.makeSession()

        await #expect(throws: PlexError.notHomeOwner) {
            try await session.signIn(accountToken: "TOKEN-KID")
        }

        #expect(await session.snapshot().state == .signedOut)
        #expect(try rig.secrets.string(for: .plexOwnerToken) == nil)
        #expect(await rig.settings.document.profiles.isEmpty)
        #expect(await rig.settings.document.household.ownerPlexUserID == nil)
    }

    @Test func theManualRouteWithANonAdminAccountTokenIsRefused() async throws {
        let rig = SessionRig()
        defer { rig.cleanup() }
        await rig.transport.script(path: "/api/v2/home/users", .response(status: 200, body: Self.body))
        await rig.transport.scriptHealthyAccount()
        let session = rig.makeSession()

        await #expect(throws: PlexError.notHomeOwner) {
            try await session.signInManually(address: "192.168.1.20", token: "TOKEN-KID")
        }

        #expect(await session.snapshot().state == .signedOut)
        #expect(try rig.secrets.string(for: .plexOwnerToken) == nil)
        #expect(await rig.settings.document.profiles.isEmpty)
    }

    @Test func theAdminOwnerStillSyncsAsAnUnrestrictedParent() async throws {
        let rig = SessionRig()
        defer { rig.cleanup() }
        await rig.transport.scriptHealthyAccount()
        let session = rig.makeSession()

        try await session.signIn(accountToken: "TOKEN-OWNER")

        let doc = await rig.settings.document
        #expect(doc.household.ownerPlexUserID == owner)
        #expect(doc.profiles[owner]?.plexRestriction == .unrestricted)
        #expect(doc.profiles[owner]?.role == .parent)
        #expect(doc.profiles[kid]?.plexRestriction == .littleKid)
    }
}

@Suite("Manual route fallback", .timeLimit(.minutes(1)))
struct PlexManualFallbackTests {
    @Test func plexTVBeingDownIsNotTreatedAsAServerOnlyToken() async throws {
        let rig = await rig(userReplies: [.failure(.notConnectedToInternet)])
        defer { rig.cleanup() }
        let session = rig.makeSession()

        await #expect(throws: PlexError.plexTVUnreachable) {
            try await session.signInManually(address: "192.168.1.20", token: "TOKEN-MANUAL")
        }

        #expect(await session.snapshot().state == .signedOut)
        #expect(try rig.secrets.string(for: .plexOwnerToken) == nil)
        #expect(rig.defaults.bool(forKey: PlexSession.DefaultsKey.singleProfile) == false)
    }

    @Test func aBrokenAccountAnswerIsNotTreatedAsAServerOnlyToken() async throws {
        let rig = await rig(userReplies: [.response(status: 200, body: Data("not json".utf8))])
        defer { rig.cleanup() }
        let session = rig.makeSession()

        await #expect(throws: (any Error).self) {
            try await session.signInManually(address: "192.168.1.20", token: "TOKEN-MANUAL")
        }

        #expect(await session.snapshot().state == .signedOut)
        #expect(try rig.secrets.string(for: .plexOwnerToken) == nil)
    }

    @Test func singleProfileLeavesNoOwnerIDAndLetsAPerchAdminPINBeSet() async throws {
        let rig = await rig(userReplies: [unauthorized])
        defer { rig.cleanup() }
        let admin = AdminPIN(
            secrets: rig.secrets, keyValues: InMemoryKeyValueStore(), plexVerifier: nil, ownerHasPlexPIN: true)
        #expect(await admin.source == .plexOwner)
        let session = rig.makeSession(adminPIN: admin)

        try await session.signInManually(address: "192.168.1.20", token: "SERVER-ONLY")

        #expect(await rig.settings.document.household.ownerPlexUserID == nil)
        #expect(await admin.source == .setupRequired)
        let current = await session.currentProfile()
        #expect(current?.id == PlexSession.singleProfileID)
        #expect(current?.isOwner == true)
        #expect(current?.restriction == .unrestricted)
    }
}

@Suite("Profile switching: lockout", .timeLimit(.minutes(1)))
struct PlexLockoutTests {
    private func signedIn(now: @escaping NowProvider = { fixedNow }) async throws -> (SessionRig, PlexSession) {
        let rig = SessionRig()
        await rig.transport.scriptHealthyAccount()
        let session = rig.makeSession(now: now)
        try await session.signIn(accountToken: "TOKEN-OWNER")
        return (rig, session)
    }

    @Test func aCorruptLockoutRecordLocksOnceAndThenExpires() async throws {
        final class Clock: @unchecked Sendable { var now = fixedNow }
        let clock = Clock()
        let (rig, session) = try await signedIn(now: { clock.now })
        defer { rig.cleanup() }
        rig.defaults.set(Data("garbage".utf8), forKey: PlexSession.DefaultsKey.profilePINLockout)
        await rig.transport.scriptSwitch(userID: "1002", switchOK)

        let until = fixedNow.addingTimeInterval(PINLockout.baseLockout)
        await #expect(throws: PlexError.lockedOut(until: until)) {
            try await session.switchProfile(to: partner, pin: "1234")
        }
        clock.now = until.addingTimeInterval(1)

        try await session.switchProfile(to: partner, pin: "1234")

        #expect(await session.currentProfile()?.id == partner)
    }

    @Test func aLockoutDoesNotBlockUnprotectedProfiles() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        let until = fixedNow.addingTimeInterval(600)
        rig.defaults.set(
            try JSONEncoder().encode(PINLockout(failedAttempts: 0, lockoutCount: 2, lockedUntil: until)),
            forKey: PlexSession.DefaultsKey.profilePINLockout)
        await rig.transport.scriptSwitch(userID: "1003", switchOK)
        await rig.transport.scriptSwitch(userID: "1002", switchOK)

        await #expect(throws: PlexError.lockedOut(until: until)) {
            try await session.switchProfile(to: partner, pin: "1234")
        }
        try await session.switchProfile(to: kid, pin: nil)

        #expect(await session.currentProfile()?.id == kid)
    }

    @Test func aLockoutThatStartsDuringThePlexTVCallStopsTheCommit() async throws {
        let rig = SessionRig()
        defer { rig.cleanup() }
        await rig.transport.scriptHealthyAccount()
        await rig.transport.scriptSwitch(userID: "1002", switchOK)
        let until = fixedNow.addingTimeInterval(600)
        nonisolated(unsafe) let defaults = rig.defaults
        let hooked = HookTransport(base: rig.transport) { request in
            guard request.url?.path == "/api/home/users/1002/switch" else { return }
            defaults.set(
                try? JSONEncoder().encode(PINLockout(failedAttempts: 0, lockoutCount: 2, lockedUntil: until)),
                forKey: PlexSession.DefaultsKey.profilePINLockout)
        }
        let session = rig.makeSession(transport: hooked)
        try await session.signIn(accountToken: "TOKEN-OWNER")

        await #expect(throws: PlexError.lockedOut(until: until)) {
            try await session.switchProfile(to: partner, pin: "1234")
        }

        #expect(await session.currentProfile()?.id == owner)
        #expect(try rig.secrets.string(for: .plexUserToken(partner)) == nil)
        #expect(rig.defaults.string(forKey: PlexSession.DefaultsKey.lastProfileID) == "1001")
    }

    @Test func aSecondConcurrentSwitchIsRefused() async throws {
        let rig = SessionRig()
        defer { rig.cleanup() }
        await rig.transport.scriptHealthyAccount()
        await rig.transport.scriptSwitch(userID: "1002", switchOK)
        let hooked = HookTransport(base: rig.transport, delayPath: "/api/home/users/1002/switch")
        let session = rig.makeSession(transport: hooked)
        try await session.signIn(accountToken: "TOKEN-OWNER")

        async let first: Void = session.switchProfile(to: partner, pin: "1234")
        try await Task.sleep(for: .milliseconds(100))
        await #expect(throws: PlexError.switchInProgress) {
            try await session.switchProfile(to: kid, pin: nil)
        }
        try await first

        #expect(await session.currentProfile()?.id == partner)
    }
}

@Suite("Resume refreshes restriction", .timeLimit(.minutes(1)))
struct PlexResumeRestrictionTests {
    @Test func aTightenedRestrictionReachesTheResumedProfile() async throws {
        let rig = SessionRig()
        defer { rig.cleanup() }
        await rig.transport.scriptHealthyAccount()
        await rig.transport.scriptSwitch(userID: "1003", switchOK)
        let first = rig.makeSession()
        try await first.signIn(accountToken: "TOKEN-OWNER")
        try await first.switchProfile(to: kid, pin: nil)
        // Stored restriction is older than what Plex says now (little_kid).
        try await rig.settings.update { $0.profiles[kid]?.plexRestriction = .olderKid }

        let relaunch = FakeTransport()
        await relaunch.script(path: "/identity", fixture: "identity")
        await relaunch.script(path: "/api/v2/user", fixture: "user")
        await relaunch.script(path: "/api/v2/home/users", fixture: "home_users")
        await relaunch.script(path: "/api/v2/resources", fixture: "resources_single")
        let session = rig.makeSession(transport: relaunch)
        #expect(await session.resume() == true)
        #expect(await session.currentProfile()?.restriction == .olderKid)

        await session.refreshFromPlexTV()

        #expect(await session.currentProfile()?.restriction == .littleKid)
        if case .ready(let profile, _) = await session.snapshot().state {
            #expect(profile.restriction == .littleKid)
        } else {
            Issue.record("expected ready")
        }
    }
}

@Suite("Decoding and descriptions")
struct PlexFailClosedTests {
    @Test func aNamedRestrictionProfileMeansRestrictedEvenWithoutTheFlag() throws {
        let json = Data(#"{"id": 9, "title": "X", "restrictionProfile": "little_kid"}"#.utf8)
        let user = try PlexJSON.decode(PlexHomeUser.self, from: json)
        #expect(user.restricted == false)
        #expect(user.restriction == .littleKid)
    }

    @Test func aServerDescriptionNeverContainsItsToken() {
        let server = PlexServer(
            name: "Lounge", machineID: "M", owned: true, connections: [], accessToken: "FAKE-TOKEN-X")
        #expect(!String(describing: server).contains("FAKE-TOKEN-X"))
        #expect(!String(reflecting: server).contains("FAKE-TOKEN-X"))
        #expect(String(describing: server).contains("Lounge"))
    }
}

/// Forwards to a base transport, running a hook (or sleeping) first for chosen paths.
private struct HookTransport: PlexTransport {
    let base: FakeTransport
    var hook: (@Sendable (URLRequest) -> Void)?
    var delayPath: String?

    init(base: FakeTransport, hook: (@Sendable (URLRequest) -> Void)? = nil, delayPath: String? = nil) {
        self.base = base
        self.hook = hook
        self.delayPath = delayPath
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        hook?(request)
        if request.url?.path == delayPath { try await Task.sleep(for: .milliseconds(500)) }
        return try await base.send(request)
    }
}
