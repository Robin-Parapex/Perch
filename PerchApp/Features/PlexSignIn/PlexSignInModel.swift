import Foundation
import Observation
import PerchCore
import PerchPlex

/// Bridges the PlexSession actor's update stream to SwiftUI.
@Observable @MainActor
final class PlexSignInModel {
    let session: PlexSession
    let transport: any PlexTransport
    let endpoints: PlexEndpoints
    /// For the debug "Check Admin PIN" demo (acceptance item 9); the real Admin entry is later.
    let adminPIN: AdminPIN
    private let settings: SettingsStore

    private(set) var snapshot = PlexSessionSnapshot.signedOut
    var servers: [PlexServer] = []

    @ObservationIgnored private var observer: Task<Void, Never>?

    init(
        session: PlexSession, transport: any PlexTransport, endpoints: PlexEndpoints, adminPIN: AdminPIN,
        settings: SettingsStore
    ) {
        self.session = session
        self.transport = transport
        self.endpoints = endpoints
        self.adminPIN = adminPIN
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

    var plexTVReachable: Bool { snapshot.plexTVReachable }
    var serverUnreachable: Bool { snapshot.state == .serverUnreachable }

    func resume() async {
        // Then ask plex.tv once, in the same background task, so the PIN notice is truthful after launch.
        if await session.resume() { await session.refreshFromPlexTV() }
    }

    /// Set by CoreServices: clears the artwork caches straight after the tokens are gone (WP-08).
    @ObservationIgnored var onSignedOut: (@MainActor () -> Void)?

    func signOut() async {
        await session.signOut()
        servers = []
        onSignedOut?()
    }

    /// Plain-words text for a sign-in or connect failure.
    static func message(for error: Error, switchingProfile: Bool = false) -> String {
        if let address = error as? ServerAddressError {
            _ = address
            return "Check the address"
        }
        if error is KeychainError { return "Couldn't save your sign-in" }
        guard let error = error as? PlexError else { return "Something went wrong. Try again" }
        switch error {
        case .unauthorized: return switchingProfile ? "That PIN isn't right" : "That token wasn't accepted"
        case .pinRequired: return "Enter the PIN for this profile"
        case .notSignedIn: return "Sign in first"
        case .notHomeOwner: return "Sign in with the account that manages your Plex Home"
        case .switchInProgress: return "Still switching profiles"
        case .adminVerificationRequired: return "Enter the Admin PIN first"
        case .pinIncorrect: return "That PIN isn't right"
        case .lockedOut(let until): return "Too many tries. Try again in \(duration(until))"
        case .plexTVUnreachable: return "Can't reach Plex right now"
        case .decoding: return "Something went wrong. Try again"
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
