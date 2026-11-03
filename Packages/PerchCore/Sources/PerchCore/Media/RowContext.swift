import Foundation

/// Who a row is for, and about what. Rows are built per profile (SPEC.md, everything is per
/// profile).
public struct RowContext: Sendable, Hashable {
    public var profileID: String
    /// The ceiling the library service already enforces for this profile (for Plex, the Home
    /// user's restriction).
    public var serviceCeiling: RatingCeiling
    /// The profile's effective ceiling, which an Admin may have lowered below the service's.
    public var ceiling: RatingCeiling
    /// The title or person a title-page or person-page row is about; nil on Home.
    public var subjectID: String?

    public init(
        profileID: String, serviceCeiling: RatingCeiling, ceiling: RatingCeiling,
        subjectID: String? = nil
    ) {
        self.profileID = profileID
        self.serviceCeiling = serviceCeiling
        self.ceiling = ceiling
        self.subjectID = subjectID
    }

    /// The service filters its own library, so only a ceiling lowered in Perch filters here.
    /// A title with no usable certificate counts as 15 (fails closed). WP-18 widens this to
    /// search and discover.
    public func admits(_ item: MediaSummary) -> Bool {
        guard ceiling < serviceCeiling else { return true }
        return ceiling.allows(.forTitle(certificate: item.certificate))
    }

    public func admit(_ row: MediaRow) -> MediaRow {
        var row = row
        row.items = row.items.filter(admits)
        return row
    }
}
