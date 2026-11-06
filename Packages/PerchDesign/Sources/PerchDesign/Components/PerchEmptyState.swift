import SwiftUI

/// A quiet page for a screen with nothing on it yet: one large SF Symbol, a sentence-case title and a short line at
/// HeroMessage's scale (64/26 pt), centred in the page, fading up once. No buttons, no spinner, no jargon. Used by the Films, Series and Search
/// tabs until their work packages fill them.
public struct PerchEmptyState: View {
    @Environment(\.perchStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private let systemImage: String
    private let title: String
    private let message: String?

    public init(systemImage: String, title: String, message: String? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 28) {
            Image(systemName: systemImage)
                .font(.system(size: style == .kids ? 104 : 92, weight: .light))
                .foregroundStyle(PerchColor.textSecondary)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            VStack(spacing: 20) {
                Text(title)
                    .font(PerchFont.stepTitle(style))
                    .foregroundStyle(PerchColor.textPrimary)
                if let message {
                    Text(message)
                        .font(PerchFont.body(style))
                        .foregroundStyle(PerchColor.textHelper)
                        .frame(maxWidth: 900)
                }
            }
            .multilineTextAlignment(.center)
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : PerchMotion.heroTextOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.easeOut(duration: PerchMotion.crossfadeDuration)) { shown = true }
        }
    }
}

#Preview {
    PerchEmptyState(systemImage: "film", title: "Films", message: "Browse your films here soon.")
        .perchPageBackground()
}
