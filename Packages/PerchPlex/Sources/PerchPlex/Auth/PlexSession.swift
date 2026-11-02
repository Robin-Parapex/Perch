import Foundation
import OSLog
import PerchCore

public struct PlexActiveProfile: Sendable, Equatable {
    public let id: PlexUserID
    public let displayName: String
    public let isOwner: Bool
    public let restriction: PlexRestriction
}

public struct PlexConnectedServer: Sendable, Equatable {
    public let name: String
    public let machineID: String
    public let baseURL: URL
    public let tier: PlexConnectionTier
}

public enum PlexSessionState: Sendable, Equatable {
    case signedOut
    case connecting
    case ready(profile: PlexActiveProfile, server: PlexConnectedServer)
    case serverUnreachable
}

public struct PlexSessionSnapshot: Sendable, Equatable {
    public var state: PlexSessionState
    /// False when the last plex.tv call failed: PIN-protected profile switches cannot be checked.
    public var plexTVReachable: Bool
    /// False when running on a server-only token (manual route): one profile, no switching.
    public var profileSwitchingAvailable: Bool

    public init(state: PlexSessionState, plexTVReachable: Bool, profileSwitchingAvailable: Bool) {
        self.state = state
        self.plexTVReachable = plexTVReachable
        self.profileSwitchingAvailable = profileSwitchingAvailable
    }

    public static let signedOut = PlexSessionSnapshot(
        state: .signedOut, plexTVReachable: true, profileSwitchingAvailable: true)
}

/// The only holder of Plex tokens. Owner token, per-profile account tokens and per-profile server
/// access tokens live in the Keychain; non-secret choices live in the settings document and defaults.
public actor PlexSession {
    public enum DefaultsKey {
        public static let lastProfileID = "plex.lastProfileID"
        public static let profilePINLockout = "plex.profilePINLockout"
        public static let singleProfile = "plex.singleProfile"
    }

    enum ConfigKey {
        static let machineID = "machineID"
        static let serverName = "serverName"
        static let lastURI = "lastURI"
        static let manualURL = "manualURL"
    }

    /// The one profile of a manual (server-only token) sign-in.
    public static let singleProfileID = PlexUserID("manual")
    static let moduleID = ModuleID("plex")
    private static let log = Logger(subsystem: "com.robrolabs.perch", category: "plex")

    private struct SavedChoice {
        var machineID: String
        var name: String
        var lastURI: URL?
        var manualURL: URL?
    }

    private let transport: any PlexTransport
    private let endpoints: PlexEndpoints
    private let secrets: any SecretStore
    private let defaults: UserDefaults
    private let settings: SettingsStore
    private let adminPIN: AdminPIN?
    private let discovery: ServerDiscovery
    private let prober: ConnectionProber
    private let clock: NowProvider

    private var snapshotValue = PlexSessionSnapshot.signedOut
    private var continuations: [UUID: AsyncStream<PlexSessionSnapshot>.Continuation] = [:]
    private var account: PlexAccount?
    private var homeUsersCache: [PlexHomeUser] = []
    private var profile: PlexActiveProfile?
    private var knownServers: [PlexServer] = []

    public init(
        transport: any PlexTransport,
        identity: PlexClientIdentity,
        secrets: any SecretStore,
        defaults: UserDefaults,
        settings: SettingsStore,
        adminPIN: AdminPIN? = nil,
        proberTiming: ConnectionProber.Timing = .standard,
        now: @escaping NowProvider = { Date() }
    ) {
        let endpoints = PlexEndpoints(identity: identity)
        self.transport = transport
        self.endpoints = endpoints
        self.secrets = secrets
        self.defaults = defaults
        self.settings = settings
        self.adminPIN = adminPIN
        self.discovery = ServerDiscovery(transport: transport, endpoints: endpoints)
        self.prober = ConnectionProber(transport: transport, endpoints: endpoints, timing: proberTiming)
        self.clock = now
    }

    // MARK: State

    public func snapshot() -> PlexSessionSnapshot { snapshotValue }

    public func currentProfile() -> PlexActiveProfile? { profile }

    /// Yields the current snapshot at once, then every change, until the consumer stops.
    public func updates() -> AsyncStream<PlexSessionSnapshot> {
        let (stream, continuation) = AsyncStream<PlexSessionSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuations[id] = continuation
        continuation.yield(snapshotValue)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream
    }

    private func removeContinuation(_ id: UUID) { continuations[id] = nil }

    private func setState(_ state: PlexSessionState) {
        snapshotValue.state = state
        publish()
    }

    private func setPlexTVReachable(_ reachable: Bool) {
        guard snapshotValue.plexTVReachable != reachable else { return }
        snapshotValue.plexTVReachable = reachable
        publish()
    }

    private func setSwitchingAvailable(_ available: Bool) {
        guard snapshotValue.profileSwitchingAvailable != available else { return }
        snapshotValue.profileSwitchingAvailable = available
        publish()
    }

    private func publish() {
        for continuation in continuations.values { continuation.yield(snapshotValue) }
    }

    /// Runs a plex.tv call and records whether plex.tv answered (any answer counts as reachable).
    private func viaPlexTV<T>(_ body: () async throws -> T) async throws -> T {
        do {
            let value = try await body()
            setPlexTVReachable(true)
            return value
        } catch {
            if let plex = error as? PlexError {
                setPlexTVReachable(plex != .plexTVUnreachable)
            }
            throw error
        }
    }

    private func plexTV(_ request: URLRequest) async throws -> Data {
        try await viaPlexTV { try await transport.perform(request, host: .plexTV) }
    }

    // MARK: Sign in

    /// Validates the account token, stores it as the owner token, syncs Home users and finds servers.
    /// With exactly one server it is chosen at once and the state becomes `ready`; otherwise the
    /// caller shows the list and calls `choose(server:)`.
    @discardableResult
    public func signIn(accountToken: String) async throws -> [PlexServer] {
        setState(.connecting)
        do {
            let data = try await plexTV(endpoints.user(token: accountToken))
            let user = try PlexJSON.decode(PlexAccount.self, from: data)
            try secrets.setString(accountToken, for: .plexOwnerToken)
            account = user
            defaults.set(false, forKey: DefaultsKey.singleProfile)
            setSwitchingAvailable(true)
            _ = try await refreshHomeUsers(ownerToken: accountToken)
            let found = try await trackedServers(token: accountToken)
            knownServers = found
            if found.count == 1 { try await choose(server: found[0]) }
            return found
        } catch {
            if case .ready = snapshotValue.state {} else {
                try? secrets.remove(.plexOwnerToken)
                setState(.signedOut)
            }
            throw error
        }
    }

    /// Server-only route: an address plus a token. The token is stored as the owner token. If plex.tv
    /// accepts it as an account token, Home users and switching work; otherwise there is one profile.
    public func signInManually(address: String, token: String) async throws {
        let url = try ServerAddress.parse(address)
        setState(.connecting)
        let previousState = snapshotValue.state
        do {
            let found = try await prober.probe(connections: [.manual(url: url)])
            // /identity needs no token, so check the token against a call that does.
            _ = try await transport.perform(
                endpoints.librarySections(base: found.url, token: token), host: .server)

            try secrets.setString(token, for: .plexOwnerToken)
            var ownerID = Self.singleProfileID
            var switching = false
            do {
                let accountData = try await plexTV(endpoints.user(token: token))
                let user = try PlexJSON.decode(PlexAccount.self, from: accountData)
                account = user
                let users = try await refreshHomeUsers(ownerToken: token)
                ownerID = PlexUserID(ProfileSync.ownerUser(in: users, account: user)?.id ?? String(user.id))
                switching = true
            } catch {
                account = nil
                homeUsersCache = []
                try await saveSingleProfile()
            }
            defaults.set(!switching, forKey: DefaultsKey.singleProfile)
            setSwitchingAvailable(switching)

            let name = url.host(percentEncoded: false) ?? "Server"
            let server = ConnectedTarget(
                name: name, machineID: found.identity.machineIdentifier, url: found.url, tier: found.tier,
                manualURL: url)
            try await activate(profileID: ownerID, accountToken: token, serverToken: token, on: server)
        } catch {
            if case .ready = previousState {} else {
                try? secrets.remove(.plexOwnerToken)
                setState(.signedOut)
            }
            throw error
        }
    }

    // MARK: Servers

    /// Servers the owner account can reach (fetches from plex.tv).
    public func servers() async throws -> [PlexServer] {
        guard let token = try secrets.string(for: .plexOwnerToken) else { throw PlexError.notSignedIn }
        let found = try await trackedServers(token: token)
        knownServers = found
        return found
    }

    /// Connects to a server as the owner profile and saves the choice.
    public func choose(server: PlexServer) async throws {
        guard let ownerToken = try secrets.string(for: .plexOwnerToken) else { throw PlexError.notSignedIn }
        setState(.connecting)
        let saved = await savedChoice()
        let result: ProbeResult
        do {
            result = try await prober.probe(
                connections: server.connections,
                lastGood: saved?.machineID == server.machineID ? saved?.lastURI : nil,
                expectedMachineID: server.machineID)
        } catch {
            setState(.serverUnreachable)
            throw error
        }
        let ownerID = await ownerUserID()
        let target = ConnectedTarget(
            name: server.name, machineID: server.machineID, url: result.url, tier: result.tier, manualURL: nil)
        try await activate(
            profileID: ownerID, accountToken: ownerToken, serverToken: server.accessToken ?? ownerToken,
            on: target)
    }

    // MARK: Profiles

    /// Home users, refreshed from plex.tv; also syncs the settings document. In single-profile mode
    /// this is just the one profile.
    public func homeUsers() async throws -> [PlexHomeUser] {
        guard let token = try secrets.string(for: .plexOwnerToken) else { throw PlexError.notSignedIn }
        if defaults.bool(forKey: DefaultsKey.singleProfile) {
            return [PlexHomeUser(id: Self.singleProfileID.rawValue, uuid: "", title: "Me", admin: true)]
        }
        return try await refreshHomeUsers(ownerToken: token)
    }

    /// Switches profile. A wrong PIN on a protected user throws `pinIncorrect` and counts against the
    /// lockout; transport failures throw `plexTVUnreachable` and do not. Nothing is committed unless
    /// plex.tv accepted the switch.
    public func switchProfile(to id: PlexUserID, pin: String?) async throws {
        guard snapshotValue.profileSwitchingAvailable,
            let ownerToken = try secrets.string(for: .plexOwnerToken)
        else { throw PlexError.notSignedIn }
        if id == profile?.id, case .ready = snapshotValue.state { return }
        guard let saved = await savedChoice() else { throw PlexError.notSignedIn }

        var lockout = loadLockout()
        if lockout.isLocked(at: clock()), let until = lockout.lockedUntil { throw PlexError.lockedOut(until: until) }

        let users = try await refreshHomeUsers(ownerToken: ownerToken)
        guard let user = users.first(where: { PlexUserID($0.id) == id }) else { throw PlexError.unauthorized }
        let ownerID = await ownerUserID()
        let isOwner = id == ownerID
        let enteredPIN = pin ?? ""
        if user.protected && enteredPIN.isEmpty { throw PlexError.pinRequired }

        let accountToken: String
        if isOwner && !user.protected {
            accountToken = ownerToken
        } else {
            let request = endpoints.switchUser(
                id: user.id, pin: user.protected ? enteredPIN : nil, ownerToken: ownerToken)
            do {
                let data = try await plexTV(request)
                let result = try PlexJSON.decode(PlexSwitchResult.self, from: data)
                accountToken = isOwner ? ownerToken : result.authToken
            } catch PlexError.unauthorized where user.protected {
                lockout = loadLockout()
                lockout.recordFailure(at: clock())
                saveLockout(lockout)
                if lockout.isLocked(at: clock()), let until = lockout.lockedUntil {
                    throw PlexError.lockedOut(until: until)
                }
                throw PlexError.pinIncorrect
            }
        }
        if user.protected {
            lockout = loadLockout()
            lockout.recordSuccess()
            saveLockout(lockout)
        }

        // The server access token for this user comes from plex.tv with the user's own token.
        let found = try await trackedServers(token: accountToken)
        guard let server = found.first(where: { $0.machineID == saved.machineID }) ?? manualServer(saved) else {
            throw PlexError.unauthorized
        }
        let target = ConnectedTarget(
            name: server.name, machineID: server.machineID, url: nil, tier: nil, manualURL: saved.manualURL,
            connections: server.connections, lastGood: saved.lastURI)
        try await activate(
            profileID: id, accountToken: accountToken, serverToken: server.accessToken ?? accountToken,
            on: target)
    }

    /// Re-opens the last profile from what is stored. No PIN, and no plex.tv needed when the saved
    /// address still answers. Returns false when nothing is saved (show sign-in). Also the "Try again".
    @discardableResult
    public func resume() async -> Bool {
        guard let lastID = defaults.string(forKey: DefaultsKey.lastProfileID),
            let saved = await savedChoice(),
            (try? secrets.string(for: Self.serverTokenKey(PlexUserID(lastID)))) != nil
        else {
            setState(.signedOut)
            return false
        }
        let id = PlexUserID(lastID)
        let ownerToken = try? secrets.string(for: .plexOwnerToken)
        let single = defaults.bool(forKey: DefaultsKey.singleProfile)
        setSwitchingAvailable(!single && ownerToken != nil)
        let doc = await settings.document
        if let stored = doc.profiles[id] {
            profile = Self.activeProfile(stored, owner: doc.household.ownerPlexUserID)
        }
        setState(.connecting)

        // First the remembered addresses alone, so a plex.tv outage does not slow the launch.
        var cached: [PlexConnection] = []
        for url in [saved.lastURI, saved.manualURL].compactMap({ $0 }) { cached.append(.manual(url: url)) }
        var result = try? await prober.probe(
            connections: cached, lastGood: saved.lastURI, expectedMachineID: saved.machineID)

        if result == nil, let token = (try? secrets.string(for: .plexUserToken(id))) ?? ownerToken {
            if let found = try? await trackedServers(token: token),
                let server = found.first(where: { $0.machineID == saved.machineID })
            {
                result = try? await prober.probe(
                    connections: server.connections + cached, lastGood: saved.lastURI,
                    expectedMachineID: saved.machineID)
            }
        }
        guard let result, let profile else {
            setState(.serverUnreachable)
            return true
        }
        await remember(url: result.url)
        setState(
            .ready(
                profile: profile,
                server: PlexConnectedServer(
                    name: saved.name, machineID: saved.machineID, baseURL: result.url, tier: result.tier)))
        return true
    }

    /// After `resume()`: asks plex.tv for the Home users once (which also syncs restrictions into the
    /// settings document) so `plexTVReachable` reflects reality. Never changes the current profile, never throws.
    public func refreshFromPlexTV() async {
        guard !defaults.bool(forKey: DefaultsKey.singleProfile),
            let ownerToken = try? secrets.string(for: .plexOwnerToken)
        else { return }
        // `refreshHomeUsers` goes through `plexTV`, which records reachability.
        do { _ = try await refreshHomeUsers(ownerToken: ownerToken) } catch {
            Self.log.error("Could not refresh from plex.tv")
        }
    }

    /// Library count of the connected server, for the "Connected to <name>, <n> libraries" line.
    public func librarySummary() async throws -> PlexLibrarySummary {
        guard case .ready(let active, let server) = snapshotValue.state,
            let token = try secrets.string(for: Self.serverTokenKey(active.id))
        else { throw PlexError.notSignedIn }
        let data = try await transport.perform(
            endpoints.librarySections(base: server.baseURL, token: token), host: .server)
        return try PlexLibrarySummary.decode(from: data)
    }

    /// `/identity` on the connected server, for the module's "Test connection".
    public func testServerConnection() async -> TestResult {
        guard case .ready(_, let server) = snapshotValue.state else {
            return .failure("Can't reach your library right now")
        }
        do {
            let data = try await transport.perform(
                endpoints.serverIdentity(base: server.baseURL), host: .server)
            let identity = try PlexServerIdentity.decode(from: data)
            guard identity.machineIdentifier == server.machineID else { return .failure("Wrong library") }
            return .success("Connected to \(server.name)")
        } catch {
            return .failure("Can't reach your library right now")
        }
    }

    /// Forgets every Plex token and the saved server choice. The PIN lockout is kept on purpose.
    public func signOut() async {
        var ids = Set<PlexUserID>(homeUsersCache.map { PlexUserID($0.id) })
        let doc = await settings.document
        ids.formUnion(doc.profiles.keys)
        ids.insert(Self.singleProfileID)
        for id in ids {
            try? secrets.remove(.plexUserToken(id))
            try? secrets.remove(Self.serverTokenKey(id))
        }
        try? secrets.remove(.plexOwnerToken)
        defaults.removeObject(forKey: DefaultsKey.lastProfileID)
        defaults.removeObject(forKey: DefaultsKey.singleProfile)
        try? await settings.update { $0.modules[PlexSession.moduleID] = nil }
        account = nil
        homeUsersCache = []
        knownServers = []
        profile = nil
        setSwitchingAvailable(true)
        setPlexTVReachable(true)
        setState(.signedOut)
    }

    // MARK: Internals

    private struct ConnectedTarget {
        var name: String
        var machineID: String
        var url: URL?
        var tier: PlexConnectionTier?
        var manualURL: URL?
        var connections: [PlexConnection] = []
        var lastGood: URL?
    }

    private static func serverTokenKey(_ id: PlexUserID) -> SecretKey {
        .module(moduleID, "server.\(id.rawValue)")
    }

    private static func activeProfile(_ stored: ProfileSettings, owner: PlexUserID?) -> PlexActiveProfile {
        PlexActiveProfile(
            id: stored.plexUserID, displayName: stored.displayName, isOwner: stored.plexUserID == owner,
            restriction: stored.plexRestriction)
    }

    private func trackedServers(token: String) async throws -> [PlexServer] {
        try await viaPlexTV { try await discovery.servers(token: token) }
    }

    private func manualServer(_ saved: SavedChoice) -> PlexServer? {
        guard let url = saved.manualURL else { return nil }
        return PlexServer(
            name: saved.name, machineID: saved.machineID, owned: true, connections: [.manual(url: url)])
    }

    /// Probes if needed, then stores tokens, remembers the profile and the server, and goes ready.
    private func activate(
        profileID: PlexUserID, accountToken: String, serverToken: String, on target: ConnectedTarget
    ) async throws {
        var url = target.url
        var tier = target.tier
        var serverReachable = true
        if url == nil {
            do {
                var connections = target.connections
                if let manual = target.manualURL { connections.append(.manual(url: manual)) }
                let result = try await prober.probe(
                    connections: connections, lastGood: target.lastGood, expectedMachineID: target.machineID)
                url = result.url
                tier = result.tier
            } catch {
                serverReachable = false
            }
        }

        // Commit: tokens, last profile, server choice.
        try secrets.setString(accountToken, for: .plexUserToken(profileID))
        try secrets.setString(serverToken, for: Self.serverTokenKey(profileID))
        defaults.set(profileID.rawValue, forKey: DefaultsKey.lastProfileID)
        let doc = await settings.document
        guard let stored = doc.profiles[profileID] else {
            // Profile sync has not seen this user (should not happen); fail closed rather than guess a role.
            throw PlexError.unauthorized
        }
        let active = Self.activeProfile(stored, owner: doc.household.ownerPlexUserID)
        profile = active
        if let url { await saveChoice(target, url: url) }

        guard serverReachable, let url, let tier else {
            setState(.serverUnreachable)
            return
        }
        setState(
            .ready(
                profile: active,
                server: PlexConnectedServer(
                    name: target.name, machineID: target.machineID, baseURL: url, tier: tier)))
    }

    private func saveChoice(_ target: ConnectedTarget, url: URL) async {
        let machineID = target.machineID
        let name = target.name
        let manual = target.manualURL?.absoluteString
        let uri = url.absoluteString
        do {
            try await settings.update { doc in
                var module = doc.modules[PlexSession.moduleID] ?? ModuleSettings()
                module.enabled = true
                module.config[ConfigKey.machineID] = machineID
                module.config[ConfigKey.serverName] = name
                module.config[ConfigKey.lastURI] = uri
                module.config[ConfigKey.manualURL] = manual
                doc.modules[PlexSession.moduleID] = module
            }
        } catch {
            Self.log.error("Could not save the server choice")
        }
    }

    private func remember(url: URL) async {
        let uri = url.absoluteString
        try? await settings.update { doc in
            guard var module = doc.modules[PlexSession.moduleID] else { return }
            module.config[ConfigKey.lastURI] = uri
            doc.modules[PlexSession.moduleID] = module
        }
    }

    private func savedChoice() async -> SavedChoice? {
        let config = await settings.document.modules[Self.moduleID]?.config ?? [:]
        guard let machineID = config[ConfigKey.machineID], !machineID.isEmpty else { return nil }
        return SavedChoice(
            machineID: machineID, name: config[ConfigKey.serverName] ?? "",
            lastURI: config[ConfigKey.lastURI].flatMap { URL(string: $0) },
            manualURL: config[ConfigKey.manualURL].flatMap { URL(string: $0) })
    }

    private func ownerUserID() async -> PlexUserID {
        if let owner = await settings.document.household.ownerPlexUserID { return owner }
        return Self.singleProfileID
    }

    private func ownerAccount(token: String) async throws -> PlexAccount {
        if let account { return account }
        let data = try await plexTV(endpoints.user(token: token))
        let fetched = try PlexJSON.decode(PlexAccount.self, from: data)
        account = fetched
        return fetched
    }

    /// Fetches Home users, writes them to the settings document, and tells AdminPIN about the owner's PIN.
    private func refreshHomeUsers(ownerToken: String) async throws -> [PlexHomeUser] {
        let data = try await plexTV(endpoints.homeUsers(token: ownerToken))
        let users = try PlexHomeUser.decodeList(from: data)
        let owner = try await ownerAccount(token: ownerToken)
        let pinProtected = ProfileSync.ownerUser(in: users, account: owner)?.protected
        do {
            try await settings.update { doc in
                doc = ProfileSync.sync(homeUsers: users, ownerAccount: owner, into: doc).document
            }
        } catch {
            Self.log.error("Could not save the profiles")
            throw error
        }
        homeUsersCache = users
        if let pinProtected { await adminPIN?.setOwnerHasPlexPIN(pinProtected) }
        return users
    }

    /// Manual route without plex.tv: one unrestricted parent profile.
    private func saveSingleProfile() async throws {
        let id = Self.singleProfileID
        try await settings.update { doc in
            doc.household.ownerPlexUserID = id
            if doc.profiles[id] == nil {
                doc.profiles[id] = ProfileSettings.defaults(
                    plexUserID: id, displayName: "Me", isOwner: true, restriction: .unrestricted)
            }
        }
    }

    private func loadLockout() -> PINLockout {
        guard let data = defaults.data(forKey: DefaultsKey.profilePINLockout) else { return PINLockout() }
        if let decoded = try? JSONDecoder().decode(PINLockout.self, from: data) { return decoded }
        // A corrupt record must not unlock: start locked for the base period (as AdminPIN does).
        return PINLockout(
            failedAttempts: 0, lockoutCount: 1,
            lockedUntil: clock().addingTimeInterval(PINLockout.baseLockout))
    }

    private func saveLockout(_ lockout: PINLockout) {
        defaults.set(try? JSONEncoder().encode(lockout), forKey: DefaultsKey.profilePINLockout)
    }
}
