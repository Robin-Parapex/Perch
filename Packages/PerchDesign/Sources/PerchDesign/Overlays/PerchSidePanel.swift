import SwiftUI

// Container only: the separate overlay window above the player is WP-07.

extension View {
    /// Glass panel, top-trailing at the page margins. Takes focus while shown; Back dismisses
    /// and focus returns to the element that was focused before.
    public func perchSidePanel<Panel: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Panel
    ) -> some View {
        modifier(PerchSidePanelModifier(isPresented: isPresented, panel: content))
    }
}

private struct PerchSidePanelModifier<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let panel: () -> Panel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.modifier(FocusTakingOverlay(
            isPresented: $isPresented, animation: .perchOverlay(reduceMotion: reduceMotion)
        ) { visible in
            panel()
                .padding(32)
                .frame(width: PerchSize.sidePanelWidth)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
                .focusSection()
                .padding(.top, PerchSpacing.topMargin)
                .padding(.trailing, PerchSpacing.horizontalMargin)
                .modifier(OverlaySlideModifier(edge: .trailing, active: !visible, reduceMotion: reduceMotion))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        })
    }
}

#Preview {
    Color.black.ignoresSafeArea()
        .perchSidePanel(isPresented: .constant(true)) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Front door").font(.title2)
                Button("Dismiss") {}.buttonStyle(.perchSecondary)
            }
        }
}
