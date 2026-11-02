/// Roles from docs/PERMISSIONS.md. Defaults: owner and unrestricted users are parent,
/// restricted users are kid, teen only by assignment in Admin (DECISIONS.md, WP-02).
public enum Role: String, Codable, Sendable, CaseIterable {
    case parent
    case teen
    case kid
    /// Read-only pseudo-role for the Top Shelf extension: browse at the household's lowest ceiling.
    case topShelf
}
