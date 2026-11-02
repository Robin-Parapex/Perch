import SwiftUI

/// White capsule with dark text.
public struct PerchPrimaryButtonStyle: ButtonStyle {
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
                .foregroundStyle(PerchColor.base)
                .padding(.horizontal, 40)
                .frame(minHeight: PerchSize.buttonMinHeight)
                .background(Capsule().fill(Color.white))
                .scaleEffect(isFocused && !reduceMotion ? PerchSize.focusScale : 1)
                .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 16, y: 8)
                .animation(PerchMotion.spring, value: isFocused)
        }
    }
}

extension ButtonStyle where Self == PerchPrimaryButtonStyle {
    public static var perchPrimary: PerchPrimaryButtonStyle { PerchPrimaryButtonStyle() }
}
