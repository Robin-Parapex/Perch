import Foundation
import Security
import Synchronization

/// Names a secret held in the Keychain. Values are never logged.
public struct SecretKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let plexOwnerToken = SecretKey(rawValue: "plex.owner.token")
    public static let adminPerchPIN = SecretKey(rawValue: "admin.perchPIN")

    public static func plexUserToken(_ id: PlexUserID) -> SecretKey {
        SecretKey(rawValue: "plex.user.\(id.rawValue).token")
    }

    public static func module(_ id: ModuleID, _ name: String) -> SecretKey {
        SecretKey(rawValue: "module.\(id.rawValue).\(name)")
    }
}

public protocol SecretStore: Sendable {
    func data(for key: SecretKey) throws -> Data?
    func set(_ data: Data, for key: SecretKey) throws
    func remove(_ key: SecretKey) throws
}

extension SecretStore {
    public func string(for key: SecretKey) throws -> String? {
        try data(for: key).flatMap { String(data: $0, encoding: .utf8) }
    }

    public func setString(_ value: String, for key: SecretKey) throws {
        try set(Data(value.utf8), for: key)
    }
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
    public init(status: OSStatus) { self.status = status }
}

/// Generic-password Keychain items, readable after first unlock, never synced off this device.
public struct KeychainStore: SecretStore {
    public let service: String
    public let accessGroup: String?

    public init(
        service: String = PerchConstants.keychainService,
        accessGroup: String? = PerchConstants.keychainAccessGroup
    ) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private func baseQuery(_ key: SecretKey? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let key { query[kSecAttrAccount as String] = key.rawValue }
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    public func data(for key: SecretKey) throws -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError(status: status)
        }
    }

    public func set(_ data: Data, for key: SecretKey) throws {
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = baseQuery(key)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        default:
            throw KeychainError(status: status)
        }
    }

    public func remove(_ key: SecretKey) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    /// Deletes every item of this service (tests and reset).
    public func removeAll() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

public final class InMemorySecretStore: SecretStore {
    private let storage = Mutex<[SecretKey: Data]>([:])

    public init() {}

    public func data(for key: SecretKey) throws -> Data? { storage.withLock { $0[key] } }
    public func set(_ data: Data, for key: SecretKey) throws { storage.withLock { $0[key] = data } }
    public func remove(_ key: SecretKey) throws { storage.withLock { $0[key] = nil } }
}

/// Shows enough of a secret to recognise it, e.g. `sk-…a1b2`.
public enum SecretMask {
    public static func display(_ secret: String) -> String {
        guard secret.count > 8 else { return "••••" }
        let tail = String(secret.suffix(4))
        let head = secret.prefix(5)
        if let dash = head.firstIndex(of: "-") {
            return String(secret[...dash]) + "…" + tail
        }
        return "…" + tail
    }
}
