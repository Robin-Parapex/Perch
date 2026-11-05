import Foundation
import OSLog
import PerchCore
import PerchPlex
import Synchronization

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
    let library: PlexLibrary
    let plexSignIn: PlexSignInModel
    let setupCompletion: SetupCompletion
    let profileSwitcher: ProfileSwitcher
    let playback: PlaybackCoordinator
    /// WP-08: the one image pipeline, the focus prefetcher and the page tint that follows focus.
    let artwork: ArtworkService
    let artworkPrefetcher: ArtworkPrefetcher
    let artworkTint: ArtworkTintModel
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
        // `-PerchLibraryDump` writes server library responses to Caches/library-dump (live checks).
        let transport = LibraryDumpTransport.wrapping(
            FaultInjectingTransport.wrapping(FakeHouseholdTransport.fromArguments() ?? baseTransport))
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
        let artwork = ArtworkService(session: session, transport: transport)
        self.artwork = artwork
        artworkPrefetcher = ArtworkPrefetcher(service: artwork)
        artworkTint = ArtworkTintModel(service: artwork)
        plexSignIn = PlexSignInModel(
            session: session, transport: transport, endpoints: endpoints, adminPIN: adminPIN, settings: settings)
        setupCompletion = SetupCompletion(store: keyValues)
        profileSwitcher = ProfileSwitcher(
            session: session, settings: settings, adminPIN: adminPIN, defaults: Self.plexDefaults())
        // The library needs the Authoriser and the Authoriser asks the modules, which hold the library:
        // the registry is filled in through a box once everything exists.
        let registryBox = RegistryBox()
        let authoriser = Authoriser(
            auditLog: auditLog, adminPIN: adminPIN,
            modulePolicies: { action in await registryBox.registry?.policy(for: action) })
        let library = PlexLibrary.make(
            session: session, transport: transport, identity: endpoints.identity, settings: settings,
            authoriser: authoriser, snapshotsDirectory: Self.homeSnapshotsDirectory())
        let modules = ModuleRegistry(modules: [PlexModule(session: session, library: library)])
        registryBox.set(modules)
        self.modules = modules
        self.library = library
        self.authoriser = authoriser
        playback = PlaybackCoordinator(
            library: library, plexSession: session, artwork: artwork, modules: modules,
            logFileURL: PlaybackCoordinator.logFileURL(), settings: settings)
        // Once at launch: sign-out deletes the Home snapshots, a profile change clears memory.
        Task { await library.observe(session) }
        // Sign-out clears the artwork caches (memory and disk).
        artwork.start()
    }

    private final class RegistryBox: Sendable {
        private let lock = Mutex<ModuleRegistry?>(nil)
        var registry: ModuleRegistry? { lock.withLock { $0 } }
        func set(_ registry: ModuleRegistry) { lock.withLock { $0 = registry } }
    }

    /// Home snapshots live in the App Group Caches (purgeable); the app's own Caches when the group
    /// container is not available.
    nonisolated static func homeSnapshotsDirectory() -> URL {
        let base =
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PerchConstants.appGroupID)?
            .appending(path: "Library/Caches", directoryHint: .isDirectory)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appending(path: "PlexHome", directoryHint: .isDirectory)
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
        ArtworkService.removeDiskCache()
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
