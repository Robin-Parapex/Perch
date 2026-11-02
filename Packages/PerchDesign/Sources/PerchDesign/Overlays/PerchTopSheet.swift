import SwiftUI

// Container only: the separate overlay window above the player is WP-07.

extension View {
    /// Half-height glass sheet from the top edge; host dims. Takes focus while shown; Back dismisses
    /// and focus returns to the element that was focused before.
    public func perchTopSheet<Sheet: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Sheet
    ) -> some View {
        modifier(PerchTopSheetModifier(isPresented: isPresented, sheet: content))
    }
}

private struct PerchTopSheetModifier<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    let sheet: () -> Sheet
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.modifier(FocusTakingOverlay(
            isPresented: $isPresented, animation: .perchOverlay(reduceMotion: reduceMotion)
        ) { visible in
            ZStack(alignment: .top) {
                Color.black.opacity(visible ? 0.3 : 0)
                GeometryReader { proxy in
                    sheet()
                        .padding(.horizontal, PerchSpacing.horizontalMargin)
                        .padding(.top, PerchSpacing.topMargin)
                        .padding(.bottom, 32)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                        .glassEffect(.regular, in: Rectangle())
                        .focusSection()
                }
                .containerRelativeFrame(.vertical) { length, _ in length / 2 }
                .modifier(OverlaySlideModifier(edge: .top, active: !visible, reduceMotion: reduceMotion))
            }
            .ignoresSafeArea()
        })
    }
}

#Preview {
    Color.gray.ignoresSafeArea()
        .perchTopSheet(isPresented: .constant(true)) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Living room").font(.title2)
                Button("Done") {}.buttonStyle(.perchSecondary)
            }
        }
}
