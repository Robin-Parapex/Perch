import Foundation
import Synchronization
import Testing

@testable import PerchCore

/// Lockout rules from docs/DECISIONS.md 2026-11-02 "Admin PIN rules".
final class LockoutTestClock: Sendable {
    private let current: Mutex<Date>
    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = Mutex(start) }
    var now: Date { current.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }
    var provider: NowProvider { { [self] in self.now } }
}

struct LockoutThrowingVerifier: PlexPINVerifying {
    func verifyOwnerPIN(_ pin: String) async throws -> Bool { throw PlexPINError.unreachable }
}

struct LockoutFixedVerifier: PlexPINVerifying {
    let correct: String
    func verifyOwnerPIN(_ pin: String) async throws -> Bool { pin == correct }
}

actor LockoutGate {
    private var waiter: CheckedContinuation<Void, Never>?
    private var opened = false
    var isWaiting: Bool { waiter != nil }
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func open() {
        opened = true
        waiter?.resume()
        waiter = nil
    }
}

/// The right PIN suspends at the gate; any other PIN is wrong immediately.
struct LockoutGatedVerifier: PlexPINVerifying {
    let correct: String
    let gate: LockoutGate
    func verifyOwnerPIN(_ pin: String) async throws -> Bool {
        guard pin == correct else { return false }
        await gate.wait()
        return true
    }
}

struct PINLockoutTests {
    static let right = "1234"
    static let wrong = "9999"

    func makePIN(
        clock: LockoutTestClock, keyValues: InMemoryKeyValueStore = InMemoryKeyValueStore(),
        secrets: InMemorySecretStore = InMemorySecretStore(), setPIN: Bool = true,
        verifier: (any PlexPINVerifying)? = nil, ownerHasPlexPIN: Bool = false
    ) async throws -> AdminPIN {
        let pin = AdminPIN(
            secrets: secrets, keyValues: keyValues, plexVerifier: verifier,
            ownerHasPlexPIN: ownerHasPlexPIN, hasher: PINHasher(iterations: 1_000),
            now: clock.provider)
        if setPIN { try await pin.setPerchPIN(Self.right) }
        return pin
    }

    /// Five wrong attempts; returns the result of the fifth.
    func burn(_ pin: AdminPIN) async -> PINResult {
        var last = PINResult.accepted
        for _ in 0..<5 { last = await pin.verify(Self.wrong) }
        return last
    }

    // MARK: AdminPIN

    @Test func wrongAttemptsCountDownThenFifthLocksFor60s() async throws {
        let clock = LockoutTestClock()
        let pin = try await makePIN(clock: clock)
        #expect(await pin.verify(Self.wrong) == .rejected(attemptsLeft: 4))
        #expect(await pin.verify(Self.wrong) == .rejected(attemptsLeft: 3))
        #expect(await pin.verify(Self.wrong) == .rejected(attemptsLeft: 2))
        #expect(await pin.verify(Self.wrong) == .rejected(attemptsLeft: 1))
        #expect(await pin.verify(Self.wrong) == .lockedOut(until: clock.now.addingTimeInterval(60)))
    }

    @Test func fourWrongAttemptsDoNotLock() async throws {
        let clock = LockoutTestClock()
        let pin = try await makePIN(clock: clock)
        for _ in 0..<4 { _ = await pin.verify(Self.wrong) }
        #expect(await pin.verify(Self.right) == .accepted)
    }

    @Test func attemptsWhileLockedAreRejectedEvenWithRightPINAndNotCounted() async throws {
        let clock = LockoutTestClock()
        let pin = try await makePIN(clock: clock)
        let locked = await burn(pin)
        let until = clock.now.addingTimeInterval(60)
        #expect(locked == .lockedOut(until: until))
        clock.advance(30)
        #expect(await pin.verify(Self.right) == .lockedOut(until: until))
        #expect(await pin.verify(Self.wrong) == .lockedOut(until: until))
        #expect(await pin.lockoutState().failedAttempts == 0)
        #expect(await pin.lockoutState().lockoutCount == 1)
        // Still exactly 60 s from the original lock, not extended.
        clock.advance(30)
        #expect(await pin.verify(Self.right) == .accepted)
    }

    @Test func lockoutDoublesEachCycleAndCapsAtOneHour() async throws {
        let clock = LockoutTestClock()
        let pin = try await makePIN(clock: clock)
        let expected: [TimeInterval] = [60, 120, 240, 480, 960, 1920, 3600, 3600, 3600]
        for seconds in expected {
            let result = await burn(pin)
            #expect(result == .lockedOut(until: clock.now.addingTimeInterval(seconds)))
            clock.advance(seconds)
        }
    }

    @Test func correctPINAfterExpiryAcceptsAndResetsEscalation() async throws {
        let clock = LockoutTestClock()
        let pin = try await makePIN(clock: clock)
        _ = await burn(pin)
        clock.advance(60)
        _ = await burn(pin)  // 120 s lock
        clock.advance(120)
        #expect(await pin.verify(Self.right) == .accepted)
        #expect(await burn(pin) == .lockedOut(until: clock.now.addingTimeInterval(60)))
    }

    @Test func correctPINResetsFailedAttemptCount() async throws {
        let clock = LockoutTestClock()
        let pin = try await makePIN(clock: clock)
        for _ in 0..<3 { _ = await pin.verify(Self.wrong) }
        #expect(await pin.verify(Self.right) == .accepted)
        #expect(await pin.verify(Self.wrong) == .rejected(attemptsLeft: 4))
    }

    @Test func lockoutSurvivesNewInstanceOnSameKeyValueStore() async throws {
        let clock = LockoutTestClock()
        let kv = InMemoryKeyValueStore()
        let secrets = InMemorySecretStore()
        let first = try await makePIN(clock: clock, keyValues: kv, secrets: secrets)
        _ = await burn(first)
        let until = clock.now.addingTimeInterval(60)
        let relaunched = try await makePIN(clock: clock, keyValues: kv, secrets: secrets, setPIN: false)
        #expect(await relaunched.verify(Self.right) == .lockedOut(until: until))
        clock.advance(60)
        // Escalation also survived: next lockout is 120 s.
        #expect(await burn(relaunched) == .lockedOut(until: clock.now.addingTimeInterval(120)))
    }

    @Test func partialFailuresSurviveRelaunch() async throws {
        let clock = LockoutTestClock()
        let kv = InMemoryKeyValueStore()
        let secrets = InMemorySecretStore()
        let first = try await makePIN(clock: clock, keyValues: kv, secrets: secrets)
        for _ in 0..<3 { _ = await first.verify(Self.wrong) }
        let relaunched = try await makePIN(clock: clock, keyValues: kv, secrets: secrets, setPIN: false)
        #expect(await relaunched.verify(Self.wrong) == .rejected(attemptsLeft: 1))
    }

    @Test func plexUnreachableIsNotAFailedAttempt() async throws {
        let clock = LockoutTestClock()
        let pin = try await makePIN(
            clock: clock, setPIN: false, verifier: LockoutThrowingVerifier(), ownerHasPlexPIN: true)
        for _ in 0..<10 { #expect(await pin.verify(Self.wrong) == .plexUnreachable) }
        #expect(await pin.lockoutState().failedAttempts == 0)
        #expect(await pin.lockoutState().lockedUntil == nil)
    }

    @Test func plexPathCountsRealWrongAttempts() async throws {
        let clock = LockoutTestClock()
        let pin = try await makePIN(
            clock: clock, setPIN: false, verifier: LockoutFixedVerifier(correct: "4321"), ownerHasPlexPIN: true)
        #expect(await pin.verify("0000") == .rejected(attemptsLeft: 4))
        #expect(await pin.verify("4321") == .accepted)
    }

    @Test func lockoutDuringPendingPlexVerifyWins() async throws {
        let clock = LockoutTestClock()
        let gate = LockoutGate()
        let pin = try await makePIN(
            clock: clock, setPIN: false, verifier: LockoutGatedVerifier(correct: "4321", gate: gate),
            ownerHasPlexPIN: true)
        let pending = Task { await pin.verify("4321") }
        var spins = 0
        while !(await gate.isWaiting) && spins < 10_000 {
            await Task.yield()
            spins += 1
        }
        #expect(await gate.isWaiting)
        #expect(await burn(pin) == .lockedOut(until: clock.now.addingTimeInterval(60)))
        await gate.open()
        #expect(await pending.value == .lockedOut(until: clock.now.addingTimeInterval(60)))
        #expect(await pin.isFresh() == false)
        #expect(await pin.lockoutState().lockoutCount == 1)
    }

    @Test func setupRequiredWhenNoPerchPINAndOwnerHasNoPlexPIN() async throws {
        let clock = LockoutTestClock()
        let pin = try await makePIN(clock: clock, setPIN: false, ownerHasPlexPIN: false)
        #expect(await pin.source == .setupRequired)
        #expect(await pin.verify(Self.right) == .setupRequired)
    }

    @Test func freshnessLastsFiveMinutesAfterAcceptedPIN() async throws {
        let clock = LockoutTestClock()
        let pin = try await makePIN(clock: clock)
        #expect(await pin.isFresh() == false)
        #expect(await pin.verify(Self.right) == .accepted)
        clock.advance(299)
        #expect(await pin.isFresh())
        clock.advance(2)
        #expect(await pin.isFresh() == false)
    }

    @Test func wrongPINDoesNotMakeItFresh() async throws {
        let clock = LockoutTestClock()
        let pin = try await makePIN(clock: clock)
        _ = await pin.verify(Self.wrong)
        #expect(await pin.isFresh() == false)
    }

    // MARK: PINLockout value

    @Test func valueFourFailuresDoNotLock() {
        var state = PINLockout()
        let now = Date(timeIntervalSince1970: 0)
        for _ in 0..<4 { state.recordFailure(at: now) }
        #expect(!state.isLocked(at: now))
        #expect(state.attemptsLeft == 1)
    }

    @Test func valueSequence60Then120Then240() {
        var state = PINLockout()
        var now = Date(timeIntervalSince1970: 0)
        for seconds in [60.0, 120, 240] {
            for _ in 0..<5 { state.recordFailure(at: now) }
            #expect(state.isLocked(at: now))
            #expect(state.remaining(at: now) == seconds)
            now = now.addingTimeInterval(seconds)
            #expect(!state.isLocked(at: now))
        }
    }

    @Test func valueCapsAtOneHour() {
        var state = PINLockout()
        var now = Date(timeIntervalSince1970: 0)
        var lastRemaining: TimeInterval = 0
        for _ in 0..<12 {
            for _ in 0..<5 { state.recordFailure(at: now) }
            lastRemaining = state.remaining(at: now)
            now = now.addingTimeInterval(lastRemaining)
        }
        #expect(lastRemaining == 3600)
    }

    @Test func valueFailuresWhileLockedAreIgnored() {
        var state = PINLockout()
        let now = Date(timeIntervalSince1970: 0)
        for _ in 0..<5 { state.recordFailure(at: now) }
        let snapshot = state
        state.recordFailure(at: now.addingTimeInterval(10))
        #expect(state == snapshot)
    }

    @Test func valueSuccessResetsEverything() {
        var state = PINLockout()
        let now = Date(timeIntervalSince1970: 0)
        for _ in 0..<5 { state.recordFailure(at: now) }
        state.recordSuccess()
        #expect(state == PINLockout())
        for _ in 0..<5 { state.recordFailure(at: now) }
        #expect(state.remaining(at: now) == 60)
    }

    @Test func valueEncodesAndDecodesIntact() throws {
        var state = PINLockout()
        for _ in 0..<5 { state.recordFailure(at: Date(timeIntervalSince1970: 100)) }
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(PINLockout.self, from: data) == state)
    }
}
