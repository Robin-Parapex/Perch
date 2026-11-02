import SwiftUI

/// Colour tokens (docs/DESIGN.md).
public enum PerchColor {
    public static let base = Color(red: 11 / 255, green: 11 / 255, blue: 15 / 255)
    public static let textPrimary = Color.white
    public static let textBody = Color.white.opacity(0.85)
    public static let textSecondary = Color.white.opacity(0.60)
    public static let pageTintOpacity: Double = 0.10
}
