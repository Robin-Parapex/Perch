import Observation
import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI

/// Launch facts the root needs that no other object holds.
@MainActor @Observable
final class LaunchState {
    /// True once the saved profile has been tried (resumed or not), so the picker never flashes before it.
    var resumeFinished = false
}

/// The app's root. The screen is derived from state, never navigated to (after Dusk's ContentView state machine):
/// the wizard until setup is complete, then the profile picker when no profile resumed, else the home.
/// A re-run of setup shows the wizard on top of a completed setup and returns home when it ends.
struct AppRoot: View {
    enum Route: Hashable { case loading, setup, rerun, picker, home }

    let core: CoreServices
    @State private var setupComplete: Bool
    @State private var isRerun = false
    @State private var route: Route

    init(core: CoreServices) {
        self.core = core
        let complete = core.setupCompletion.isComplete
        _setupComplete = State(initialValue: complete)
        _route = State(initialValue: complete ? .loading : .setup)
    }

    /// Nil while a connection is being made: the screen stays as it is.
    private var desired: Route? {
        if isRerun { return .rerun }
        if !setupComplete { return .setup }
        if !core.launch.resumeFinished { return .loading }
        switch core.plexSignIn.snapshot.state {
        case .ready, .serverUnreachable: return .home  // unreachable still has a profile; home explains
        case .signedOut: return .picker
        case .connecting: return nil
        }
    }

    var body: some View {
        ZStack {
            screen.id(route).transition(.opacity)
        }
        // Reduce Motion needs no variant: the change between screens is only a fade.
        .animation(.easeInOut(duration: PerchMotion.crossfadeDuration), value: route)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .perchPageBackground()
        .onChange(of: desired, initial: true) { _, next in
            if let next { route = next }
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch route {
        case .loading:
            Color.clear.accessibilityIdentifier("root.loading")
        case .setup:
            SetupFlowView(core: core, isRerun: false, onFinish: finishSetup)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("root.setup")
        case .rerun:
            SetupFlowView(core: core, isRerun: true, onFinish: finishSetup)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("root.rerun")
        case .picker:
            ProfilePickerView(core: core, onBack: nil, onDone: nil)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("root.picker")
        case .home:
            PlaceholderView(core: core, onRunSetupAgain: { isRerun = true })
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("root.home")
        }
    }

    /// The wizard ends: a first run is now complete; a re-run goes home (also when Back leaves Welcome).
    private func finishSetup() {
        setupComplete = core.setupCompletion.isComplete
        isRerun = false
    }
}
