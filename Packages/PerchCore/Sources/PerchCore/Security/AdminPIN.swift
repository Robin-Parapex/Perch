import Foundation

public struct PINLockout: Codable, Sendable, Equatable {
    public static let maxAttempts = 5
    public static let baseLockout: TimeInterval = 60
    public static let maxLockout: TimeInterval = 3600

    public var failedAttempts: Int
    public var lockoutCount: Int
    public var lockedUntil: Date?

    public init(failedAttempts: Int = 0, lockoutCount: Int = 0, lockedUntil: Date? = nil) {
        self.failedAttempts = failedAttempts
        self.lockoutCount = lockoutCount
        self.lockedUntil = lockedUntil
    }

    public func isLocked(at now: Date) -> Bool {
        guard let lockedUntil else { return false }
        return now < lockedUntil
    }

    public func remaining(at now: Date) -> TimeInterval {
        guard let lockedUntil, now < lockedUntil else { return 0 }
        return lockedUntil.timeIntervalSince(now)
    }

    public var attemptsLeft: Int { Self.maxAttempts - failedAttempts }

    public mutating func recordFailure(at now: Date) {
        guard !isLocked(at: now) else { return }
        failedAttempts += 1
        if failedAttempts >= Self.maxAttempts {
            lockoutCount += 1
            let exponent = min(lockoutCount - 1, 20)
            let seconds = min(Self.baseLockout * pow(2, Double(exponent)), Self.maxLockout)
            lockedUntil = now.addingTimeInterval(seconds)
            failedAttempts = 0
        }
    }

    public mutating func recordSuccess() {
        failedAttempts = 0
        lockoutCount = 0
        lockedUntil = nil
    }
}

public enum PlexPINError: Error { case unreachable }

public protocol PlexPINVerifying: Sendable {
    func verifyOwnerPIN(_ pin: String) async throws -> Bool
}

public enum AdminPINSource: Sendable, Equatable { case perch, plexOwner, setupRequired, unavailable }

public enum PINResult: Sendable, Equatable {
    case accepted
    case rejected(attemptsLeft: Int)
    case lockedOut(until: Date)
    case setupRequired
    case plexUnreachable
    /// The stored Perch PIN could not be read. Fails closed; never treated as "no PIN".
    case unavailable
}

public actor AdminPIN {
    private static let lockoutKey = "admin.pinLockout"
    private static let ownerPINKey = "admin.ownerHasPlexPIN"

    private enum StoredPIN {
        case absent
        case present(HashedPIN)
        case unreadable
    }

    private let secrets: any SecretStore
    private let keyValues: any KeyValueStore
    private let plexVerifier: (any PlexPINVerifying)?
    /// Nil means unknown (Plex not reached yet and nothing remembered).
    private var ownerHasPlexPIN: Bool?
    private let hasher: PINHasher
    private let freshness: TimeInterval
    private let now: NowProvider
    private var lockout: PINLockout
    private var lastVerified: Date?

    public init(
        secrets: any SecretStore,
        keyValues: any KeyValueStore,
        plexVerifier: (any PlexPINVerifying)?,
        ownerHasPlexPIN: Bool?,
        hasher: PINHasher = PINHasher(),
        freshness: TimeInterval = 300,
        now: @escaping NowProvider = { Date() }
    ) {
        self.secrets = secrets
        self.keyValues = keyValues
        self.plexVerifier = plexVerifier
        if let ownerHasPlexPIN {
            self.ownerHasPlexPIN = ownerHasPlexPIN
            keyValues.set(Data([ownerHasPlexPIN ? 1 : 0]), forKey: Self.ownerPINKey)
        } else {
            self.ownerHasPlexPIN = keyValues.data(forKey: Self.ownerPINKey).flatMap { $0.first.map { $0 == 1 } }
        }
        self.hasher = hasher
        self.freshness = freshness
        self.now = now
        if let blob = keyValues.data(forKey: Self.lockoutKey) {
            if let decoded = try? JSONDecoder().decode(PINLockout.self, from: blob) {
                self.lockout = decoded
            } else {
                // A corrupt lockout record must not unlock: start locked for the base period.
                let locked = PINLockout(
                    failedAttempts: 0, lockoutCount: 1,
                    lockedUntil: now().addingTimeInterval(PINLockout.baseLockout))
                self.lockout = locked
                keyValues.set(try? JSONEncoder().encode(locked), forKey: Self.lockoutKey)
            }
        } else {
            self.lockout = PINLockout()
        }
    }

    private func storedPerchPIN() -> StoredPIN {
        do {
            guard let data = try secrets.data(for: .adminPerchPIN) else { return .absent }
            return .present(try JSONDecoder().decode(HashedPIN.self, from: data))
        } catch {
            return .unreadable
        }
    }

    public var source: AdminPINSource {
        switch storedPerchPIN() {
        case .present: return .perch
        case .unreadable: return .unavailable
        case .absent:
            switch ownerHasPlexPIN {
            case true?: return .plexOwner
            case false?: return .setupRequired
            case nil: return .unavailable
            }
        }
    }

    public func setOwnerHasPlexPIN(_ value: Bool?) {
        ownerHasPlexPIN = value
        if let value { keyValues.set(Data([value ? 1 : 0]), forKey: Self.ownerPINKey) }
    }

    public func verify(_ pin: String) async -> PINResult {
        let start = now()
        if lockout.isLocked(at: start), let until = lockout.lockedUntil { return .lockedOut(until: until) }

        let matched: Bool
        switch storedPerchPIN() {
        case .unreadable:
            return .unavailable
        case .present(let stored):
            if pin.isEmpty { return .rejected(attemptsLeft: lockout.attemptsLeft) }
            matched = hasher.verify(pin, against: stored)
        case .absent:
            switch ownerHasPlexPIN {
            case nil:
                return .plexUnreachable
            case false?:
                return .setupRequired
            case true?:
                if pin.isEmpty { return .rejected(attemptsLeft: lockout.attemptsLeft) }
                guard let plexVerifier else { return .plexUnreachable }
                do { matched = try await plexVerifier.verifyOwnerPIN(pin) } catch { return .plexUnreachable }
            }
        }

        // The actor may have been re-entered during the await; a lockout set meanwhile wins.
        let moment = now()
        if lockout.isLocked(at: moment), let until = lockout.lockedUntil { return .lockedOut(until: until) }
        if matched {
            lockout.recordSuccess()
            persist()
            lastVerified = moment
            return .accepted
        }
        lockout.recordFailure(at: moment)
        persist()
        if lockout.isLocked(at: moment), let until = lockout.lockedUntil { return .lockedOut(until: until) }
        return .rejected(attemptsLeft: lockout.attemptsLeft)
    }

    /// First-time setup (wizard) or a parent who just entered the Admin PIN.
    private func requireAuthorisation() throws {
        guard source == .setupRequired || isFresh() else { throw AdminPINError.notAuthorised }
    }

    public func setPerchPIN(_ pin: String) throws {
        try requireAuthorisation()
        try PINPolicy.validatePerchPIN(pin)
        let hashed = try hasher.hash(pin)
        try secrets.set(try JSONEncoder().encode(hashed), for: .adminPerchPIN)
    }

    public func removePerchPIN() throws {
        try requireAuthorisation()
        guard ownerHasPlexPIN == true else { throw AdminPINError.wouldLeaveNoPIN }
        try secrets.remove(.adminPerchPIN)
    }

    public func isFresh() -> Bool {
        guard let lastVerified else { return false }
        let elapsed = now().timeIntervalSince(lastVerified)
        return elapsed >= 0 && elapsed <= freshness
    }

    public func expireFreshness() { lastVerified = nil }

    public func lockoutState() -> PINLockout { lockout }

    private func persist() {
        keyValues.set(try? JSONEncoder().encode(lockout), forKey: Self.lockoutKey)
    }
}
