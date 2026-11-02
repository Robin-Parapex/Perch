import Foundation

/// The household's BBFC-style rating scale. 12 folds into 12A (DECISIONS.md, WP-02).
public enum RatingCeiling: Int, Comparable, Codable, Sendable, CaseIterable {
    case u = 0, pg, twelveA, fifteen, eighteen

    public static func < (lhs: RatingCeiling, rhs: RatingCeiling) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .u: "U"
        case .pg: "PG"
        case .twelveA: "12A"
        case .fifteen: "15"
        case .eighteen: "18"
        }
    }

    /// Parses a Plex content rating such as "PG-13", "gb/12A" or "R". Unknown values give nil.
    public init?(certificate: String) {
        var text = certificate.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let slash = text.firstIndex(of: "/") {
            text = String(text[text.index(after: slash)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        switch text {
        case "G", "U": self = .u
        case "PG": self = .pg
        case "PG-13", "12", "12A": self = .twelveA
        case "R", "15": self = .fifteen
        case "NC-17", "18": self = .eighteen
        default: return nil
        }
    }

    /// A title with no usable certificate is treated as 15 (ARCHITECTURE.md).
    public static func forTitle(certificate: String?) -> RatingCeiling {
        certificate.flatMap { RatingCeiling(certificate: $0) } ?? .fifteen
    }

    public func allows(_ title: RatingCeiling) -> Bool { title <= self }
}

/// A Plex Home user's restriction as the API reports it.
public enum PlexRestriction: Codable, Sendable, Equatable, Hashable {
    case unrestricted
    case littleKid
    case olderKid
    case teen
    case custom(allowedRatings: [String])

    public init(restricted: Bool, restrictionProfile: String?, allowedRatings: [String] = []) {
        guard restricted else {
            self = .unrestricted
            return
        }
        switch restrictionProfile?.lowercased() {
        case "little_kid": self = .littleKid
        case "older_kid": self = .olderKid
        case "teen": self = .teen
        default: self = .custom(allowedRatings: allowedRatings)
        }
    }
}

extension RatingCeiling {
    public init(plex: PlexRestriction) {
        switch plex {
        case .littleKid: self = .u
        case .olderKid: self = .pg
        case .teen: self = .twelveA
        case .unrestricted: self = .eighteen
        case .custom(let allowed):
            // Nothing recognised fails closed to U (DECISIONS.md, WP-02).
            self = allowed.compactMap { RatingCeiling(certificate: $0) }.max() ?? .u
        }
    }

    /// An admin override can lower the Plex ceiling, never raise it.
    public static func effective(plex: PlexRestriction, adminOverride: RatingCeiling?) -> RatingCeiling {
        let base = RatingCeiling(plex: plex)
        guard let adminOverride else { return base }
        return min(base, adminOverride)
    }

    public static func householdLowest<S: Sequence>(_ ceilings: S) -> RatingCeiling
    where S.Element == RatingCeiling {
        ceilings.min() ?? .u
    }
}
