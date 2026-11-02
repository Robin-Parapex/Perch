import CommonCrypto
import Foundation
import OSLog
import Security
import Synchronization

public struct HashedPIN: Codable, Sendable, Equatable {
    public var salt: Data
    public var iterations: Int
    public var hash: Data

    public init(salt: Data, iterations: Int, hash: Data) {
        self.salt = salt
        self.iterations = iterations
        self.hash = hash
    }
}

public struct PINHasher: Sendable {
    public var iterations: Int

    public init(iterations: Int = 600_000) { self.iterations = iterations }

    public func hash(_ pin: String) throws -> HashedPIN {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        let derived = try Self.derive(pin, salt: salt, iterations: iterations)
        return HashedPIN(salt: salt, iterations: iterations, hash: derived)
    }

    public func verify(_ pin: String, against stored: HashedPIN) -> Bool {
        guard stored.iterations > 0,
            let derived = try? Self.derive(pin, salt: stored.salt, iterations: stored.iterations)
        else { return false }
        return Self.constantTimeEqual(derived, stored.hash)
    }

    private static func derive(_ pin: String, salt: Data, iterations: Int) throws -> Data {
        var out = Data(count: 32)
        let pinBytes = Array(pin.utf8)
        let status = out.withUnsafeMutableBytes { outPtr in
            salt.withUnsafeBytes { saltPtr in
                pinBytes.withUnsafeBufferPointer { pinPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pinPtr.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                        pinBytes.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        outPtr.bindMemory(to: UInt8.self).baseAddress, 32)
                }
            }
        }
        guard status == kCCSuccess else { throw KeychainError(status: OSStatus(status)) }
        return out
    }

    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }
}

public enum AdminPINError: Error, Equatable {
    case invalidPIN
    case wouldLeaveNoPIN
    case notAuthorised
}

public enum PINPolicy {
    /// 4 to 8 ASCII digits. The Admin PIN can never be empty.
    public static func validatePerchPIN(_ pin: String) throws {
        let bytes = Array(pin.utf8)
        guard (4...8).contains(bytes.count), bytes.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else {
            throw AdminPINError.invalidPIN
        }
    }
}

public protocol KeyValueStore: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

public final class UserDefaultsStore: KeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults

    /// False if the App Group suite could not be opened and `.standard` is in use.
    public let isAppGroupSuite: Bool

    public init(suiteName: String = PerchConstants.appGroupID) {
        if let suite = UserDefaults(suiteName: suiteName) {
            defaults = suite
            isAppGroupSuite = true
        } else {
            Logger(subsystem: "com.robrolabs.perch", category: "storage")
                .error("App Group defaults suite unavailable; falling back to standard defaults")
            defaults = .standard
            isAppGroupSuite = false
        }
    }

    public func data(forKey key: String) -> Data? { defaults.data(forKey: key) }

    public func set(_ data: Data?, forKey key: String) {
        if let data { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

public final class InMemoryKeyValueStore: KeyValueStore {
    private let storage = Mutex<[String: Data]>([:])

    public init() {}

    public func data(forKey key: String) -> Data? { storage.withLock { $0[key] } }
    public func set(_ data: Data?, forKey key: String) { storage.withLock { $0[key] = data } }
}
