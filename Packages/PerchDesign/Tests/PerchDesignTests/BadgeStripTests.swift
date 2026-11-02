import Testing

@testable import PerchCore
@testable import PerchDesign

/// Expectations are written from docs/DESIGN.md:12 ("Keep to three badges per card").
struct BadgeStripTests {
    private func names(_ kinds: [Pill.Kind]) -> [String] { kinds.map { String(describing: $0) } }

    static let five: [Pill.Kind] = [
        .format("4K"), .format("Atmos"), .new, .format("HDR10+"), .availability(.readyToWatch, kids: false),
    ]

    @Test func maxIsThree() {
        #expect(BadgeStrip.maxBadges == 3)
    }

    @Test func fiveShowsFirstThreeInOrder() {
        let shown = BadgeStrip.visible(Self.five)
        #expect(names(shown) == names(Array(Self.five.prefix(3))))
    }

    @Test func twoShowsBoth() {
        let two: [Pill.Kind] = [.format("4K"), .new]
        #expect(names(BadgeStrip.visible(two)) == names(two))
    }

    @Test func emptyIsEmpty() {
        #expect(BadgeStrip.visible([]).isEmpty)
    }
}
