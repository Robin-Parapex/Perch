import CoreGraphics
import Testing

@testable import PerchDesign

/// Expectations are written from docs/DESIGN.md, not from the implementation.
struct TokenTests {
    @Test func spacing() {
        // docs/DESIGN.md:11
        #expect(PerchSpacing.horizontalMargin == 80)
        #expect(PerchSpacing.topMargin == 60)
        #expect(PerchSpacing.rowGap == 36)
        #expect(PerchSpacing.itemGap == 24)
    }

    @Test func sizes() {
        // docs/DESIGN.md:11
        #expect(PerchSize.posterRow.width == 180 && PerchSize.posterRow.height == 270)
        #expect(PerchSize.posterGrid.width == 240 && PerchSize.posterGrid.height == 360)
        #expect(PerchSize.landscape.width == 336 && PerchSize.landscape.height == 190)
        // docs/DESIGN.md:13
        #expect(PerchSize.buttonMinHeight == 68)
        // docs/DESIGN.md:49
        #expect(PerchSize.sidePanelWidth == 760)
        // docs/DESIGN.md:51
        #expect(PerchSize.askBarWidth == 1200)
        // docs/DESIGN.md:17
        #expect((1.05...1.08).contains(Double(PerchSize.focusScale)))
    }

    @Test func aspectRatios() {
        // docs/DESIGN.md:11 (posters 2:3, landscape 16:9)
        for s in [PerchSize.posterRow, PerchSize.posterGrid] {
            #expect(abs(Double(s.width / s.height) - 2.0 / 3.0) < 0.01)
        }
        #expect(abs(Double(PerchSize.landscape.width / PerchSize.landscape.height) - 16.0 / 9.0) < 0.01)
    }

    @Test func radius() {
        // docs/DESIGN.md:39
        #expect(PerchRadius.card(for: .standard) == 12)
        #expect(PerchRadius.card(for: .kids) == 16)
    }

    @Test func fontSizes() {
        // docs/DESIGN.md:9
        #expect(PerchFont.heroSize == 96)
        #expect(PerchFont.bodySize == 26)
        #expect(PerchFont.metadataSize == 22)
        #expect(PerchFont.badgeSize == 18)
        #expect(PerchFont.minimumSize == 17)
        #expect((26.0...30.0).contains(Double(PerchFont.sectionSize)))
    }

    @Test func fontSizeFloorAndKids() {
        // docs/DESIGN.md:9 (nothing under 17 pt), :39 (kids larger type)
        for base in [1, 10, 17, 18, 22, 26, 30, 96] as [Double] {
            let std = Double(PerchFont.size(CGFloat(base), for: .standard))
            let kids = Double(PerchFont.size(CGFloat(base), for: .kids))
            #expect(std >= 17)
            #expect(kids >= 17)
            #expect(kids >= std)
        }
    }

    @Test func pageTint() {
        // docs/DESIGN.md:38
        #expect((0.08...0.12).contains(Double(PerchColor.pageTintOpacity)))
    }
}
