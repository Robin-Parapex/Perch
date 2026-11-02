import Foundation

/// Injected wall clock, so PIN freshness, lockouts and audit timestamps are testable.
public typealias NowProvider = @Sendable () -> Date

public enum PerchConstants {
    public static let appGroupID = "group.com.robrolabs.perch"
    /// Keychain sharing uses the App Group ID as the access group (DECISIONS.md, WP-02).
    public static let keychainAccessGroup = appGroupID
    public static let keychainService = "com.robrolabs.perch"
}
