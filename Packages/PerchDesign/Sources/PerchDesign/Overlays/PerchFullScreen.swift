import SwiftUI

extension View {
    /// A whole screen shown over this one (the profile picker, a PIN screen), crossfading in and out. It is a
    /// modal presentation underneath (`FocusTakingOverlay`), so focus moves into it, the host (sidebar included)
    /// cannot be reached, Menu goes to it, and focus returns to the exact element that opened it. The screen
    /// draws its own backdrop; the page background shows where it has none. Back sets the binding false unless
    /// the screen handles Back itself.
    public func perchFullScreen<Screen: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Screen
    ) -> some View {
        modifier(FocusTakingOverlay(
            isPresented: isPresented,
            animation: .easeInOut(duration: PerchMotion.crossfadeDuration),
            overlay: { visible in
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .perchPageBackground()
                    .opacity(visible ? 1 : 0)
            }
        ))
    }
}
