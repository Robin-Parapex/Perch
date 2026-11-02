import SwiftUI

/// Motion tokens (docs/DESIGN.md) and the Reduce Motion substitution rule.
public enum PerchMotion {
    public static let spring = Animation.spring(response: 0.45, dampingFraction: 0.85)
    public static let crossfadeDuration: Double = 0.3
    public static let heroBackdropFade: Double = 0.5
    public static let heroLogoDelay: Double = 0.1
    public static let heroLogoDuration: Double = 0.4
    public static let heroLogoStartScale: CGFloat = 0.96
    public static let heroTextDelay: Double = 0.2
    public static let heroTextOffset: CGFloat = 12
    public static let kenBurnsDuration: Double = 20
    public static let kenBurnsAmount: CGFloat = 0.04
    public static let rowLift: CGFloat = 4
    public static let rowDimOpacity: Double = 0.9
    public static let panelDuration: Double = 0.35
    public static let panelOffset: CGFloat = 24
    public static let trailerFocusDelay: Double = 4
    public static let trailerCrossfade: Double = 0.8

    public enum Effect: Sendable, Hashable {
        case scale(from: CGFloat)
        case slide(offset: CGFloat)
        case kenBurns(amount: CGFloat)
        case lift(points: CGFloat)
        case dim(opacity: Double)
        case fade
        case none
    }

    /// With Reduce Motion, movement becomes a fade or nothing; everything else is unchanged.
    public static func resolve(_ effect: Effect, reduceMotion: Bool) -> Effect {
        guard reduceMotion else { return effect }
        switch effect {
        case .scale, .slide: return .fade
        case .kenBurns, .lift: return .none
        case .dim, .fade, .none: return effect
        }
    }
}
