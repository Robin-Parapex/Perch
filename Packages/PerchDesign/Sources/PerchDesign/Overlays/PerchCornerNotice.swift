import SwiftUI

// Container only: the separate overlay window above the player is WP-07.

extension View {
    /// Small passive glass card, top-leading. Never takes focus and never blocks the host.
    public func perchCornerNotice<Notice: View>(
        isPresented: Binding<Bool>,
        autoDismissAfter: Duration? = nil,
        @ViewBuilder content: @escaping () -> Notice
    ) -> some View {
        modifier(PerchCornerNoticeModifier(
            isPresented: isPresented, autoDismissAfter: autoDismissAfter, notice: content))
    }
}

private struct PerchCornerNoticeModifier<Notice: View>: ViewModifier {
    @Binding var isPresented: Bool
    let autoDismissAfter: Duration?
    let notice: () -> Notice
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if isPresented {
                    notice()
                        .padding(24)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
                        .allowsHitTesting(false)
                        .focusable(false)
                        .padding(.top, PerchSpacing.topMargin)
                        .padding(.leading, PerchSpacing.horizontalMargin)
                        // Task is cancelled when the notice is removed or disappears.
                        .task {
                            guard let autoDismissAfter else { return }
                            try? await Task.sleep(for: autoDismissAfter)
                            if !Task.isCancelled { isPresented = false }
                        }
                        .transition(.perchOverlay(from: .top, reduceMotion: reduceMotion))
                }
            }
            .animation(.perchOverlay(reduceMotion: reduceMotion), value: isPresented)
    }
}

#Preview {
    Color.black.ignoresSafeArea()
        .perchCornerNotice(isPresented: .constant(true)) {
            Label("Added to your list", systemImage: "checkmark.circle")
        }
}
