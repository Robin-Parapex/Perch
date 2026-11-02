import SwiftUI

// Container only: the separate overlay window above the player is WP-07.

extension View {
    /// Capsule button bottom-trailing (like the skip-intro button). Takes focus; auto-hides; Back hides it.
    /// Focus returns to the element that was focused before.
    public func perchCornerPill(
        isPresented: Binding<Bool>,
        autoHideAfter: Duration? = .seconds(6),
        title: String,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        modifier(PerchCornerPillModifier(
            isPresented: isPresented, autoHideAfter: autoHideAfter,
            title: title, systemImage: systemImage, action: action))
    }
}

private struct PerchCornerPillModifier: ViewModifier {
    @Binding var isPresented: Bool
    let autoHideAfter: Duration?
    let title: String
    let systemImage: String?
    let action: () -> Void

    func body(content: Content) -> some View {
        content.modifier(FocusTakingOverlay(
            isPresented: $isPresented, animation: .easeInOut(duration: PerchMotion.crossfadeDuration)
        ) { visible in
            Button(action: action) {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .buttonStyle(.perchSecondary)
            .padding(.bottom, PerchSpacing.topMargin)
            .padding(.trailing, PerchSpacing.horizontalMargin)
            .opacity(visible ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            // Restarts if re-shown; cancelled when the pill hides or the cover goes away.
            .task(id: isPresented) {
                guard isPresented, let autoHideAfter else { return }
                try? await Task.sleep(for: autoHideAfter)
                if !Task.isCancelled { isPresented = false }
            }
        })
    }
}

#Preview {
    Color.black.ignoresSafeArea()
        .perchCornerPill(isPresented: .constant(true), title: "Skip intro", systemImage: "forward.fill") {}
}
