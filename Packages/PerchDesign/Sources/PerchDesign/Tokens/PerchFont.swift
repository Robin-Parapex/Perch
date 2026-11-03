import SwiftUI

/// Type tokens (docs/DESIGN.md). Sizes are in points; kids scale up and nothing drops below `minimumSize`.
public enum PerchFont {
    public static let heroSize: CGFloat = 96
    public static let stepTitleSize: CGFloat = 64
    public static let sectionSize: CGFloat = 28
    public static let bodySize: CGFloat = 26
    public static let metadataSize: CGFloat = 22
    public static let badgeSize: CGFloat = 18
    public static let minimumSize: CGFloat = 17
    public static let kidsScale: CGFloat = 1.1

    public static func size(_ base: CGFloat, for style: PerchStyle) -> CGFloat {
        let scaled = style == .kids ? base * kidsScale : base
        return max(scaled.rounded(), minimumSize)
    }

    public static func hero(_ style: PerchStyle) -> Font {
        .system(size: size(heroSize, for: style), weight: .bold)
    }
    /// Wizard step titles and "Who's watching?".
    public static func stepTitle(_ style: PerchStyle) -> Font {
        .system(size: size(stepTitleSize, for: style), weight: .bold)
    }
    public static func section(_ style: PerchStyle) -> Font {
        .system(size: size(sectionSize, for: style), weight: .semibold)
    }
    public static func body(_ style: PerchStyle) -> Font {
        .system(size: size(bodySize, for: style))
    }
    public static func metadata(_ style: PerchStyle) -> Font {
        .system(size: size(metadataSize, for: style))
    }
    public static func badge(_ style: PerchStyle) -> Font {
        .system(size: size(badgeSize, for: style), weight: .semibold)
    }
}
