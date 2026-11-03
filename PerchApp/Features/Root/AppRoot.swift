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
    enum Route: Hashable { case loading, setup, rerun, reconnect, picker, home }

    let core: CoreServices
    @State private var setupComplete: Bool
    @State private var isRerun = false
    /// Setup is complete but the Plex sign-in is gone: the wizard runs again from Connect Plex until it ends.
    @State private var reconnecting = false
    /// Set when the first-run wizard ends: the picker shows once ("Choose who's watching") before home.
    @State private var choosingAfterSetup = false
    @State private var route: Route

    init(core: CoreServices) {
        self.core = core
        let complete = core.setupCompletion.isComplete
        _setupComplete = State(initialValue: complete)
        _route = State(initialValue: complete ? .loading : .setup)
    }

    /// No stored sign-in at all (as opposed to a sign-in whose server or plex.tv cannot be reached).
    private var hasNoStoredSignIn: Bool {
        guard setupComplete, core.launch.resumeFinished, case .signedOut = core.plexSignIn.snapshot.state
        else { return false }
        return ((try? core.secrets.string(for: .plexOwnerToken)) ?? nil) == nil
    }

    /// Nil while a connection is being made: the screen stays as it is.
    private var desired: Route? {
        if isRerun { return .rerun }
        if !setupComplete { return .setup }
        if !core.launch.resumeFinished { return .loading }
        if reconnecting || hasNoStoredSignIn { return .reconnect }
        switch core.plexSignIn.snapshot.state {
        case .ready: return choosingAfterSetup ? .picker : .home
        case .serverUnreachable: return .home  // unreachable still has a profile; home explains
        case .signedOut: return .picker  // signed in, but plex.tv cannot be reached: the offline picker
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
        .onChange(of: hasNoStoredSignIn, initial: true) { _, none in
            if none { reconnecting = true }
        }
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
        case .reconnect:
            SetupFlowView(core: core, isRerun: true, startAtConnect: true, onFinish: finishSetup)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("root.reconnect")
        case .picker:
            // After the wizard the current profile is a valid pick (home, no PIN); a switch goes home too.
            ProfilePickerView(
                core: core, onBack: choosingAfterSetup ? { choosingAfterSetup = false } : nil,
                onDone: { choosingAfterSetup = false })
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
        let firstRun = !setupComplete && !isRerun
        setupComplete = core.setupCompletion.isComplete
        if firstRun && setupComplete { choosingAfterSetup = true }
        isRerun = false
        reconnecting = false
    }
}
