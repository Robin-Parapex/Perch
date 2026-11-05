import SwiftUI
import Testing

@testable import PerchDesign

/// Expectations come from docs/design/wp-09-home.md 3.1, not from the implementation.
struct HeroMetricsTests {
    @Test func synopsisReservesTwoBodyLines() {
        #expect(HeroMetrics.synopsisHeight == 68)
        #expect(HeroMetrics.contentBottomInset == 72)
    }

    @Test func synopsisRowCollapsesWhenEmpty() {
        #expect(HeroMetrics.reservedSynopsisHeight(for: "") == nil)
        #expect(HeroMetrics.reservedSynopsisHeight(for: "A story.") == 68)
    }

    @Test func synopsisReservationFollowsKidsFontScale() {
        // Kids body is 26 * 1.1 = 28.6, rounded to 29 pt: 68 * 29 / 26 = 75.8, rounded up.
        #expect(HeroMetrics.reservedSynopsisHeight(for: "A story.", style: .standard) == 68)
        #expect(HeroMetrics.reservedSynopsisHeight(for: "A story.", style: .kids) == 76)
        #expect(HeroMetrics.reservedSynopsisHeight(for: "", style: .kids) == nil)
    }

    @Test func bottomScrimStopsFollowTheSpec() {
        let stops = HeroMetrics.bottomScrimStops(height: 864)
        #expect(stops.count == 3)
        #expect(stops[0].location == 0.44)
        #expect(abs(stops[1].location - (864 - 36) / 864) < 0.0001)
        #expect(stops[2].location == 1)
        #expect(stops.map(\.location) == stops.map(\.location).sorted())
    }

    @Test func scrimStopsStaySortedForTinyHeights() {
        let locations = HeroMetrics.bottomScrimStops(height: 10).map(\.location)
        #expect(locations == locations.sorted())
    }
}
