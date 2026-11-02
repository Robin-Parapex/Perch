import Testing

@testable import PerchCore

struct CertificateParsingTests {
    @Test(arguments: [
        ("G", RatingCeiling.u), ("U", .u), ("PG", .pg), ("PG-13", .twelveA), ("12", .twelveA),
        ("12A", .twelveA), ("R", .fifteen), ("15", .fifteen), ("NC-17", .eighteen), ("18", .eighteen),
    ])
    func parses(_ text: String, _ expected: RatingCeiling) {
        #expect(RatingCeiling(certificate: text) == expected)
    }

    @Test func prefixesAndCase() {
        #expect(RatingCeiling(certificate: "gb/12A") == .twelveA)
        #expect(RatingCeiling(certificate: "US/PG-13") == .twelveA)
        #expect(RatingCeiling(certificate: " pg ") == .pg)
        #expect(RatingCeiling(certificate: "nc-17") == .eighteen)
    }

    @Test func unknownIsNil() {
        #expect(RatingCeiling(certificate: "Not Rated") == nil)
        #expect(RatingCeiling(certificate: "") == nil)
        #expect(RatingCeiling(certificate: "gb/") == nil)
    }

    @Test func forTitleDefaultsToFifteen() {
        #expect(RatingCeiling.forTitle(certificate: nil) == .fifteen)
        #expect(RatingCeiling.forTitle(certificate: "Unrated") == .fifteen)
        #expect(RatingCeiling.forTitle(certificate: "PG") == .pg)
    }

    @Test func plexRestrictionFromAPI() {
        #expect(PlexRestriction(restricted: false, restrictionProfile: "teen") == .unrestricted)
        #expect(PlexRestriction(restricted: true, restrictionProfile: "little_kid") == .littleKid)
        #expect(PlexRestriction(restricted: true, restrictionProfile: "Older_Kid") == .olderKid)
        #expect(PlexRestriction(restricted: true, restrictionProfile: "TEEN") == .teen)
        #expect(
            PlexRestriction(restricted: true, restrictionProfile: nil, allowedRatings: ["PG"])
                == .custom(allowedRatings: ["PG"]))
    }

    @Test func plexCeilings() {
        #expect(RatingCeiling(plex: .custom(allowedRatings: ["PG", "15", "x"])) == .fifteen)
        #expect(RatingCeiling(plex: .custom(allowedRatings: ["x"])) == .u)
        #expect(RatingCeiling.effective(plex: .teen, adminOverride: .eighteen) == .twelveA)
        #expect(RatingCeiling.effective(plex: .teen, adminOverride: .pg) == .pg)
        #expect(RatingCeiling.householdLowest([RatingCeiling.fifteen, .pg]) == .pg)
        #expect(RatingCeiling.householdLowest([RatingCeiling]()) == .u)
        #expect(RatingCeiling.pg.allows(.u) && !RatingCeiling.pg.allows(.twelveA))
    }
}
