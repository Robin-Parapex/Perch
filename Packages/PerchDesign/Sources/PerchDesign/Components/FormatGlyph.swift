import SwiftUI

/// A small rounded-rect format mark ("4K", "Dolby Vision", "HDR10") that sits inline at the end of a facts line
/// (WP-11), as the Apple TV app sets them: outlined, the line's colour, a touch smaller than the text.
public struct FormatGlyph: View {
    @Environment(\.perchStyle) private var style
    private let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(.system(size: PerchFont.size(15, for: style), weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(lineWidth: 1.5))
            .fixedSize()
    }
}

/// A facts line with its format marks inline at the end: "2024 · 12A · 1 h 52 min · Drama  [4K] [Dolby Vision]".
public struct FactsLine: View {
    @Environment(\.perchStyle) private var style
    private let text: String
    private let formats: [String]
    private let textIdentifier: String?

    public init(_ text: String, formats: [String], textIdentifier: String? = nil) {
        self.text = text
        self.formats = formats
        self.textIdentifier = textIdentifier
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if !text.isEmpty {
                Text(text)
                    .font(PerchFont.metadata(style).weight(.medium))
                    .lineLimit(1)
                    .accessibilityIdentifier(textIdentifier ?? "")
            }
            ForEach(Array(BadgeStrip.visible(formats.map { Pill.Kind.format($0) }).enumerated()), id: \.offset) { _, kind in
                if case .format(let name) = kind { FormatGlyph(name) }
            }
        }
        .foregroundStyle(Color.white.opacity(0.7))
    }
}
