import CoreGraphics
import SwiftUI

/// Blurred stand-in for artwork that is still loading, or a quiet tinted gradient when there is none.
/// No animation inside; the caller crossfades between this and the real image.
public struct ArtworkPlaceholder: View {
    private let image: CGImage?
    private let tint: ArtworkRGB?

    public init(image: CGImage?, tint: ArtworkRGB?) {
        self.image = image
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            PerchColor.base
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(1.08)
                    .blur(radius: 18)
            } else {
                // A calm vertical wash, no hot-spot: the tint slightly desaturated at about 55% luminance,
                // faint over the base (WP-08 design review).
                let wash = Self.wash(tint ?? ArtworkTint.neutral)
                LinearGradient(
                    colors: [wash.color.opacity(0.16), wash.color.opacity(0.07)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .clipped()
    }

    /// The tint moved 35% towards grey, then scaled to a relative luminance of 0.55 (capped per channel).
    static func wash(_ rgb: ArtworkRGB) -> ArtworkRGB {
        func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
        let grey = luminance(rgb.red, rgb.green, rgb.blue)
        let r = rgb.red + (grey - rgb.red) * 0.35
        let g = rgb.green + (grey - rgb.green) * 0.35
        let b = rgb.blue + (grey - rgb.blue) * 0.35
        let current = luminance(r, g, b)
        guard current > 0.01 else { return ArtworkRGB(red: 0.55, green: 0.55, blue: 0.55) }
        let k = 0.55 / current
        return ArtworkRGB(red: min(1, r * k), green: min(1, g * k), blue: min(1, b * k))
    }
}
