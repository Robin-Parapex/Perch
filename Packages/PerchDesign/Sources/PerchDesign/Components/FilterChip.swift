import SwiftUI

/// The label of a sort or filter control in a library header (WP-10): a title, the chosen value when there is
/// one, and a chevron when it opens a menu. Pair it with `.buttonStyle(.perchChip(active:))`.
public struct FilterChipLabel: View {
    @Environment(\.perchStyle) private var style
    private let title: String
    private let value: String?
    private let systemImage: String?
    private let showsChevron: Bool

    public init(_ title: String, value: String? = nil, systemImage: String? = nil, showsChevron: Bool = true) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.showsChevron = showsChevron
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 20, weight: .semibold)) }
            Text(value.map { "\(title): \($0)" } ?? title).lineLimit(1)
            if showsChevron { Image(systemName: "chevron.down").font(.system(size: 16, weight: .semibold)) }
        }
        .font(PerchFont.metadata(style).weight(.medium))
    }
}

/// A slim capsule for header chips: glass at rest, a quiet white outline when active (a filter is set), white
/// fill and dark text with the system lift when focused, like native tvOS buttons. Smaller than the 68 pt action
/// pills because a header holds several; still well over the focus target size.
public struct PerchChipButtonStyle: ButtonStyle {
    let active: Bool

    public init(active: Bool = false) { self.active = active }

    public func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, active: active)
    }

    private struct Styled: View {
        let configuration: Configuration
        let active: Bool
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? PerchColor.base : Color.white)
                .padding(.horizontal, 26)
                .frame(minHeight: 52)
                .background {
                    if isFocused {
                        Capsule().fill(Color.white)
                    } else {
                        Capsule().fill(Color.white.opacity(active ? 0.18 : 0)).glassEffect(.regular, in: Capsule())
                    }
                }
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(active && !isFocused ? 0.85 : 0), lineWidth: 1)
                }
                .scaleEffect(isFocused && !reduceMotion ? PerchSize.focusScale : 1)
                .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 14, y: 6)
                .animation(PerchMotion.spring, value: isFocused)
                .animation(.easeInOut(duration: PerchMotion.crossfadeDuration), value: active)
        }
    }
}

extension ButtonStyle where Self == PerchChipButtonStyle {
    /// Header chip; `active` marks a set filter.
    public static func perchChip(active: Bool = false) -> PerchChipButtonStyle { PerchChipButtonStyle(active: active) }
}
