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
        /// Non-secret fields of the last Home user list, so the picker can show locked profiles offline.
        public static let homeUsersCache = "plex.homeUsersCache"
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
    private var homeUsersCache: [PlexHomeUser] = [] {
        didSet { Self.storeCachedUsers(homeUsersCache, in: defaults) }
    }
    private var profile: PlexActiveProfile?
    private var knownServers: [PlexServer] = []
    private var switchInFlight = false
    private var connectionUpgrade: Task<Void, Never>?

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
        self.homeUsersCache = Self.loadCachedUsers(from: defaults)
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

    /// Bumped whenever the ready profile, machine or base URL changes, or the session leaves ready.
    /// Library results fetched under an older value are stale and must be dropped.
    private var generation: UInt64 = 0

    private static func readyKey(_ state: PlexSessionState) -> String? {
        guard case .ready(let profile, let server) = state else { return nil }
        return [profile.id.rawValue, server.machineID, server.baseURL.absoluteString].joined(separator: "\n")
    }

    private func setState(_ state: PlexSessionState) {
        if Self.readyKey(snapshotValue.state) != Self.readyKey(state) { generation &+= 1 }
        if case .ready(_, let next) = state, Self.baseURL(of: snapshotValue.state) != next.baseURL {
            Self.logConnection(next.baseURL, tier: next.tier)
        }
        snapshotValue.state = state
        publish()
    }

    private static func baseURL(of state: PlexSessionState) -> URL? {
        if case .ready(_, let server) = state { server.baseURL } else { nil }
    }

    /// One line per change of server address: scheme, host, port and tier (never a token; none is in it).
    private static func logConnection(_ url: URL, tier: PlexConnectionTier) {
        log.info(
            "Plex connection: \(url.scheme ?? "", privacy: .public)://\(url.host(percentEncoded: false) ?? "", privacy: .public):\(url.port ?? 0, privacy: .public) tier=\(String(describing: tier), privacy: .public)"
        )
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
        let previous = capturePrevious()
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
            restore(previous)
            throw error
        }
    }

    /// What a failed sign-in must put back: a failed attempt never wipes an existing sign-in.
    private struct PreviousSignIn {
        var state: PlexSessionState
        var ownerToken: String?
        var account: PlexAccount?
        var homeUsers: [PlexHomeUser]
        var profile: PlexActiveProfile?
        var single: Bool
        var switching: Bool
    }

    private func capturePrevious() -> PreviousSignIn {
        PreviousSignIn(
            state: snapshotValue.state, ownerToken: (try? secrets.string(for: .plexOwnerToken)) ?? nil,
            account: account, homeUsers: homeUsersCache, profile: profile,
            single: defaults.bool(forKey: DefaultsKey.singleProfile),
            switching: snapshotValue.profileSwitchingAvailable)
    }

    private func restore(_ previous: PreviousSignIn) {
        if let token = previous.ownerToken {
            try? secrets.setString(token, for: .plexOwnerToken)
        } else {
            try? secrets.remove(.plexOwnerToken)
        }
        account = previous.account
        homeUsersCache = previous.homeUsers
        profile = previous.profile
        defaults.set(previous.single, forKey: DefaultsKey.singleProfile)
        setSwitchingAvailable(previous.switching)
        setState(previous.state == .connecting ? .signedOut : previous.state)
    }

    /// Server-only route: an address plus a token. The token is stored as the owner token. If plex.tv
    /// accepts it as an account token, Home users and switching work; otherwise there is one profile.
    public func signInManually(address: String, token: String) async throws {
        let url = try ServerAddress.parse(address)
        let previous = capturePrevious()
        setState(.connecting)
        do {
            let found = try await prober.probe(connections: [.manual(url: url)])
            // /identity needs no token, so check the token against a call that does.
            _ = try await transport.perform(
                endpoints.librarySections(base: found.url, token: token), host: .server)

            try secrets.setString(token, for: .plexOwnerToken)
            var ownerID = Self.singleProfileID
            var switching = false
            // Only plex.tv refusing the token means "server-only token"; any other failure is a failed sign-in.
            var accountData: Data?
            do {
                accountData = try await plexTV(endpoints.user(token: token))
            } catch PlexError.unauthorized {
                accountData = nil
            }
            if let accountData {
                let user = try PlexJSON.decode(PlexAccount.self, from: accountData)
                account = user
                let users = try await refreshHomeUsers(ownerToken: token)
                ownerID = PlexUserID(ProfileSync.ownerUser(in: users)?.id ?? String(user.id))
                switching = true
            } else {
                account = nil
                homeUsersCache = []
                try await saveSingleProfile()
                // No Plex PIN to reuse, so a Perch Admin PIN can be set.
                await adminPIN?.setOwnerHasPlexPIN(false)
            }
            defaults.set(!switching, forKey: DefaultsKey.singleProfile)
            setSwitchingAvailable(switching)

            let name = url.host(percentEncoded: false) ?? "Server"
            let server = ConnectedTarget(
                name: name, machineID: found.identity.machineIdentifier, url: found.url, tier: found.tier,
                manualURL: url)
            try await activate(profileID: ownerID, accountToken: token, serverToken: token, on: server)
        } catch {
            restore(previous)
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

    /// What switching to `user` needs, by `ProfileSwitchPolicy`, from the session's own record of the
    /// current (or last) profile. Read-only, makes no request; the picker uses it to choose the PIN
    /// screen. `switchProfile` recomputes it from fresh plex.tv data and refuses on a difference.
    public func switchRequirement(for user: PlexHomeUser) async -> SwitchRequirement {
        let doc = await settings.document
        let targetID = PlexUserID(user.id)
        let targetRole =
            doc.profiles[targetID]?.role
            ?? ProfileSettings.defaults(
                plexUserID: targetID, displayName: user.displayName, isOwner: user.admin,
                restriction: user.restriction
            ).role
        let fromRole = ProfileSwitchPolicy.startingRole(
            currentID: profile?.id,
            lastID: defaults.string(forKey: DefaultsKey.lastProfileID).map { PlexUserID($0) },
            profiles: doc.profiles)
        return ProfileSwitchPolicy.requirement(
            fromRole: fromRole, toRole: targetRole,
            targetIsProtected: user.protected, targetHasPlexPIN: user.protected)
    }

    /// The only way to switch profile. The session applies `ProfileSwitchPolicy` itself, after
    /// refreshing the Home users, so a caller cannot weaken it. `pin` is the target's Plex PIN
    /// (`.targetPlexPIN`) or the Admin PIN (`.adminPIN`, checked here through the session's AdminPIN).
    /// If `expecting` is given and the fresh requirement differs, throws `requirementChanged` before
    /// any PIN is checked or sent, so the UI re-asks. Offline, throws `plexTVUnreachable` and the
    /// current profile stays.
    ///
    /// A wrong target PIN throws `pinIncorrect` and counts against the lockout; transport failures
    /// throw `plexTVUnreachable` and do not. Nothing is committed unless the checks and plex.tv pass.
    public func switchProfile(
        to id: PlexUserID, pin: String?, expecting: SwitchRequirement? = nil
    ) async throws {
        guard snapshotValue.profileSwitchingAvailable,
            let ownerToken = try secrets.string(for: .plexOwnerToken)
        else { throw PlexError.notSignedIn }
        if id == profile?.id, case .ready = snapshotValue.state { return }
        guard let saved = await savedChoice() else { throw PlexError.notSignedIn }

        // One switch at a time: a second concurrent request is refused (the UI disables the button too).
        guard !switchInFlight else { throw PlexError.switchInProgress }
        switchInFlight = true
        defer { switchInFlight = false }

        // The lockout only guards protected users. Before asking plex.tv, use the last known list
        // (unknown user counts as protected) so a locked-out attempt makes no request.
        var lockout = loadLockout()
        if homeUsersCache.first(where: { PlexUserID($0.id) == id })?.protected ?? true {
            try throwIfLocked(lockout)
        }

        let users = try await refreshHomeUsers(ownerToken: ownerToken)
        guard let user = users.first(where: { PlexUserID($0.id) == id }) else { throw PlexError.unauthorized }
        if user.protected { try throwIfLocked(loadLockout()) }
        let ownerID = await ownerUserID()
        let isOwner = id == ownerID
        let enteredPIN = pin ?? ""
        if user.protected && enteredPIN.isEmpty { throw PlexError.pinRequired }

        // The policy, from fresh data. Never a weaker check than the UI asked for.
        let required = await switchRequirement(for: user)
        if let expecting, expecting != required { throw PlexError.requirementChanged(required) }
        switch required {
        case .none:
            break
        case .targetPlexPIN:
            if enteredPIN.isEmpty { throw PlexError.pinRequired }
        case .adminPIN:
            guard let adminPIN else { throw PlexError.adminVerificationRequired }
            if enteredPIN.isEmpty { throw PlexError.pinRequired }
            switch await adminPIN.verify(enteredPIN) {
            case .accepted: break
            case .rejected: throw PlexError.pinIncorrect
            case .lockedOut(let until): throw PlexError.lockedOut(until: until)
            case .setupRequired, .plexUnreachable, .unavailable: throw PlexError.adminVerificationRequired
            }
        }

        let accountToken: String
        if isOwner && !user.protected {
            accountToken = ownerToken
        } else {
            let request = endpoints.switchUser(
                id: user.id, pin: user.protected ? enteredPIN : nil, ownerToken: ownerToken)
            do {
                let data = try await plexTV(request)
                let result = try PlexSwitchResult.decode(from: data)
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
            // Re-check after the plex.tv await: the lock may have started meanwhile; nothing is committed then.
            lockout = loadLockout()
            try throwIfLocked(lockout)
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

        let token = (try? secrets.string(for: .plexUserToken(id))) ?? ownerToken
        if result == nil, let token {
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
        // A remembered public address works but makes Plex cap the stream: look for a LAN address
        // without holding up the launch.
        if result.tier != .local, let token {
            connectionUpgrade = Task { await self.upgradeConnection(token: token, cached: cached) }
        }
        return true
    }

    /// Background check after `resume()` on a non-local address: fetches the server's addresses from
    /// plex.tv and probes them; if a strictly better tier answers while the same profile and address are
    /// still current, later requests use it and it becomes `lastURI`. Work already started (requests in
    /// flight, a playing item, timeline reports) keeps its URL: the generation does not change, because
    /// the server is the same. Does not touch `plexTVReachable`; failures leave everything as it was.
    private func upgradeConnection(token: String, cached: [PlexConnection]) async {
        guard case .ready(let startProfile, let start) = snapshotValue.state else { return }
        guard let found = try? await discovery.servers(token: token),
            let server = found.first(where: { $0.machineID == start.machineID }),
            let fresh = try? await prober.probe(
                connections: server.connections + cached, lastGood: start.baseURL,
                expectedMachineID: start.machineID),
            fresh.tier < start.tier
        else { return }
        // Re-check after the awaits: a profile switch, server change or sign-out wins over this.
        guard case .ready(let profile, let current) = snapshotValue.state, profile.id == startProfile.id,
            current == start
        else { return }
        snapshotValue.state = .ready(
            profile: profile,
            server: PlexConnectedServer(
                name: current.name, machineID: current.machineID, baseURL: fresh.url, tier: fresh.tier))
        Self.logConnection(fresh.url, tier: fresh.tier)
        publish()
        await remember(url: fresh.url)
    }

    /// For tests: waits for the background connection check started by `resume()`, if any.
    func awaitConnectionUpgrade() async { await connectionUpgrade?.value }

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

    /// The strictest ceiling in the household (U when no profile is known), for art shown on kid screens.
    public func householdArtCeiling() async -> RatingCeiling {
        await settings.document.householdLowestCeiling
    }

    /// Backdrop art paths (for example `/library/metadata/1/art/2`) from the connected server's newest
    /// items. Paths carry no token; fetch the bytes with `imageData(for:)`.
    /// Only items whose rating is at or below `ceiling` are kept; unrated or unknown ratings are
    /// dropped. The default is the strictest (U), so a caller that forgets stays safe.
    public func libraryArt(limit: Int = 12, ceiling: RatingCeiling = .u) async throws -> [String] {
        let (base, token) = try serverContext()
        let data = try await transport.perform(
            endpoints.recentlyAdded(base: base, token: token, limit: limit), host: .server)
        return try PlexArtList.decode(from: data, limit: limit, ceiling: ceiling)
    }

    /// Image bytes for a server path. The token travels only in the `X-Plex-Token` header, and only
    /// to the connected server; a path that is not a plain server path is refused.
    public func imageData(for path: String) async throws -> Data {
        let (base, token) = try serverContext()
        guard let request = endpoints.image(base: base, path: path, token: token) else {
            throw PlexError.unauthorized
        }
        return try await transport.perform(request, host: .server)
    }

    private func serverContext() throws -> (URL, String) {
        let context = try libraryContext()
        return (context.baseURL, context.token)
    }

    /// The ready profile's context. The server token is read from the Keychain here and goes no further
    /// than PerchPlex.
    func libraryContext() throws -> PlexServerContext {
        guard case .ready(let active, let server) = snapshotValue.state,
            let token = try secrets.string(for: Self.serverTokenKey(active.id))
        else { throw PlexError.notSignedIn }
        return PlexServerContext(
            baseURL: server.baseURL, token: token, profileID: active.id.rawValue,
            machineID: server.machineID, generation: generation)
    }

    func currentGeneration() -> UInt64 { generation }

    /// The last Home user list as stored (non-secret fields only). Empty before the first sync.
    public func cachedHomeUsers() -> [PlexHomeUser] { homeUsersCache }

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
            id: stored.plexUserID, displayName: stored.displayName,
            isOwner: stored.plexUserID == owner || stored.plexUserID == singleProfileID,
            restriction: stored.plexRestriction)
    }

    /// What is written under `homeUsersCache`: never a token, never the username or restriction profile.
    private struct CachedHomeUser: Codable {
        var id: String
        var uuid: String
        var title: String
        var thumb: String?
        var protected: Bool
        var restricted: Bool
        var admin: Bool
    }

    private static func storeCachedUsers(_ users: [PlexHomeUser], in defaults: UserDefaults) {
        let rows = users.map {
            CachedHomeUser(
                id: $0.id, uuid: $0.uuid, title: $0.title, thumb: $0.thumb.map(Self.withoutTokenQuery),
                protected: $0.protected, restricted: $0.restricted, admin: $0.admin)
        }
        if rows.isEmpty {
            defaults.removeObject(forKey: DefaultsKey.homeUsersCache)
        } else {
            defaults.set(try? JSONEncoder().encode(rows), forKey: DefaultsKey.homeUsersCache)
        }
    }

    private static func loadCachedUsers(from defaults: UserDefaults) -> [PlexHomeUser] {
        guard let data = defaults.data(forKey: DefaultsKey.homeUsersCache),
            let rows = try? JSONDecoder().decode([CachedHomeUser].self, from: data)
        else { return [] }
        return rows.map {
            PlexHomeUser(
                id: $0.id, uuid: $0.uuid, title: $0.title, thumb: $0.thumb, admin: $0.admin,
                restricted: $0.restricted, protected: $0.protected)
        }
    }

    /// Avatar URLs carry no secret, but a stored URL never keeps a token-like query item.
    private static func withoutTokenQuery(_ thumb: String) -> String {
        guard var parts = URLComponents(string: thumb) else { return thumb }
        let kept = (parts.queryItems ?? []).filter { !$0.name.lowercased().contains("token") }
        parts.queryItems = kept.isEmpty ? nil : kept
        return parts.string ?? thumb
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
        // Only the Plex Home admin can own the household; refuse before anything is stored.
        let admin = ProfileSync.ownerUser(in: users)
        if let admin, admin.id != String(owner.id) { throw PlexError.notHomeOwner }
        let pinProtected = admin?.protected
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
        await applySyncedRestriction()
        return users
    }

    /// After any Home users sync: the active profile takes Plex's current restriction.
    private func applySyncedRestriction() async {
        guard let current = profile else { return }
        let doc = await settings.document
        guard let stored = doc.profiles[current.id] else { return }
        let updated = Self.activeProfile(stored, owner: doc.household.ownerPlexUserID)
        guard updated != current else { return }
        profile = updated
        if case .ready(_, let server) = snapshotValue.state {
            setState(.ready(profile: updated, server: server))
        }
    }

    /// Manual route without plex.tv: one unrestricted parent profile (no owner id is recorded).
    private func saveSingleProfile() async throws {
        let id = Self.singleProfileID
        try await settings.update { doc in
            if doc.profiles[id] == nil {
                doc.profiles[id] = ProfileSettings.defaults(
                    plexUserID: id, displayName: "Me", isOwner: true, restriction: .unrestricted)
            }
        }
    }

    private func throwIfLocked(_ lockout: PINLockout) throws {
        if lockout.isLocked(at: clock()), let until = lockout.lockedUntil { throw PlexError.lockedOut(until: until) }
    }

    private func loadLockout() -> PINLockout {
        guard let data = defaults.data(forKey: DefaultsKey.profilePINLockout) else { return PINLockout() }
        if let decoded = try? JSONDecoder().decode(PINLockout.self, from: data) { return decoded }
        // A corrupt record must not unlock: start locked for the base period (as AdminPIN does),
        // and save it so the lock ends instead of being rebuilt on every load.
        let replacement = PINLockout(
            failedAttempts: 0, lockoutCount: 1,
            lockedUntil: clock().addingTimeInterval(PINLockout.baseLockout))
        saveLockout(replacement)
        return replacement
    }

    private func saveLockout(_ lockout: PINLockout) {
        defaults.set(try? JSONEncoder().encode(lockout), forKey: DefaultsKey.profilePINLockout)
    }
}

extension PlexSession: PlexServerContextProviding {}
