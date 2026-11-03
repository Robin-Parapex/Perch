import Foundation
import OSLog
import PerchCore
import PerchPlex

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
    let modules: ModuleRegistry
    let plexSignIn: PlexSignInModel
    let setupCompletion: SetupCompletion
    let profileSwitcher: ProfileSwitcher
    let launch = LaunchState()
    let eventBus = EventBus()
    let pollers = PollerCoordinator()

    init() {
        secrets = KeychainStore()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PerchResetSetup") { Self.debugReset(secrets: secrets) }
        if ProcessInfo.processInfo.arguments.contains("-PerchFakeSignedOut") { Self.debugSignOut(secrets: secrets) }
        #endif
        let keyValues = UserDefaultsStore()
        self.keyValues = keyValues
        settings = SettingsStore(store: keyValues)
        auditLog = AuditLog(store: keyValues)
        // Plex: transport, identity and the owner PIN verifier are built before AdminPIN (WP-04 decision 10).
        let baseTransport: any PlexTransport = URLSessionTransport()
        #if DEBUG
        // `-PerchFakeHousehold` serves canned answers; the fault switches wrap whichever transport is in use.
        let transport = FaultInjectingTransport.wrapping(FakeHouseholdTransport.fromArguments() ?? baseTransport)
        #else
        let transport = baseTransport
        #endif
        let endpoints = PlexEndpoints(identity: PlexClientIdentity(defaults: Self.plexDefaults()))
        let verifier = PlexOwnerPINVerifier(
            transport: transport, endpoints: endpoints, secrets: secrets, settings: settings)
        let adminPIN = AdminPIN(
            secrets: secrets, keyValues: keyValues, plexVerifier: verifier, ownerHasPlexPIN: nil)
        self.adminPIN = adminPIN
        let session = PlexSession(
            transport: transport, identity: endpoints.identity, secrets: secrets, defaults: Self.plexDefaults(),
            settings: settings, adminPIN: adminPIN)
        plexSignIn = PlexSignInModel(
            session: session, transport: transport, endpoints: endpoints, adminPIN: adminPIN, settings: settings)
        setupCompletion = SetupCompletion(store: keyValues)
        profileSwitcher = ProfileSwitcher(
            session: session, settings: settings, adminPIN: adminPIN, defaults: Self.plexDefaults())
        let modules = ModuleRegistry(modules: [PlexModule(session: session)])
        self.modules = modules
        authoriser = Authoriser(
            auditLog: auditLog, adminPIN: adminPIN,
            modulePolicies: { action in await modules.policy(for: action) })
    }

    /// A fresh handle on the App Group defaults (UserDefaults is not Sendable, so each owner gets its own).
    nonisolated static func plexDefaults() -> UserDefaults {
        UserDefaults(suiteName: PerchConstants.appGroupID) ?? .standard
    }

    #if DEBUG
    /// `-PerchResetSetup`: back to a first run for tests and screenshots. Clears the setup flag, the last
    /// profile, the Plex and Admin PIN records, the settings document, the image cache and the Keychain
    /// items of the fake household (and the signed-in owner). Runs before any service reads its state.
    private static func debugReset(secrets: any SecretStore) {
        let defaults = plexDefaults()
        for key in defaults.dictionaryRepresentation().keys
        where ["plex.", "admin.", "perch."].contains(where: key.hasPrefix) {
            defaults.removeObject(forKey: key)
        }
        try? secrets.remove(.plexOwnerToken)
        try? secrets.remove(.adminPerchPIN)
        for id in ["1001", "1002", "1003", "manual"] {
            try? secrets.remove(.plexUserToken(PlexUserID(id)))
            try? secrets.remove(.module(ModuleID("plex"), "server.\(id)"))
        }
        ImageDiskCache.shared.removeAll()
    }

    /// `-PerchFakeSignedOut`: forgets only the stored Plex sign-in (the owner and profile tokens, the server
    /// tokens and the last profile). The PINs, the setup flag and the other settings stay.
    private static func debugSignOut(secrets: any SecretStore) {
        plexDefaults().removeObject(forKey: PlexSession.DefaultsKey.lastProfileID)
        plexDefaults().removeObject(forKey: PlexSession.DefaultsKey.singleProfile)
        try? secrets.remove(.plexOwnerToken)
        for id in ["1001", "1002", "1003", "manual"] {
            try? secrets.remove(.plexUserToken(PlexUserID(id)))
            try? secrets.remove(.module(ModuleID("plex"), "server.\(id)"))
        }
    }

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
