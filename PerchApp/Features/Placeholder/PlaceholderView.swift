import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI

/// The temporary home until the real Home screen (WP-08): who is signed in, Switch profile, and the
/// Admin-PIN-gated way back into setup (until Settings exists, WP-18).
struct PlaceholderView: View {
    let core: CoreServices
    let onRunSetupAgain: () -> Void

    @State private var path = PlaceholderView.initialPath()
    @State private var profile: PlexActiveProfile?

    @State private var askingForPIN = false
    @State private var pin = ""
    @State private var failures = 0
    @State private var isChecking = false
    @State private var errorMessage: String?

    private enum Route: Hashable {
        case picker
        #if DEBUG
        case gallery
        #endif
    }

    private static func initialPath() -> NavigationPath {
        var path = NavigationPath()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PerchDesignGallery") { path.append(Route.gallery) }
        #endif
        return path
    }

    private var snapshot: PlexSessionSnapshot { core.plexSignIn.snapshot }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                if askingForPIN {
                    pinScreen.transition(.opacity)
                } else {
                    content.transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: PerchMotion.crossfadeDuration), value: askingForPIN)
            .onExitCommand {
                if askingForPIN, !isChecking { closePIN() }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .picker:
                    ProfilePickerView(
                        core: core, onBack: { popPicker() }, onDone: { popPicker() })
                #if DEBUG
                case .gallery:
                    DesignGallery()
                #endif
                }
            }
        }
        .task(id: snapshot.state) { profile = await core.plexSignIn.session.currentProfile() }
    }

    private func popPicker() {
        if !path.isEmpty { path.removeLast() }
    }

    // MARK: Home

    private var content: some View {
        VStack(spacing: 28) {
            Text("Perch")
                .font(.system(size: 120, weight: .bold))
                .foregroundStyle(PerchColor.textPrimary)
            if let profile {
                Text("Watching as \(profile.displayName)")
                    .font(PerchFont.body(.standard))
                    .foregroundStyle(PerchColor.textSecondary)
                    .accessibilityIdentifier("home.profileName")
            }
            if snapshot.state == .serverUnreachable {
                Text("Can't reach your media server")
                    .font(PerchFont.body(.standard))
                    .foregroundStyle(PerchColor.textBody)
                    .accessibilityIdentifier("home.serverDown")
            }
            HStack(spacing: 40) {
                Button("Switch profile") { path.append(Route.picker) }
                    .buttonStyle(.perchPrimary)
                    .accessibilityIdentifier("home.switchProfile")
                Button("Run setup again") { askingForPIN = true }
                    .buttonStyle(.perchSecondary)
                    .accessibilityIdentifier("home.runSetup")
                if snapshot.state == .serverUnreachable {
                    Button("Try again") { Task { await core.plexSignIn.resume() } }
                        .buttonStyle(.perchSecondary)
                        .accessibilityIdentifier("home.retry")
                }
                #if DEBUG
                Button("Design gallery") { path.append(Route.gallery) }
                    .buttonStyle(.perchSecondary)
                    .accessibilityIdentifier("placeholder.gallery")
                #endif
            }
            .padding(.top, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .perchPageBackground()
    }

    // MARK: Run setup again

    private var pinScreen: some View {
        PINEntryScreen(
            name: profile?.displayName ?? "Admin",
            prompt: "Enter the Admin PIN to change setup",
            pin: $pin, failures: failures, isChecking: isChecking, errorMessage: errorMessage,
            onComplete: { entered in Task { await runSetupAgain(with: entered) } }
        )
        .onChange(of: pin) { _, value in if !value.isEmpty { errorMessage = nil } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.setupPIN")
    }

    private func closePIN() {
        askingForPIN = false
        pin = ""
        errorMessage = nil
    }

    /// The Authoriser decides (PerchCore matrix: parent only, fresh Admin PIN). It is asked first so a
    /// kid profile is refused without the PIN being tried, then again once the PIN has been accepted.
    private func runSetupAgain(with entered: String) async {
        isChecking = true
        defer { isChecking = false }
        let context = await permissionContext()
        let authoriser = core.authoriser
        if case .denied = await authoriser.authorise(.editSetup, context: context, entity: "setup.rerun") {
            reject("Ask a parent to change setup")
            return
        }
        switch await core.adminPIN.verify(entered) {
        case .accepted:
            if await authoriser.authorise(.editSetup, context: context, entity: "setup.rerun").isAllowed {
                closePIN()
                onRunSetupAgain()
            } else {
                reject("Ask a parent to change setup")
            }
        case .rejected:
            reject(ProfileSwitcher.wrongPIN)
        case .lockedOut(let until):
            reject(ProfileSwitcher.lockedMessage(until))
        case .setupRequired, .plexUnreachable, .unavailable:
            pin = ""
            errorMessage = "Can't check the Admin PIN right now"
        }
    }

    private func reject(_ message: String) {
        pin = ""
        failures += 1
        errorMessage = message
    }

    /// Unknown role means the strictest one.
    private func permissionContext() async -> PermissionContext {
        guard let profile else { return PermissionContext(role: .kid) }
        let role = await core.settings.document.profiles[profile.id]?.role ?? .kid
        return PermissionContext(role: role, plexUserID: profile.id)
    }
}
