/// What a profile switch needs before it may go ahead (docs/PERMISSIONS.md, docs/MODULES.md).
public enum SwitchRequirement: Sendable, Equatable {
    case none
    /// The target profile's own Plex Home PIN, checked by plex.tv.
    case targetPlexPIN
    /// The Admin PIN, verified by AdminPIN.
    case adminPIN
}

/// The leave-a-kid-profile rule, in one pure place so no screen can skip it.
public enum ProfileSwitchPolicy {
    /// - Parameters:
    ///   - fromRole: Role of the profile being left. The caller passes the current profile's role,
    ///     or, when nothing resumed (failed resume), the stored role of the last profile, so a kid
    ///     last on the TV cannot pick an adult freely. `nil` means a first-ever pick: no history.
    ///   - targetRole: Role of the profile being opened.
    ///   - targetIsProtected: The target has a Plex Home PIN.
    ///   - targetHasPlexPIN: Same fact from the PIN side; the target needs its PIN if either is true.
    /// - Returns: Leaving a kid profile (always, whatever `pinRequiredToExit` says) for a non-kid
    ///   target needs the target's Plex PIN if it has one, else the Admin PIN. Otherwise a protected
    ///   target needs its own Plex PIN. Otherwise nothing.
    public static func requirement(
        fromRole: Role?, toRole targetRole: Role, targetIsProtected: Bool, targetHasPlexPIN: Bool
    ) -> SwitchRequirement {
        let targetPIN = targetIsProtected || targetHasPlexPIN
        if fromRole == .kid && targetRole != .kid {
            return targetPIN ? .targetPlexPIN : .adminPIN
        }
        return targetPIN ? .targetPlexPIN : .none
    }

    /// Convenience for the usual caller: the current profile's settings, else the stored last
    /// profile's role.
    public static func requirement(
        from current: ProfileSettings?, fallbackRole: Role?, to target: ProfileSettings,
        targetIsProtected: Bool, targetHasPlexPIN: Bool
    ) -> SwitchRequirement {
        requirement(
            fromRole: current?.role ?? fallbackRole, toRole: target.role,
            targetIsProtected: targetIsProtected, targetHasPlexPIN: targetHasPlexPIN)
    }
}
