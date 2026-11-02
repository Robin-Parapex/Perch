/// What a role may do with one action, before context (rooms, PIN freshness, AI level) is applied.
/// Replaces MODULES.md's `requiredRole(for:) -> Role`, which cannot express PIN-fresh or queued
/// (DECISIONS.md, WP-02).
public enum Access: String, Codable, Sendable, CaseIterable {
    case allow
    case deny
    /// Allowed after a PIN prompt (the kids' profile exit and Settings).
    case needsPIN
    /// Allowed only if the Admin PIN was entered in the last 5 minutes on this device.
    case needsFreshPIN
    /// Allowed, but the result waits for a parent's approval (title requests).
    case queued
    /// Allowed with a reduced surface (teen Settings).
    case limited
}

/// Access per role for one action. The Top Shelf pseudo-role is denied unless stated.
public struct ActionPolicy: Codable, Sendable, Equatable {
    public var parent: Access
    public var teen: Access
    public var kid: Access
    public var topShelf: Access
    /// Privileged actions are always written to the audit log by the Authoriser.
    public var isPrivileged: Bool

    public init(
        parent: Access, teen: Access, kid: Access, topShelf: Access = .deny,
        isPrivileged: Bool = false
    ) {
        self.parent = parent
        self.teen = teen
        self.kid = kid
        self.topShelf = topShelf
        self.isPrivileged = isPrivileged
    }

    public func access(for role: Role) -> Access {
        switch role {
        case .parent: parent
        case .teen: teen
        case .kid: kid
        case .topShelf: topShelf
        }
    }

    /// Parent only, everyone else denied.
    public static let parentOnly = ActionPolicy(parent: .allow, teen: .deny, kid: .deny)
}
