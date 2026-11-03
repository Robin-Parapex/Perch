import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI
import UIKit

/// The temporary home until the real Home screen (WP-08): who is signed in, Switch profile, and the
/// Admin-PIN-gated way back into setup (until Settings exists, WP-18).
struct PlaceholderView: View {
    let core: CoreServices
    let onRunSetupAgain: () -> Void

    @State private var path = PlaceholderView.initialPath()
    @State private var profile: PlexActiveProfile?

    @State private var askingForPIN = false
    @State private var refused = false
    @State private var lockedUntil: Date?
    @State private var backdrop: UIImage? = LibraryBackdrop.cached()
    @State private var pin = ""
    @State private var failures = 0
    @State private var isChecking = false
    @State private var errorMessage: String?

    private enum Route: Hashable {
        case picker
        #if DEBUG
        case gallery
        case libraryCheck
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
                if refused {
                    refusedScreen.transition(.opacity)
                } else if askingForPIN {
                    pinScreen.transition(.opacity)
                } else {
                    content.transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: PerchMotion.crossfadeDuration), value: askingForPIN || refused)
            // Nil on home itself, so Back leaves the app (top level) instead of being swallowed.
            .onExitCommand(
                perform: (refused || askingForPIN)
                    ? { if refused { refused = false } else if !isChecking { closePIN() } } : nil)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .picker:
                    ProfilePickerView(
                        core: core, onBack: { popPicker() }, onDone: { popPicker() })
                #if DEBUG
                case .gallery:
                    DesignGallery()
                case .libraryCheck:
                    LibraryCheckView(core: core)
                #endif
                }
            }
        }
        .task(id: snapshot.state) {
            profile = await core.plexSignIn.session.currentProfile()
            if backdrop == nil { backdrop = await LibraryBackdrop.fetch(session: core.plexSignIn.session) }
        }
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
                Button("Run setup again") { Task { await openRunSetup() } }
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
                Button("Library check") { path.append(Route.libraryCheck) }
                    .buttonStyle(.perchSecondary)
                    .accessibilityIdentifier("placeholder.libraryCheck")
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
            backdrop: backdrop.map { Image(uiImage: $0).resizable() },
            prompt: "Enter the Admin PIN to change setup",
            pin: $pin, failures: failures, isChecking: isChecking, errorMessage: errorMessage,
            lockedUntil: lockedUntil, onBack: { closePIN() },
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
        lockedUntil = nil
    }

    /// A kid is told straight away: no keypad for something the PIN cannot change.
    private var refusedScreen: some View {
        ZStack {
            SetupBackdrop(art: backdrop.map { AnyView(Image(uiImage: $0).resizable()) })
            VStack(spacing: 40) {
                Text("Ask a parent to change setup")
                    .font(PerchFont.stepTitle(.standard))
                    .foregroundStyle(PerchColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("home.setupRefused")
                Button("OK") { refused = false }
                    .buttonStyle(.perchPrimary)
                    .accessibilityIdentifier("home.setupRefused.ok")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 90)
        }
        .ignoresSafeArea()
        .focusSection()
    }

    private func openRunSetup() async {
        let context = await permissionContext()
        if case .denied = await core.authoriser.authorise(.editSetup, context: context, entity: "setup.rerun") {
            refused = true
        } else {
            let lockout = await core.adminPIN.lockoutState()
            lockedUntil = lockout.isLocked(at: Date()) ? lockout.lockedUntil : nil
            askingForPIN = true
        }
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
            pin = ""
            errorMessage = nil
            lockedUntil = until
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
