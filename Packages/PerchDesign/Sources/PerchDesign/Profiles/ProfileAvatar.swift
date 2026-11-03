import SwiftUI

/// The round picture alone: optional image, else white initials on a per-name tint, with an optional lock mark.
/// `isCurrent` is accepted for compatibility; "Watching now" is a caption under the name, not a mark on the picture.
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

    /// Muted fills for the initials fallback, dark enough for white text.
    nonisolated static let tintPalette: [(red: Double, green: Double, blue: Double)] = [
        (0.36, 0.40, 0.62), (0.30, 0.50, 0.55), (0.55, 0.38, 0.52), (0.60, 0.42, 0.32),
        (0.34, 0.52, 0.40), (0.52, 0.36, 0.40), (0.42, 0.44, 0.56), (0.50, 0.48, 0.30),
    ]

    /// Stable palette position for a name (FNV-1a over the lowercased text, so it survives relaunches).
    nonisolated public static func tintIndex(for name: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in name.trimmingCharacters(in: .whitespaces).lowercased().utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return Int(hash % UInt64(tintPalette.count))
    }

    /// The fallback fill for a name.
    public static func tint(for name: String) -> Color {
        let c = tintPalette[tintIndex(for: name)]
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    public var body: some View {
        ZStack {
            Circle().fill(Self.tint(for: name))
            if let image {
                image.scaledToFill().frame(width: size, height: size).clipped()
            } else {
                Text(Self.initials(for: name))
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(PerchColor.textPrimary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            if isLocked { badge("lock.fill") }
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

/// A "Who's watching?" profile: round avatar with the name beneath. Focus adds a white ring, a shadow and scale 1.1; unfocused avatars dim. `isCurrent` adds a "Watching now" caption.
public struct ProfileAvatar: View {
    private let name: String
    private let size: CGFloat
    private let image: AnyView?
    private let isLocked: Bool
    private let isCurrent: Bool
    private let action: () -> Void
    @Environment(\.perchStyle) private var style

    /// Button for one profile; `isLocked` adds a lock glyph (protected profiles only, the same for every viewer), `isCurrent` adds a "Watching now" caption.
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
                Text(isCurrent ? "Watching now" : " ")
                    .font(PerchFont.metadata(style))
                    .foregroundStyle(PerchColor.textSecondary)
                    .opacity(isCurrent ? 1 : 0)
                    .padding(.top, -14)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(ProfileAvatarButtonStyle(avatarSize: size))
        .accessibilityLabel(accessibilityName)
    }

    private var accessibilityName: String {
        [name, isLocked ? "needs a PIN" : nil, isCurrent ? "current profile" : nil].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Focus look for an avatar: 3 pt white ring, shadow and scale 1.1; unfocused avatars dim to 70%.
/// (Ring-and-dim focus idea from Swiftfin's user and profile tiles; the code is our own.)
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
                .foregroundStyle(isFocused ? PerchColor.textPrimary : PerchColor.textBody)
                .overlay(alignment: .top) {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 3)
                        .frame(width: avatarSize + 14, height: avatarSize + 14)
                        .offset(y: -7)
                        .opacity(isFocused ? 1 : 0)
                }
                .opacity(isFocused ? 1 : 0.7)
                .scaleEffect(isFocused && scale ? (configuration.isPressed ? 1.06 : 1.1) : 1)
                .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 24, y: 14)
                .animation(PerchMotion.spring, value: isFocused)
                .animation(PerchMotion.spring, value: configuration.isPressed)
        }
    }
}
