import Foundation
import Synchronization
import Testing

@testable import PerchCore

private final class TestClock: Sendable {
    private let value: Mutex<Date>
    init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) { value = Mutex(start) }
    var now: Date { value.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { value.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

private struct FakeVerifier: PlexPINVerifying {
    let correct: String
    let reachable: Bool
    func verifyOwnerPIN(_ pin: String) async throws -> Bool {
        guard reachable else { throw PlexPINError.unreachable }
        return pin == correct
    }
}

private struct ThrowingSecretStore: SecretStore {
    struct Boom: Error {}
    func data(for key: SecretKey) throws -> Data? { throw Boom() }
    func set(_ data: Data, for key: SecretKey) throws { throw Boom() }
    func remove(_ key: SecretKey) throws { throw Boom() }
}

private func makePIN(
    secrets: InMemorySecretStore = InMemorySecretStore(),
    keyValues: InMemoryKeyValueStore = InMemoryKeyValueStore(),
    verifier: (any PlexPINVerifying)? = nil,
    ownerHasPlexPIN: Bool? = false,
    clock: TestClock = TestClock()
) -> AdminPIN {
    AdminPIN(
        secrets: secrets, keyValues: keyValues, plexVerifier: verifier,
        ownerHasPlexPIN: ownerHasPlexPIN, hasher: PINHasher(iterations: 1_000),
        now: { clock.now })
}

@Suite("Security")
struct SecurityTests {
    @Test func secretKeyRawValues() {
        #expect(SecretKey.plexOwnerToken.rawValue == "plex.owner.token")
        #expect(SecretKey.adminPerchPIN.rawValue == "admin.perchPIN")
        #expect(SecretKey.plexUserToken("42").rawValue == "plex.user.42.token")
        #expect(SecretKey.module("seerr", "apiKey").rawValue == "module.seerr.apiKey")
    }

    @Test func secretMask() {
        #expect(SecretMask.display("abc") == "••••")
        #expect(SecretMask.display("12345678") == "••••")
        #expect(SecretMask.display("sk-proj-abcdefa1b2") == "sk-…a1b2")
        #expect(SecretMask.display("abcdefghijkl9z8y") == "…9z8y")
    }

    @Test func inMemorySecretStore() throws {
        let store = InMemorySecretStore()
        let key = SecretKey.plexOwnerToken
        #expect(try store.string(for: key) == nil)
        try store.setString("token", for: key)
        #expect(try store.string(for: key) == "token")
        try store.remove(key)
        #expect(try store.data(for: key) == nil)
    }

    // Disabled: observed KeychainError(status: -34018) (errSecMissingEntitlement) when run
    // unsigned (CODE_SIGNING_ALLOWED=NO) on the tvOS simulator. Enable from a signed host.
    @Test(.disabled("Keychain returns -34018 (errSecMissingEntitlement) in the unsigned test bundle"))
    func keychainStore() throws {
        let store = KeychainStore(
            service: "com.robrolabs.perch.tests.\(UUID().uuidString)", accessGroup: nil)
        defer { try? store.removeAll() }
        let key = SecretKey.module("seerr", "apiKey")
        #expect(try store.data(for: key) == nil)
        try store.setString("one", for: key)
        #expect(try store.string(for: key) == "one")
        try store.setString("two", for: key)
        #expect(try store.string(for: key) == "two")
        try store.remove(key)
        #expect(try store.data(for: key) == nil)
        try store.setString("x", for: key)
        try store.removeAll()
        #expect(try store.data(for: key) == nil)
    }

    @Test func pinHasher() throws {
        let hasher = PINHasher(iterations: 1_000)
        let a = try hasher.hash("1234")
        let b = try hasher.hash("1234")
        #expect(a.salt != b.salt)
        #expect(a.salt.count == 16 && a.hash.count == 32 && a.iterations == 1_000)
        #expect(hasher.verify("1234", against: a))
        #expect(!hasher.verify("1235", against: a))
    }

    @Test func pinPolicy() throws {
        try PINPolicy.validatePerchPIN("1234")
        try PINPolicy.validatePerchPIN("12345678")
        for bad in ["", "123", "123456789", "12ab", "١٢٣٤"] {
            #expect(throws: AdminPINError.invalidPIN) { try PINPolicy.validatePerchPIN(bad) }
        }
    }

    @Test func sourceResolution() async throws {
        let none = makePIN()
        #expect(await none.source == .setupRequired)
        #expect(await none.verify("1234") == .setupRequired)

        let owner = makePIN(verifier: FakeVerifier(correct: "9999", reachable: true), ownerHasPlexPIN: true)
        #expect(await owner.source == .plexOwner)
        await #expect(throws: AdminPINError.notAuthorised) { try await owner.setPerchPIN("4321") }
        #expect(await owner.verify("9999") == .accepted)
        try await owner.setPerchPIN("4321")
        #expect(await owner.source == .perch)
        #expect(await owner.verify("4321") == .accepted)
        await owner.expireFreshness()
        await #expect(throws: AdminPINError.notAuthorised) { try await owner.removePerchPIN() }
        #expect(await owner.verify("4321") == .accepted)
        try await owner.removePerchPIN()
        #expect(await owner.source == .plexOwner)
    }

    @Test func invalidAndRefusedChanges() async throws {
        let pin = makePIN()
        await #expect(throws: AdminPINError.invalidPIN) { try await pin.setPerchPIN("12") }
        try await pin.setPerchPIN("1234")
        #expect(await pin.source == .perch)
        // A PIN now exists and nothing is fresh: changes are refused.
        await #expect(throws: AdminPINError.notAuthorised) { try await pin.setPerchPIN("5678") }
        #expect(await pin.verify("1234") == .accepted)
        try await pin.setPerchPIN("5678")
        await #expect(throws: AdminPINError.wouldLeaveNoPIN) { try await pin.removePerchPIN() }
        #expect(await pin.source == .perch)
    }

    @Test func unreadableStoreFailsClosed() async {
        let pin = AdminPIN(
            secrets: ThrowingSecretStore(), keyValues: InMemoryKeyValueStore(), plexVerifier: nil,
            ownerHasPlexPIN: false, hasher: PINHasher(iterations: 1_000))
        #expect(await pin.source == .unavailable)
        #expect(await pin.verify("1234") == .unavailable)
        #expect(await pin.lockoutState() == PINLockout())
        await #expect(throws: AdminPINError.notAuthorised) { try await pin.setPerchPIN("1234") }
    }

    @Test func garbageStoredPINIsUnavailableNotAbsent() async throws {
        let secrets = InMemorySecretStore()
        try secrets.set(Data("garbage".utf8), for: .adminPerchPIN)
        let pin = makePIN(secrets: secrets, ownerHasPlexPIN: false)
        #expect(await pin.source == .unavailable)
        #expect(await pin.verify("1234") == .unavailable)
        #expect(await pin.lockoutState().failedAttempts == 0)
    }

    @Test func unknownOwnerPINIsUnreachableAndNotCounted() async {
        let pin = makePIN(verifier: FakeVerifier(correct: "9999", reachable: true), ownerHasPlexPIN: nil)
        #expect(await pin.source == .unavailable)
        #expect(await pin.verify("9999") == .plexUnreachable)
        #expect(await pin.lockoutState().failedAttempts == 0)
    }

    @Test func ownerHasPlexPINIsRemembered() async {
        let keyValues = InMemoryKeyValueStore()
        let first = makePIN(keyValues: keyValues, ownerHasPlexPIN: true)
        #expect(await first.source == .plexOwner)
        let second = makePIN(keyValues: keyValues, ownerHasPlexPIN: nil)
        #expect(await second.source == .plexOwner)
        await second.setOwnerHasPlexPIN(false)
        let third = makePIN(keyValues: keyValues, ownerHasPlexPIN: nil)
        #expect(await third.source == .setupRequired)
    }

    @Test func corruptLockoutBlobStartsLockedFor60s() async {
        let keyValues = InMemoryKeyValueStore()
        keyValues.set(Data("garbage".utf8), forKey: "admin.pinLockout")
        let clock = TestClock()
        let pin = makePIN(keyValues: keyValues, clock: clock)
        let state = await pin.lockoutState()
        #expect(state.lockoutCount == 1 && state.lockedUntil == clock.now.addingTimeInterval(60))
        #expect(await pin.verify("1234") == .lockedOut(until: clock.now.addingTimeInterval(60)))
        // Persisted, so a relaunch is still locked.
        let again = makePIN(keyValues: keyValues, clock: clock)
        #expect(await again.lockoutState().lockedUntil == clock.now.addingTimeInterval(60))
    }

    @Test func plexPath() async {
        let ok = makePIN(verifier: FakeVerifier(correct: "9999", reachable: true), ownerHasPlexPIN: true)
        #expect(await ok.verify("0000") == .rejected(attemptsLeft: 4))
        #expect(await ok.verify("") == .rejected(attemptsLeft: 4))
        #expect(await ok.verify("9999") == .accepted)
        #expect(await ok.lockoutState() == PINLockout())

        let down = makePIN(verifier: FakeVerifier(correct: "9999", reachable: false), ownerHasPlexPIN: true)
        #expect(await down.verify("9999") == .plexUnreachable)
        #expect(await down.lockoutState().failedAttempts == 0)

        let none = makePIN(verifier: nil, ownerHasPlexPIN: true)
        #expect(await none.verify("9999") == .plexUnreachable)
        #expect(await none.lockoutState().failedAttempts == 0)
    }

    @Test func freshnessExpires() async throws {
        let clock = TestClock()
        let pin = makePIN(clock: clock)
        try await pin.setPerchPIN("1234")
        #expect(await pin.isFresh() == false)
        #expect(await pin.verify("1234") == .accepted)
        #expect(await pin.isFresh())
        clock.advance(299)
        #expect(await pin.isFresh())
        clock.advance(2)
        #expect(await pin.isFresh() == false)
        #expect(await pin.verify("1234") == .accepted)
        await pin.expireFreshness()
        #expect(await pin.isFresh() == false)
    }

    @Test func lockoutSurvivesRelaunch() async throws {
        let secrets = InMemorySecretStore()
        let keyValues = InMemoryKeyValueStore()
        let clock = TestClock()
        let first = makePIN(secrets: secrets, keyValues: keyValues, clock: clock)
        try await first.setPerchPIN("1234")
        for _ in 0..<4 { _ = await first.verify("0000") }
        guard case .lockedOut = await first.verify("0000") else {
            Issue.record("expected lockout on fifth failure")
            return
        }
        let second = makePIN(secrets: secrets, keyValues: keyValues, clock: clock)
        guard case .lockedOut = await second.verify("1234") else {
            Issue.record("lockout not reloaded")
            return
        }
        #expect(await second.lockoutState() == first.lockoutState())
    }
}
