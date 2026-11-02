import CoreGraphics

/// Fixed sizes (docs/DESIGN.md).
public enum PerchSize {
    public static let posterRow = CGSize(width: 180, height: 270)
    public static let posterGrid = CGSize(width: 240, height: 360)
    public static let landscape = CGSize(width: 336, height: 190)
    public static let buttonMinHeight: CGFloat = 68
    public static let focusRingWidth: CGFloat = 3
    public static let sidePanelWidth: CGFloat = 760
    public static let askBarWidth: CGFloat = 1200
    public static let focusScale: CGFloat = 1.06
}
