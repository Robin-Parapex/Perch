import Testing

@testable import PerchDesign

/// Expectations are written from docs/DESIGN.md, not from the implementation.
struct MotionTests {
    static let effects: [PerchMotion.Effect] = [
        .scale(from: 0.96), .slide(offset: 12), .kenBurns(amount: 0.04), .lift(points: 4),
        .dim(opacity: 0.9), .fade, .none,
    ]

    private func d(_ e: PerchMotion.Effect) -> String { String(describing: e) }

    @Test func motionOnReturnsInputUnchanged() {
        for e in Self.effects {
            #expect(d(PerchMotion.resolve(e, reduceMotion: false)) == d(e))
        }
    }

    @Test func reduceMotionMapsMovementToFadeOrNone() {
        // Reduce Motion is a tvOS accessibility setting; docs/DESIGN.md:26,29,31 name the moving effects
        #expect(d(PerchMotion.resolve(.scale(from: 0.96), reduceMotion: true)) == d(.fade))
        #expect(d(PerchMotion.resolve(.slide(offset: 24), reduceMotion: true)) == d(.fade))
        #expect(d(PerchMotion.resolve(.kenBurns(amount: 0.04), reduceMotion: true)) == d(.none))
        #expect(d(PerchMotion.resolve(.lift(points: 4), reduceMotion: true)) == d(.none))
        #expect(d(PerchMotion.resolve(.dim(opacity: 0.9), reduceMotion: true)) == d(.dim(opacity: 0.9)))
        #expect(d(PerchMotion.resolve(.fade, reduceMotion: true)) == d(.fade))
        #expect(d(PerchMotion.resolve(.none, reduceMotion: true)) == d(.none))
    }

    @Test func constants() {
        // docs/DESIGN.md:25
        #expect(PerchMotion.crossfadeDuration == 0.3)
        // docs/DESIGN.md:31
        #expect(PerchMotion.panelDuration == 0.35)
        #expect(PerchMotion.panelOffset == 24)
        // docs/DESIGN.md:29
        #expect(PerchMotion.rowLift == 4)
        #expect(PerchMotion.rowDimOpacity == 0.9)
        // docs/DESIGN.md:26
        #expect(PerchMotion.kenBurnsAmount == 0.04)
        #expect(PerchMotion.kenBurnsDuration == 20)
    }
}
