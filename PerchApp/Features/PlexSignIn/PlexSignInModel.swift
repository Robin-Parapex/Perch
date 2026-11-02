import Foundation
import Observation
import PerchCore
import PerchPlex

/// Navigation targets of the sign-in flow, pushed onto the placeholder's stack.
enum PlexRoute: Hashable {
    case signIn, code, address, servers, connected, profiles
}

/// One Home user as the debug profile screen shows it.
struct PlexProfileRow: Identifiable, Equatable {
    let id: String
    let name: String
    let roleLabel: String
    let ceilingLabel: String
    let isProtected: Bool
}

/// Bridges the PlexSession actor's update stream to SwiftUI.
@Observable @MainActor
final class PlexSignInModel {
    let session: PlexSession
    let transport: any PlexTransport
    let endpoints: PlexEndpoints
    private let settings: SettingsStore

    private(set) var snapshot = PlexSessionSnapshot.signedOut
    var servers: [PlexServer] = []

    @ObservationIgnored private var observer: Task<Void, Never>?

    init(session: PlexSession, transport: any PlexTransport, endpoints: PlexEndpoints, settings: SettingsStore) {
        self.session = session
        self.transport = transport
        self.endpoints = endpoints
        self.settings = settings
        observer = Task { [weak self] in
            let updates = await session.updates()
            for await next in updates { self?.snapshot = next }
        }
    }

    deinit { observer?.cancel() }

    var currentProfileID: String? {
        if case .ready(let profile, _) = snapshot.state { profile.id.rawValue } else { nil }
    }

    var isReady: Bool {
        if case .ready = snapshot.state { true } else { false }
    }

    /// "Connected to <name>, <n> libraries".
    func connectedSummary() async -> String? {
        guard case .ready(_, let server) = snapshot.state else { return nil }
        guard let summary = try? await session.librarySummary() else { return "Connected to \(server.name)" }
        let count = summary.sectionCount
        return "Connected to \(server.name), \(count) \(count == 1 ? "library" : "libraries")"
    }

    func profileRows() async throws -> [PlexProfileRow] {
        let users = try await session.homeUsers()
        let document = await settings.document
        return users.map { user in
            let stored = document.profiles[PlexUserID(user.id)]
            let role = stored?.role ?? (user.admin ? .parent : .kid)
            let ceiling = stored?.ceilingOverride ?? RatingCeiling(plex: stored?.plexRestriction ?? user.restriction)
            return PlexProfileRow(
                id: user.id, name: user.displayName, roleLabel: Self.label(role), ceilingLabel: ceiling.label,
                isProtected: user.protected)
        }
    }

    private static func label(_ role: Role) -> String {
        switch role {
        case .parent: "Parent"
        case .teen: "Teen"
        case .kid: "Kid"
        case .topShelf: "Top Shelf"
        }
    }

    var plexTVReachable: Bool { snapshot.plexTVReachable }
    var serverUnreachable: Bool { snapshot.state == .serverUnreachable }

    func resume() async {
        // Then ask plex.tv once, in the same background task, so the PIN notice is truthful after launch.
        if await session.resume() { await session.refreshFromPlexTV() }
    }

    func signOut() async {
        await session.signOut()
        servers = []
    }

    /// Plain-words text for a sign-in or connect failure.
    static func message(for error: Error, switchingProfile: Bool = false) -> String {
        if let address = error as? ServerAddressError {
            _ = address
            return "Check the address"
        }
        switch error as? PlexError {
        case .unauthorized: return switchingProfile ? "That PIN isn't right" : "That token wasn't accepted"
        case .pinRequired: return "Enter the PIN for this profile"
        case .notSignedIn: return "Sign in first"
        case .notHomeOwner: return "Sign in with the account that manages your Plex Home"
        case .switchInProgress: return "Still switching profiles"
        case .pinIncorrect: return "That PIN isn't right"
        case .lockedOut(let until): return "Too many tries. Try again in \(duration(until))"
        case .plexTVUnreachable: return "Can't reach Plex right now"
        default: return "Can't reach that server"
        }
    }

    static func duration(_ until: Date) -> String {
        let seconds = max(1, until.timeIntervalSinceNow.rounded(.up))
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = seconds >= 3600 ? [.hour] : seconds >= 60 ? [.minute] : [.second]
        return formatter.string(from: seconds) ?? "a while"
    }
}
