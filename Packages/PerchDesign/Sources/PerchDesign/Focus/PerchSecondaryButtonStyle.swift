import SwiftUI

/// Glass capsule with white text; white fill and dark text when focused, like native tvOS buttons.
public struct PerchSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        FocusStyled(configuration: configuration)
    }

    private struct FocusStyled: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? PerchColor.base : Color.white)
                .padding(.horizontal, 40)
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

extension ButtonStyle where Self == PerchSecondaryButtonStyle {
    public static var perchSecondary: PerchSecondaryButtonStyle { PerchSecondaryButtonStyle() }
}
