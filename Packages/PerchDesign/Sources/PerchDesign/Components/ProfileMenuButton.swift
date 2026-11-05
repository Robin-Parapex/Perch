import SwiftUI

/// Translucent pill with the profile avatar and name; the Home entry point for switching profile until Settings exists.
public struct ProfileMenuButton<Avatar: View>: View {
    @Environment(\.perchStyle) private var style

    static var avatarSize: CGFloat { 44 }

    private let name: String
    private let action: () -> Void
    private let avatar: Avatar

    public init(name: String, action: @escaping () -> Void, @ViewBuilder avatar: () -> Avatar) {
        self.name = name
        self.action = action
        self.avatar = avatar()
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                avatar
                    .frame(width: Self.avatarSize, height: Self.avatarSize)
                    .clipShape(Circle())
                Text(name)
                    .font(PerchFont.metadata(style))
                    .lineLimit(1)
                    .accessibilityIdentifier("home.profileName")
            }
            .padding(.leading, 12)
            .padding(.trailing, 24)
        }
        .buttonStyle(ProfileMenuButtonStyle())
    }
}

private struct ProfileMenuButtonStyle: ButtonStyle {
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
    ProfileMenuButton(name: "Sam", action: {}) { Color.indigo }
        .perchPageBackground()
}
