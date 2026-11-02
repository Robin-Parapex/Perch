import SwiftUI

/// The round picture alone: optional image, else initials on a muted fill, with optional lock and "current" marks.
public struct ProfileAvatarImage: View {
    private let name: String
    private let size: CGFloat
    private let image: AnyView?
    private let isLocked: Bool
    private let isCurrent: Bool

    /// Pass any view as `image` (it is filled and clipped to the circle); nil shows initials.
    public init(name: String, size: CGFloat = 200, image: (any View)? = nil, isLocked: Bool = false, isCurrent: Bool = false) {
        self.name = name
        self.size = size
        self.image = image.map { AnyView($0) }
        self.isLocked = isLocked
        self.isCurrent = isCurrent
    }

    /// Up to two capital letters from the name ("Sam Brown" gives "SB", "mum" gives "M"), "?" when empty.
    nonisolated public static func initials(for name: String) -> String {
        let letters = name.split(whereSeparator: { $0.isWhitespace }).prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    public var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.16))
            if let image {
                image.scaledToFill().frame(width: size, height: size).clipped()
            } else {
                Text(Self.initials(for: name))
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(PerchColor.textBody)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            if isLocked { badge("lock.fill") }
        }
        .overlay(alignment: .topTrailing) {
            if isCurrent { badge("checkmark") }
        }
        .accessibilityHidden(true)
    }

    private func badge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.16, weight: .semibold))
            .foregroundStyle(PerchColor.textPrimary)
            .frame(width: size * 0.3, height: size * 0.3)
            .background(Circle().fill(.regularMaterial))
    }
}

/// A "Who's watching?" profile: round avatar with the name beneath. Focus scales it up with a soft glow, no ring.
public struct ProfileAvatar: View {
    private let name: String
    private let size: CGFloat
    private let image: AnyView?
    private let isLocked: Bool
    private let isCurrent: Bool
    private let action: () -> Void
    @Environment(\.perchStyle) private var style

    /// Button for one profile; `isLocked` adds a lock badge, `isCurrent` marks who is signed in now.
    public init(
        name: String, size: CGFloat = 200, image: (any View)? = nil,
        isLocked: Bool = false, isCurrent: Bool = false, action: @escaping () -> Void
    ) {
        self.name = name
        self.size = size
        self.image = image.map { AnyView($0) }
        self.isLocked = isLocked
        self.isCurrent = isCurrent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 20) {
                ProfileAvatarImage(name: name, size: size, image: image, isLocked: isLocked, isCurrent: isCurrent)
                Text(name)
                    .font(PerchFont.body(style))
                    .lineLimit(1)
                    .frame(width: size + 40)
            }
        }
        .buttonStyle(ProfileAvatarButtonStyle(avatarSize: size))
        .accessibilityLabel(accessibilityName)
    }

    private var accessibilityName: String {
        [name, isLocked ? "needs a PIN" : nil, isCurrent ? "current profile" : nil].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Focus look for an avatar: scale 1.1 and a soft white glow behind the picture; the name brightens.
private struct ProfileAvatarButtonStyle: ButtonStyle {
    let avatarSize: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        AvatarBody(configuration: configuration, avatarSize: avatarSize)
    }

    private struct AvatarBody: View {
        let configuration: Configuration
        let avatarSize: CGFloat
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let scale = PerchMotion.resolve(.scale(from: 1.1), reduceMotion: reduceMotion) == .scale(from: 1.1)
            configuration.label
                .foregroundStyle(isFocused ? PerchColor.textPrimary : PerchColor.textSecondary)
                .background {
                    // Glow: a blurred disc behind the picture (soft light, not a ring or a gradient).
                    Circle()
                        .fill(Color.white.opacity(isFocused ? 0.5 : 0))
                        .frame(width: avatarSize, height: avatarSize)
                        .blur(radius: 44)
                        .offset(y: -22)
                }
                .scaleEffect(isFocused && scale ? (configuration.isPressed ? 1.06 : 1.1) : 1)
                .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 20, y: 12)
                .animation(PerchMotion.spring, value: isFocused)
                .animation(PerchMotion.spring, value: configuration.isPressed)
        }
    }
}
