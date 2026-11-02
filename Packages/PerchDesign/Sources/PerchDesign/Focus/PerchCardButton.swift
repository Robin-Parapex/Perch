import SwiftUI

/// A poster or landscape card: only the artwork lifts and rings; the caption stays still.
/// Approach after the tvOS TV app highlight style; see docs/notes/reference-review.md
public struct PerchCardButton<Artwork: View, Caption: View>: View {
    @Environment(\.perchStyle) private var style
    private let action: () -> Void
    private let artwork: Artwork
    private let caption: Caption

    public init(
        action: @escaping () -> Void,
        @ViewBuilder artwork: () -> Artwork,
        @ViewBuilder caption: () -> Caption
    ) {
        self.action = action
        self.artwork = artwork()
        self.caption = caption()
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                FocusAwareArtwork(radius: PerchRadius.card(for: style)) { artwork }
                caption
            }
        }
        .buttonStyle(.borderless)
    }
}

private struct FocusAwareArtwork<Content: View>: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.perchFocusReporter) private var reporter
    let radius: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .perchFocusRing(isFocused: isFocused, radius: radius)
            .hoverEffect(.highlight)
            .onChange(of: isFocused) { _, focused in reporter?(focused) }
            // A focused card that is removed never reports false otherwise.
            .onDisappear { if isFocused { reporter?(false) } }
    }
}
