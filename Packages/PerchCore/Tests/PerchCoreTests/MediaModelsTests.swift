import Foundation
import Testing

@testable import PerchCore

private func item(_ id: String, certificate: String? = nil, duration: Int? = nil, offset: Int? = nil, views: Int = 0)
    -> MediaSummary
{
    MediaSummary(
        id: id, kind: .film, title: id, certificate: certificate, durationMs: duration,
        viewOffsetMs: offset, viewCount: views)
}

struct MediaSummaryTests {
    @Test func remainingTimeFromDurationAndOffset() {
        let film = item("a", duration: 6_000_000, offset: 4_140_000)
        #expect(film.remainingMs == 1_860_000)
        #expect(film.progress == 0.69)
        #expect(film.isInProgress)
        #expect(!film.isWatched)
    }

    @Test func missingOrShortDurationGivesNoRemainingTime() {
        #expect(item("a", duration: nil, offset: 10).remainingMs == nil)
        #expect(item("a", duration: 0, offset: 0).remainingMs == nil)
        #expect(item("a", duration: 1_000, offset: 5_000).remainingMs == nil)
        #expect(item("a", duration: 1_000, offset: 5_000).progress == nil)
    }

    @Test func watchedNeedsAViewAndNoOffset() {
        #expect(item("a", views: 1).isWatched)
        #expect(!item("a", offset: 5, views: 1).isWatched)
        #expect(!item("a").isWatched)
    }

    @Test func snapshotRoundTrips() throws {
        let row = MediaRow(id: "r", title: "Continue watching", items: [item("a", certificate: "PG", duration: 9, offset: 3)])
        let data = try JSONEncoder().encode(row)
        #expect(try JSONDecoder().decode(MediaRow.self, from: data) == row)
    }
}

struct MediaDetailTests {
    private func detail(_ markers: [MediaMarker]) -> MediaDetail {
        MediaDetail(summary: item("a"), markers: markers)
    }

    @Test func finalCreditsWinOverMidFilmCredits() {
        let d = detail([
            MediaMarker(kind: .credits, startMs: 100, endMs: 200),
            MediaMarker(kind: .credits, startMs: 900, endMs: 1_000, isFinal: true),
            MediaMarker(kind: .intro, startMs: 10, endMs: 40),
        ])
        #expect(d.creditsMarker?.startMs == 900)
        #expect(d.introMarker?.startMs == 10)
    }

    @Test func withoutFinalFlagTheLastCreditsWin() {
        let d = detail([
            MediaMarker(kind: .credits, startMs: 900, endMs: 1_000),
            MediaMarker(kind: .credits, startMs: 100, endMs: 200),
        ])
        #expect(d.creditsMarker?.startMs == 900)
        #expect(detail([]).creditsMarker == nil)
    }
}

struct RowContextTests {
    private let row = MediaRow(id: "r", title: "Recently added", items: [
        item("u", certificate: "U"), item("pg", certificate: "TV-PG"), item("15", certificate: "15"),
        item("none"), item("nr", certificate: "NR"),
    ])

    @Test func serviceAlreadyFiltersSoNothingIsDroppedAtItsCeiling() {
        let context = RowContext(profileID: "kid", serviceCeiling: .pg, ceiling: .pg)
        #expect(context.admit(row).items.map(\.id) == ["u", "pg", "15", "none", "nr"])
    }

    @Test func aLoweredCeilingDropsTitlesAboveItAndUnknownOnes() {
        let context = RowContext(profileID: "kid", serviceCeiling: .eighteen, ceiling: .pg)
        #expect(context.admit(row).items.map(\.id) == ["u", "pg"])
    }

    @Test @MainActor func theRegistryAppliesTheCeilingToEveryRow() async throws {
        struct Fixed: RowProvider {
            let row: MediaRow
            var id: String { row.id }
            var title: String { row.title }
            let placement = RowPlacement.home(order: 0)
            func cachedRow(in context: RowContext) -> MediaRow? { row }
            func refreshRow(in context: RowContext) async throws -> MediaRow { row }
        }
        let provider = Fixed(row: row)
        let context = RowContext(profileID: "kid", serviceCeiling: .eighteen, ceiling: .u)
        #expect(ModuleRegistry.cachedRow(provider, in: context)?.items.map(\.id) == ["u"])
        #expect(try await ModuleRegistry.refreshRow(provider, in: context).items.map(\.id) == ["u"])
    }
}

struct TVRatingTests {
    @Test(arguments: [
        ("TV-Y", RatingCeiling.u), ("TV-Y7", .u), ("TV-G", .u), ("TV-PG", .pg),
        ("TV-14", .fifteen), ("TV-MA", .eighteen), ("us/TV-14", .fifteen),
    ])
    func titleRatingsRoundUp(_ certificate: String, _ expected: RatingCeiling) {
        #expect(RatingCeiling.forTitle(certificate: certificate) == expected)
    }

    @Test func notRatedCountsAsFifteen() {
        #expect(RatingCeiling(certificate: "NR") == nil)
        #expect(RatingCeiling.forTitle(certificate: "NR") == .fifteen)
    }

    @Test func allowedListsRoundTV14Down() {
        #expect(RatingCeiling(plex: .custom(allowedRatings: ["TV-14"])) == .twelveA)
        #expect(RatingCeiling(plex: .custom(allowedRatings: ["TV-PG", "TV-Y"])) == .pg)
        #expect(RatingCeiling(plex: .custom(allowedRatings: ["TV-MA"])) == .eighteen)
    }
}
