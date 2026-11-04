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
                LinearGradient(
                    colors: [(tint ?? ArtworkTint.neutral).color.opacity(0.28), PerchColor.base],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipped()
    }
}
