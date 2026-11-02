import SwiftUI

// Container only: the separate overlay window above the player is WP-07.

/// Edge an overlay slides in from.
enum OverlayEdge {
    case top, trailing

    func offset(_ distance: CGFloat) -> CGSize {
        switch self {
        case .top: CGSize(width: 0, height: -distance)
        case .trailing: CGSize(width: distance, height: 0)
        }
    }
}

/// Slide plus fade, or fade only under Reduce Motion (via `PerchMotion.resolve`).
struct OverlaySlideModifier: ViewModifier {
    let edge: OverlayEdge
    let active: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let effect = PerchMotion.resolve(.slide(offset: PerchMotion.panelOffset), reduceMotion: reduceMotion)
        let distance: CGFloat = if case .slide(let offset) = effect { offset } else { 0 }
        content
            .opacity(active ? 0 : 1)
            .offset(active ? edge.offset(distance) : .zero)
    }
}

extension AnyTransition {
    static func perchOverlay(from edge: OverlayEdge, reduceMotion: Bool) -> AnyTransition {
        .modifier(
            active: OverlaySlideModifier(edge: edge, active: true, reduceMotion: reduceMotion),
            identity: OverlaySlideModifier(edge: edge, active: false, reduceMotion: reduceMotion))
    }
}

extension Animation {
    static func perchOverlay(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: PerchMotion.crossfadeDuration)
            : .easeInOut(duration: PerchMotion.panelDuration)
    }
}
