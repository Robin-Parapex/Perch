import SwiftUI

/// A centred message that takes the hero's place: empty library, server unreachable.
/// Same height as `HeroCard`, no indicator, no artwork.
public struct HeroMessage: View {
    public struct Action {
        public let label: String
        public let identifier: String?
        public let run: () -> Void

        public init(_ label: String, identifier: String? = nil, run: @escaping () -> Void) {
            self.label = label
            self.identifier = identifier
            self.run = run
        }
    }

    @Environment(\.perchStyle) private var style

    private let title: String
    private let message: String
    private let primary: Action?
    private let secondary: Action?
    private let heightFraction: CGFloat

    public init(
        title: String,
        message: String,
        primary: Action? = nil,
        secondary: Action? = nil,
        heightFraction: CGFloat = 0.8
    ) {
        self.title = title
        self.message = message
        self.primary = primary
        self.secondary = secondary
        self.heightFraction = heightFraction
    }

    public var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(PerchFont.stepTitle(style))
                .foregroundStyle(PerchColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(PerchFont.body(style))
                .foregroundStyle(PerchColor.textHelper)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if primary != nil || secondary != nil {
                HStack(spacing: 24) {
                    if let primary {
                        button(primary).buttonStyle(.perchPrimary)
                    }
                    if let secondary {
                        button(secondary).buttonStyle(.perchSecondary)
                    }
                }
                .focusSection()
                .padding(.top, 20)
            }
        }
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .containerRelativeFrame(.horizontal)
        .containerRelativeFrame(.vertical) { height, _ in height * heightFraction }
    }

    @ViewBuilder
    private func button(_ action: Action) -> some View {
        let base = Button(action: action.run) {
            Text(action.label)
                .font(PerchFont.body(style).weight(.semibold))
                .frame(minHeight: PerchSize.buttonMinHeight)
        }
        if let id = action.identifier {
            base.accessibilityIdentifier(id)
        } else {
            base
        }
    }
}

#Preview {
    HeroMessage(
        title: "Nothing to watch yet",
        message: "Films and series you add to your media server will show up here.",
        secondary: .init("Check again") {}
    )
    .perchPageBackground()
}
