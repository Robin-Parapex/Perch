import SwiftUI

// Container only: the separate overlay window above the player is WP-07.

/// Presents overlay content in a clear, unanimated full-screen cover. A modal presentation is what
/// makes tvOS move focus into the overlay, keep the host unreachable, send Menu to the overlay
/// instead of the NavigationStack, and restore the exact previously focused element on dismiss
/// (UIKit `restoresFocusAfterTransition`). The overlay animates itself in and out via `visible`.
struct FocusTakingOverlay<Overlay: View>: ViewModifier {
    @Binding var isPresented: Bool
    let animation: Animation
    let overlay: (_ visible: Bool) -> Overlay
    @State private var coverShown = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $coverShown) {
                OverlayCoverContent(isPresented: $isPresented, animation: animation, overlay: overlay) {
                    setCover(false)
                }
                .presentationBackground(.clear)
            }
            .onChange(of: isPresented, initial: true) { _, presented in
                if presented, !coverShown { setCover(true) }
            }
            .onChange(of: coverShown) { _, shown in
                // A dismissal the system made on its own must not leave the binding stale.
                if !shown, isPresented { isPresented = false }
            }
    }

    /// The system slide-up is replaced by the overlay's own motion.
    private func setCover(_ shown: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { coverShown = shown }
    }
}

private struct OverlayCoverContent<Overlay: View>: View {
    @Binding var isPresented: Bool
    let animation: Animation
    let overlay: (Bool) -> Overlay
    let onHidden: () -> Void
    @State private var visible = false

    var body: some View {
        overlay(visible)
            .onExitCommand { isPresented = false }
            .onAppear {
                // The binding may have gone false before the cover appeared: dismiss instead of blocking the host.
                if isPresented { withAnimation(animation) { visible = true } } else { onHidden() }
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    withAnimation(animation) { visible = true }
                } else {
                    // Dismiss the cover only after the exit motion, unless re-presented meanwhile.
                    withAnimation(animation) { visible = false } completion: {
                        if !isPresented { onHidden() }
                    }
                }
            }
    }
}
