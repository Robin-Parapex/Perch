import SwiftUI

/// A compact glass circle for a secondary action beside the white primary pill (WP-11), as the Apple TV app's
/// title pages do: Liquid Glass at rest, white with a dark glyph and the system lift when focused, and the action's
/// name shown beneath only while focused. The label is an overlay, so the row never shifts. Give the button an
/// accessibility label (`PerchIconButton` does).
public struct PerchIconButtonStyle: ButtonStyle {
    public static let diameter = PerchSize.buttonMinHeight
    let title: String

    public init(title: String) { self.title = title }

    public func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, title: title)
    }

    private struct Styled: View {
        let configuration: Configuration
        let title: String
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.perchStyle) private var style

        var body: some View {
            configuration.label
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(isFocused ? PerchColor.base : Color.white)
                .frame(width: PerchIconButtonStyle.diameter, height: PerchIconButtonStyle.diameter)
                .background {
                    if isFocused {
                        Circle().fill(Color.white)
                    } else {
                        Circle().fill(Color.clear).glassEffect(.regular, in: Circle())
                    }
                }
                .scaleEffect(isFocused && !reduceMotion ? PerchSize.focusScale : 1)
                .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 16, y: 8)
                .overlay(alignment: .top) {
                    Text(title)
                        .font(PerchFont.metadata(style).weight(.medium))
                        .foregroundStyle(PerchColor.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                        .offset(y: PerchIconButtonStyle.diameter + 14)
                        .opacity(isFocused ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .animation(PerchMotion.spring, value: isFocused)
        }
    }
}

/// A secondary action as a glass icon circle whose name shows on focus; the name is also its accessibility label.
public struct PerchIconButton: View {
    private let title: String
    private let systemImage: String
    private let action: () -> Void

    public init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(PerchIconButtonStyle(title: title))
        .accessibilityLabel(title)
    }
}
