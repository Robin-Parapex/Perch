import SwiftUI

/// The alphabetical jump on a library grid's trailing edge (WP-10): one small focusable letter per bucket, "#"
/// first. The rail is its own focus section, so Right from the grid's last column reaches it and Left goes back
/// (focus sections beside a grid, after Swiftfin's letter picker; reimplemented). Letters with nothing in them are
/// not passed in. `current` marks the letter the grid is showing.
public struct LetterRail: View {
    @Environment(\.perchStyle) private var style
    private let letters: [String]
    private let current: String?
    private let identifierPrefix: String
    private let onSelect: (String) -> Void

    public init(
        letters: [String], current: String? = nil, identifierPrefix: String = "letterRail",
        onSelect: @escaping (String) -> Void
    ) {
        self.letters = letters
        self.current = current
        self.identifierPrefix = identifierPrefix
        self.onSelect = onSelect
    }

    /// Row height shrinks so 27 letters always fit 920 pt of screen.
    private var rowHeight: CGFloat { min(40, 920 / CGFloat(max(letters.count, 1))) }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(letters, id: \.self) { letter in
                Button { onSelect(letter) } label: {
                    Text(letter)
                }
                .buttonStyle(LetterButtonStyle(isCurrent: letter == current, height: rowHeight, style: style))
                .accessibilityIdentifier("\(identifierPrefix).\(letter)")
                .accessibilityLabel(letter == "#" ? "Numbers" : letter)
            }
        }
        .padding(.vertical, 12)
        .frame(width: 56)
        .glassEffect(.regular, in: Capsule())
        .focusSection()
    }
}

private struct LetterButtonStyle: ButtonStyle {
    let isCurrent: Bool
    let height: CGFloat
    let style: PerchStyle

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, isCurrent: isCurrent, height: height, style: style)
    }

    private struct Styled: View {
        let configuration: Configuration
        let isCurrent: Bool
        let height: CGFloat
        let style: PerchStyle
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.system(size: PerchFont.size(PerchFont.minimumSize + 3, for: style), weight: isFocused || isCurrent ? .bold : .medium))
                .foregroundStyle(isFocused ? PerchColor.base : (isCurrent ? PerchColor.textPrimary : PerchColor.textSecondary))
                .frame(width: 44, height: height)
                .background {
                    Circle().fill(Color.white).frame(width: 40, height: 40).opacity(isFocused ? 1 : 0)
                }
                .scaleEffect(isFocused && !reduceMotion ? 1.15 : 1)
                .animation(PerchMotion.spring, value: isFocused)
        }
    }
}
