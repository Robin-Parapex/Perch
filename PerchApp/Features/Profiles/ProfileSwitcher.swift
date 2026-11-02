import Foundation
import Observation
import PerchCore
import PerchPlex

/// The only place in the app that switches Plex profile (WP-05 change C3). It asks PerchCore's
/// `ProfileSwitchPolicy` what the move needs (rule from Apple TV profile pickers, after Dusk's picker),
/// checks the Admin PIN itself when that is the answer, and only then calls `PlexSession.switchProfile`.
/// It stores nothing: PlexSession records the new profile; PINs are passed on and never kept or logged.
@MainActor @Observable
final class ProfileSwitcher {
    enum Result: Equatable {
        case switched
        /// The move needs a PIN that was not given yet: the target's Plex PIN, or the Admin PIN.
        case needsPIN(SwitchRequirement)
        /// A wrong PIN or a lockout: show the message and shake.
        case rejected(String)
        /// Anything else: show the message, nothing changed.
        case failed(String)
    }

    static let cannotSwitch = "Can't switch profiles right now"
    static let wrongPIN = "That PIN isn't right"

    private let session: PlexSession
    private let settings: SettingsStore
    private let adminPIN: AdminPIN
    private let defaults: UserDefaults

    init(session: PlexSession, settings: SettingsStore, adminPIN: AdminPIN, defaults: UserDefaults) {
        self.session = session
        self.settings = settings
        self.adminPIN = adminPIN
        self.defaults = defaults
    }

    /// What switching to `user` needs from the person holding the remote.
    func requirement(for user: PlexHomeUser) async -> SwitchRequirement {
        let document = await settings.document
        let targetID = PlexUserID(user.id)
        let targetRole =
            document.profiles[targetID]?.role
            ?? ProfileSettings.defaults(
                plexUserID: targetID, displayName: user.displayName, isOwner: user.admin,
                restriction: user.restriction
            ).role
        return ProfileSwitchPolicy.requirement(
            fromRole: await currentRole(document), toRole: targetRole,
            targetIsProtected: user.protected, targetHasPlexPIN: user.protected)
    }

    /// The role the move starts from: the current profile, or the stored last profile when nothing
    /// resumed (so a kid last on the TV cannot pick an adult freely after a failed resume, C4).
    private func currentRole(_ document: SettingsDocument) async -> Role? {
        if let current = await session.currentProfile() {
            return document.profiles[current.id]?.role ?? .kid  // unknown means the strictest rule
        }
        guard let last = defaults.string(forKey: PlexSession.DefaultsKey.lastProfileID) else { return nil }
        return document.profiles[PlexUserID(last)]?.role ?? .kid
    }

    /// Switches to `user`. `pin` is the target's Plex PIN or the Admin PIN, as `requirement(for:)` says.
    func switchTo(_ user: PlexHomeUser, pin: String?) async -> Result {
        let requirement = await requirement(for: user)
        var verification: PINResult?
        var plexPIN: String?
        switch requirement {
        case .none:
            break
        case .targetPlexPIN:
            guard let pin, !pin.isEmpty else { return .needsPIN(requirement) }
            plexPIN = pin
        case .adminPIN:
            guard let pin, !pin.isEmpty else { return .needsPIN(requirement) }
            let result = await adminPIN.verify(pin)
            switch result {
            case .accepted: verification = result
            case .rejected: return .rejected(Self.wrongPIN)
            case .lockedOut(let until): return .rejected(Self.lockedMessage(until))
            case .setupRequired, .plexUnreachable, .unavailable: return .failed(Self.cannotSwitch)
            }
        }
        do {
            try await session.switchProfile(
                to: PlexUserID(user.id), pin: plexPIN, requirement: requirement,
                adminVerification: verification)
            return .switched
        } catch let error as PlexError {
            return Self.map(error, hadPIN: plexPIN != nil)
        } catch {
            return .failed(Self.cannotSwitch)
        }
    }

    private static func map(_ error: PlexError, hadPIN: Bool) -> Result {
        switch error {
        case .pinIncorrect: .rejected(wrongPIN)
        case .unauthorized: hadPIN ? .rejected(wrongPIN) : .failed(cannotSwitch)
        case .lockedOut(let until): .rejected(lockedMessage(until))
        case .pinRequired: .failed("Enter the PIN for this profile")
        default: .failed(cannotSwitch)  // plex.tv unreachable, server trouble: the current profile stays
        }
    }

    static func lockedMessage(_ until: Date) -> String {
        "Too many tries. Try again in \(duration(until))"
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
