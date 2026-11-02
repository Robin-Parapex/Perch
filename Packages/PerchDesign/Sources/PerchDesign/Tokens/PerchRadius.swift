import CoreGraphics

/// Corner radius tokens (docs/DESIGN.md).
public enum PerchRadius {
    public static func card(for style: PerchStyle) -> CGFloat {
        style == .kids ? 16 : 12
    }
}
