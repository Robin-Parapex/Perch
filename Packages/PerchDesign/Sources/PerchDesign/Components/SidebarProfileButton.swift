import SwiftUI

/// The profile avatar and name at the top of the sidebar (DESIGN: "profile avatar at the top"); selecting it opens
/// the profile picker. Glass at rest, a white pill with the system lift when focused. Kids get a larger avatar
/// and the kids type scale. Was WP-09's top-right ProfileMenuButton; moved into the sidebar in WP-13.
public struct SidebarProfileButton<Avatar: View>: View {
    @Environment(\.perchStyle) private var style

    public static func avatarSize(_ style: PerchStyle) -> CGFloat { style == .kids ? 56 : 48 }

    private let name: String
    private let nameIdentifier: String?
    private let action: () -> Void
    private let avatar: Avatar

    /// `nameIdentifier` labels the name for UI tests (the app passes its own id; the package names none).
    public init(name: String, nameIdentifier: String? = nil, action: @escaping () -> Void, @ViewBuilder avatar: () -> Avatar) {
        self.name = name
        self.nameIdentifier = nameIdentifier
        self.action = action
        self.avatar = avatar()
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                avatar
                    .frame(width: Self.avatarSize(style), height: Self.avatarSize(style))
                    .clipShape(Circle())
                Text(name)
                    .font(PerchFont.metadata(style).weight(.semibold))
                    .lineLimit(1)
                    .accessibilityIdentifier(nameIdentifier ?? "")
            }
            .padding(.leading, 10)
            .padding(.trailing, 24)
        }
        .buttonStyle(SidebarProfileButtonStyle())
    }
}

private struct SidebarProfileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Focused(configuration: configuration)
    }

    private struct Focused: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? PerchColor.base : Color.white)
                .frame(minHeight: PerchSize.buttonMinHeight)
                .background {
                    if isFocused {
                        Capsule().fill(Color.white)
                    } else {
                        Capsule().fill(Color.clear).glassEffect(.regular, in: Capsule())
                    }
                }
                .scaleEffect(isFocused && !reduceMotion ? PerchSize.focusScale : 1)
                .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 16, y: 8)
                .animation(PerchMotion.spring, value: isFocused)
        }
    }
}

#Preview {
    SidebarProfileButton(name: "Sam", action: {}) { Color.indigo }
        .perchPageBackground()
}
