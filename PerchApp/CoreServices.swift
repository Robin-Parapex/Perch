import Foundation
import OSLog
import PerchCore

/// The PerchCore services the app shell owns, built once at launch.
/// Modules and screens receive these; nothing else constructs its own store.
@MainActor
final class CoreServices {
    let secrets: any SecretStore
    let keyValues: any KeyValueStore
    let settings: SettingsStore
    let auditLog: AuditLog
    let authoriser: Authoriser
    let adminPIN: AdminPIN
    let modules = ModuleRegistry(modules: [])  // modules arrive in later WPs
    let eventBus = EventBus()
    let pollers = PollerCoordinator()

    init() {
        secrets = KeychainStore()
        let keyValues = UserDefaultsStore()
        self.keyValues = keyValues
        settings = SettingsStore(store: keyValues)
        auditLog = AuditLog(store: keyValues)
        // The owner's Plex PIN state and verifier arrive with Plex sign-in (WP-04); until then unknown.
        let adminPIN = AdminPIN(
            secrets: secrets, keyValues: keyValues, plexVerifier: nil, ownerHasPlexPIN: nil)
        self.adminPIN = adminPIN
        let modules = self.modules
        authoriser = Authoriser(
            auditLog: auditLog, adminPIN: adminPIN,
            modulePolicies: { action in await modules.policy(for: action) })
    }

    #if DEBUG
    /// Proves on hardware that the Keychain and the App Group defaults are reachable.
    /// Writes, reads back and deletes probe items; never touches real keys.
    func runStorageSelfCheck() {
        runKeychainProbe()
        runDefaultsProbe()
    }

    private func runDefaultsProbe() {
        let key = "debug.selfcheck"
        let value = Data(UUID().uuidString.utf8)
        keyValues.set(value, forKey: key)
        let readBack = keyValues.data(forKey: key)
        keyValues.set(nil, forKey: key)
        let gone = keyValues.data(forKey: key) == nil
        if readBack == value && gone {
            let appGroup = (keyValues as? UserDefaultsStore)?.isAppGroupSuite ?? false
            Logger.core.notice(
                "Defaults self-check OK (\(PerchConstants.appGroupID, privacy: .public), appGroup=\(appGroup, privacy: .public))"
            )
        } else {
            Logger.core.error("Defaults self-check FAILED: value mismatch or not removed")
        }
    }

    private func runKeychainProbe() {
        let probe = SecretKey(rawValue: "debug.selfcheck")
        let value = UUID().uuidString
        do {
            try secrets.setString(value, for: probe)
            let readBack = try secrets.string(for: probe)
            try secrets.remove(probe)
            let gone = try secrets.data(for: probe) == nil
            if readBack == value && gone {
                Logger.core.notice(
                    "Keychain self-check OK (\(PerchConstants.keychainAccessGroup, privacy: .public))")
            } else {
                Logger.core.error("Keychain self-check FAILED: value mismatch or not removed")
            }
        } catch {
            Logger.core.error("Keychain self-check FAILED: \(String(describing: error), privacy: .public)")
        }
    }
    #endif
}

extension Logger {
    static let core = Logger(subsystem: "com.robrolabs.perch", category: "core")
}
