import SwiftUI

/// Which way the wizard is moving, so the next step slides in from the right place.
public enum StepDirection: Sendable, Hashable {
    case forward, backward

    fileprivate var sign: CGFloat { self == .forward ? 1 : -1 }
}

/// Crossfade plus a short slide in the direction of travel; Reduce Motion gets the plain crossfade.
private struct StepTransitionEffect: ViewModifier {
    let offset: CGFloat
    let opacity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let slide = PerchMotion.resolve(.slide(offset: offset), reduceMotion: reduceMotion)
        content
            .opacity(opacity)
            .offset(x: slide == .slide(offset: offset) ? offset : 0)
    }
}

extension AnyTransition {
    /// Move between wizard steps: the old step fades out and drifts back, the new one fades in from ahead.
    public static func perchStep(_ direction: StepDirection) -> AnyTransition {
        let distance = PerchMotion.panelOffset * direction.sign
        return .asymmetric(
            insertion: .modifier(
                active: StepTransitionEffect(offset: distance, opacity: 0),
                identity: StepTransitionEffect(offset: 0, opacity: 1)),
            removal: .modifier(
                active: StepTransitionEffect(offset: -distance, opacity: 0),
                identity: StepTransitionEffect(offset: 0, opacity: 1)))
    }
}

/// Fades a piece of a step in after the one before it (title, then content, then actions).
private struct StagedEntrance: ViewModifier {
    let stage: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let stagger: Double = 0.09

    func body(content: Content) -> some View {
        let lift = PerchMotion.resolve(.slide(offset: PerchMotion.heroTextOffset), reduceMotion: reduceMotion)
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || lift == .fade ? 0 : PerchMotion.heroTextOffset)
            .onAppear {
                let animation: Animation = reduceMotion
                    ? .easeInOut(duration: PerchMotion.crossfadeDuration)
                    : PerchMotion.spring.delay(Double(stage) * Self.stagger)
                withAnimation(animation) { shown = true }
            }
    }
}

extension View {
    /// Staged entrance for part of a step; `stage` 0 appears first, later stages follow in small steps.
    public func perchStagedEntrance(stage: Int) -> some View {
        modifier(StagedEntrance(stage: stage))
    }

    /// Swap between wizard steps: give the step `.id(step)` and animate the change with `PerchMotion.spring`.
    public func perchStepTransition(_ direction: StepDirection) -> some View {
        transition(.perchStep(direction))
    }
}
