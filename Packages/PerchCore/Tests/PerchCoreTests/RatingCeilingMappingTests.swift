import Testing

@testable import PerchCore

/// Table from docs/PERMISSIONS.md "Rating ceiling mapping".
struct RatingCeilingMappingTests {
    @Test func littleKidIsU() { #expect(RatingCeiling(plex: .littleKid) == .u) }
    @Test func olderKidIsPG() { #expect(RatingCeiling(plex: .olderKid) == .pg) }
    @Test func teenIs12A() { #expect(RatingCeiling(plex: .teen) == .twelveA) }
    @Test func unrestrictedIs18() { #expect(RatingCeiling(plex: .unrestricted) == .eighteen) }

    @Test(arguments: [
        (["G"], RatingCeiling.u), (["U"], .u), (["PG"], .pg),
        (["PG-13"], .twelveA), (["12"], .twelveA), (["12A"], .twelveA),
        (["R"], .fifteen), (["15"], .fifteen), (["NC-17"], .eighteen), (["18"], .eighteen),
    ])
    func customSingleRating(_ allowed: [String], _ expected: RatingCeiling) {
        #expect(RatingCeiling(plex: .custom(allowedRatings: allowed)) == expected)
    }

    @Test func customHighestAllowedWins() {
        #expect(RatingCeiling(plex: .custom(allowedRatings: ["PG", "R"])) == .fifteen)
        #expect(RatingCeiling(plex: .custom(allowedRatings: ["R", "PG"])) == .fifteen)
        #expect(RatingCeiling(plex: .custom(allowedRatings: ["G", "PG", "PG-13"])) == .twelveA)
    }

    @Test func customWithNothingRecognisedIsU() {
        #expect(RatingCeiling(plex: .custom(allowedRatings: [])) == .u)
        #expect(RatingCeiling(plex: .custom(allowedRatings: ["bogus", "??"])) == .u)
    }

    @Test func restrictedWithUnknownProfileFallsToCustom() {
        let plex = PlexRestriction(restricted: true, restrictionProfile: nil, allowedRatings: ["PG"])
        #expect(RatingCeiling(plex: plex) == .pg)
    }

    @Test func plexProfilesParse() {
        #expect(PlexRestriction(restricted: true, restrictionProfile: "little_kid") == .littleKid)
        #expect(PlexRestriction(restricted: true, restrictionProfile: "older_kid") == .olderKid)
        #expect(PlexRestriction(restricted: true, restrictionProfile: "teen") == .teen)
        #expect(PlexRestriction(restricted: false, restrictionProfile: "teen") == .unrestricted)
    }

    @Test func adminOverrideLowers() {
        #expect(RatingCeiling.effective(plex: .teen, adminOverride: .pg) == .pg)
        #expect(RatingCeiling.effective(plex: .unrestricted, adminOverride: .u) == .u)
    }

    @Test func adminOverrideNeverRaises() {
        #expect(RatingCeiling.effective(plex: .olderKid, adminOverride: .eighteen) == .pg)
        #expect(RatingCeiling.effective(plex: .littleKid, adminOverride: .twelveA) == .u)
    }

    @Test func noOverrideKeepsPlexCeiling() {
        #expect(RatingCeiling.effective(plex: .teen, adminOverride: nil) == .twelveA)
    }

    @Test func householdLowestIsTheLowest() {
        #expect(RatingCeiling.householdLowest([.eighteen, .pg, .twelveA]) == .pg)
        #expect(RatingCeiling.householdLowest([.fifteen]) == .fifteen)
    }

    @Test func ceilingOrdering() {
        #expect(RatingCeiling.u < .pg && RatingCeiling.pg < .twelveA)
        #expect(RatingCeiling.twelveA < .fifteen && RatingCeiling.fifteen < .eighteen)
    }
}
