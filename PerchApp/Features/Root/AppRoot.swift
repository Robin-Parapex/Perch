import Observation
import PerchCore
import PerchDesign
import PerchPlayer
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
    @State private var launchItemPlayed = false

    init(core: CoreServices) {
        self.core = core
        let complete = core.setupCompletion.isComplete
        _setupComplete = State(initialValue: complete)
        _route = State(initialValue: Self.opensGallery ? .home : complete ? .loading : .setup)
    }

    /// DEBUG `-PerchDesignGallery`: home from the first frame, whatever the stored setup or sign-in, so the
    /// gallery pushed onto the Home tab is never routed away or re-mounted (WP-04 behaviour).
    private static var opensGallery: Bool {
        #if DEBUG
        // `-PerchPlayerSpike` (WP-07 spike) is pinned the same way.
        ProcessInfo.processInfo.arguments.contains("-PerchDesignGallery") || PlayerSpikeView.isRequested
        #else
        false
        #endif
    }

    /// No stored sign-in at all (as opposed to a sign-in whose server or plex.tv cannot be reached).
    private var hasNoStoredSignIn: Bool {
        guard setupComplete, core.launch.resumeFinished, case .signedOut = core.plexSignIn.snapshot.state
        else { return false }
        return ((try? core.secrets.string(for: .plexOwnerToken)) ?? nil) == nil
    }

    private var playerPresented: Binding<Bool> {
        Binding(get: { core.playback.activeSession != nil }, set: { if !$0 { core.playback.dismissActive() } })
    }

    #if DEBUG
    /// `-PerchPlayItem <rating key> [-PerchStartMs <ms>]`: plays that title once, when home is shown.
    private func playLaunchItemIfAsked() async {
        guard route == .home, !launchItemPlayed else { return }
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        guard let key = value("-PerchPlayItem") else { return }
        launchItemPlayed = true
        guard let detail = try? await core.library.detail(ratingKey: key) else { return }
        core.playback.play(detail.summary, startMs: value("-PerchStartMs").flatMap(Int.init))
    }
    #endif

    /// Nil while a connection is being made: the screen stays as it is.
    private var desired: Route? {
        if Self.opensGallery { return .home }
        if isRerun { return .rerun }
        if !setupComplete { return .setup }
        if !core.launch.resumeFinished {
            // WP-09: the saved profile is known (the session only reports connecting once it has it), so Home
            // renders from its snapshot while the server is tried, instead of a blank screen until the probe ends.
            if core.plexSignIn.snapshot.state == .connecting { return .home }
            return .loading
        }
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
        // WP-09: the page tint follows the Home hero's backdrop (ArtworkTintModel), crossfading as it changes.
        .environment(\.perchTint, core.artworkTint.tint)
        // The player sits above whatever screen launched it, so Back returns to that screen as it was.
        .fullScreenCover(isPresented: playerPresented) {
            if let session = core.playback.activeSession {
                PlayerContainerView(
                    session: session, onExit: { core.playback.dismissActive() },
                    overlay: { request in
                        PlayerOverlayContent(request: request, session: session, playback: core.playback)
                    }
                )
                .ignoresSafeArea()
                #if DEBUG
                .overlay(alignment: .topLeading) { PlayerStatusProbe(session: session) }
                #endif
            }
        }
        #if DEBUG
        .task(id: route) { await playLaunchItemIfAsked() }
        #endif
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
            #if DEBUG
            if PlayerSpikeView.isRequested {
                PlayerSpikeView(core: core)
            } else {
                MainShell(core: core, onRunSetupAgain: { isRerun = true })
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("root.home")
            }
            #else
            MainShell(core: core, onRunSetupAgain: { isRerun = true })
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("root.home")
            #endif
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
