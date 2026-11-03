import Foundation
import Observation
import PerchCore
import PerchPlex

/// The only place in the app that switches Plex profile (WP-05 change C3). It asks PerchCore's
/// session what the move needs (PlexSession applies PerchCore's `ProfileSwitchPolicy` and checks the
/// Admin PIN itself), then calls `PlexSession.switchProfile`.
/// It stores nothing: PlexSession records the new profile; PINs are passed on and never kept or logged.
@MainActor @Observable
final class ProfileSwitcher {
    enum Result: Equatable {
        case switched
        /// The move needs a PIN that was not given yet: the target's Plex PIN, or the Admin PIN.
        case needsPIN(SwitchRequirement)
        /// A wrong PIN: show the message and shake.
        case rejected(String)
        /// Too many wrong PINs: the keypad stays dimmed until this time.
        case locked(Date)
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

    /// What switching to `user` needs from the person holding the remote. PlexSession decides.
    func requirement(for user: PlexHomeUser) async -> SwitchRequirement {
        await session.switchRequirement(for: user)
    }

    /// Switches to `user`. `pin` is the target's Plex PIN or the Admin PIN, as `requirement(for:)` says.
    /// PlexSession re-applies the policy from fresh data and checks the Admin PIN itself; if the
    /// requirement moved since the screen was chosen, the answer is `.needsPIN` with the new one.
    func switchTo(_ user: PlexHomeUser, pin: String?) async -> Result {
        let requirement = await requirement(for: user)
        if requirement != .none, pin?.isEmpty ?? true { return .needsPIN(requirement) }
        do {
            try await session.switchProfile(to: PlexUserID(user.id), pin: pin, expecting: requirement)
            return .switched
        } catch let error as PlexError {
            return Self.map(error, hadPIN: !(pin?.isEmpty ?? true))
        } catch {
            return .failed(Self.cannotSwitch)
        }
    }

    private static func map(_ error: PlexError, hadPIN: Bool) -> Result {
        switch error {
        case .pinIncorrect: .rejected(wrongPIN)
        case .unauthorized: hadPIN ? .rejected(wrongPIN) : .failed(cannotSwitch)
        case .lockedOut(let until): .locked(until)
        case .requirementChanged(let now): .needsPIN(now)
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
