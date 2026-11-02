import SwiftUI

struct PerchFocusRing: ViewModifier {
    let isFocused: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white, lineWidth: PerchSize.focusRingWidth)
                .opacity(isFocused ? 1 : 0)
        }
    }
}

extension View {
    /// White ring of `PerchSize.focusRingWidth` while focused.
    public func perchFocusRing(isFocused: Bool, radius: CGFloat) -> some View {
        modifier(PerchFocusRing(isFocused: isFocused, radius: radius))
    }
}
