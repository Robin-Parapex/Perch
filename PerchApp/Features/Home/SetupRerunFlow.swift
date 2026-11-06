import Observation
import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI
import UIKit

/// "Run setup again" from the Settings tab (WP-13; the full Settings screen is WP-18): the Authoriser decides first, so a kid is
/// refused without a keypad; a parent enters the Admin PIN. Moved from the WP-04 placeholder home with its
/// identifiers and copy unchanged.
@MainActor @Observable
final class SetupRerunFlow {
    var askingForPIN = false
    var refused = false
    var lockedUntil: Date?
    var pin = ""
    var failures = 0
    var isChecking = false
    var errorMessage: String?
    var backdrop: UIImage?

    @ObservationIgnored private let core: CoreServices
    @ObservationIgnored private let onRunSetupAgain: () -> Void
    @ObservationIgnored private var profile: PlexActiveProfile?

    var isActive: Bool { askingForPIN || refused }

    init(core: CoreServices, onRunSetupAgain: @escaping () -> Void) {
        self.core = core
        self.onRunSetupAgain = onRunSetupAgain
        backdrop = LibraryBackdrop.cached(artwork: core.artwork)
    }

    func open(profile: PlexActiveProfile?) async {
        self.profile = profile
        if backdrop == nil {
            backdrop = await LibraryBackdrop.fetch(session: core.plexSignIn.session, artwork: core.artwork)
        }
        let context = await permissionContext()
        if case .denied = await core.authoriser.authorise(.editSetup, context: context, entity: "setup.rerun") {
            refused = true
        } else {
            let lockout = await core.adminPIN.lockoutState()
            lockedUntil = lockout.isLocked(at: Date()) ? lockout.lockedUntil : nil
            askingForPIN = true
        }
    }

    func back() {
        if refused { refused = false } else if !isChecking { closePIN() }
    }

    func closePIN() {
        askingForPIN = false
        pin = ""
        errorMessage = nil
        lockedUntil = nil
    }

    /// The Authoriser decides (PerchCore matrix: parent only, fresh Admin PIN). It is asked first so a
    /// kid profile is refused without the PIN being tried, then again once the PIN has been accepted.
    func runSetupAgain(with entered: String) async {
        isChecking = true
        defer { isChecking = false }
        let context = await permissionContext()
        let authoriser = core.authoriser
        if case .denied = await authoriser.authorise(.editSetup, context: context, entity: "setup.rerun") {
            reject(HomeStrings.askParent)
            return
        }
        switch await core.adminPIN.verify(entered) {
        case .accepted:
            if await authoriser.authorise(.editSetup, context: context, entity: "setup.rerun").isAllowed {
                closePIN()
                onRunSetupAgain()
            } else {
                reject(HomeStrings.askParent)
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

extension View {
    /// Replaces the screen with the refused message or the Admin PIN keypad while the flow is active.
    func setupRerunFlow(_ flow: SetupRerunFlow, name: String?) -> some View {
        modifier(SetupRerunFlowModifier(flow: flow, name: name))
    }
}

private struct SetupRerunFlowModifier: ViewModifier {
    @Bindable var flow: SetupRerunFlow
    let name: String?

    func body(content: Content) -> some View {
        // WP-13: a full-screen presentation over the whole shell (sidebar included), so focus moves into the
        // keypad and Back closes it, instead of an in-tree swap that would leave the sidebar reachable.
        content.perchFullScreen(isPresented: active) {
            ZStack {
                if flow.refused {
                    refusedScreen.transition(.opacity)
                } else if flow.askingForPIN {
                    pinScreen.transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: PerchMotion.crossfadeDuration), value: flow.refused)
        }
    }

    /// Back (or the presentation ending) runs the flow's own Back; a PIN being checked stays open.
    private var active: Binding<Bool> {
        Binding(get: { flow.isActive }, set: { if !$0 { flow.back() } })
    }

    private var pinScreen: some View {
        PINEntryScreen(
            name: name ?? "Admin",
            backdrop: flow.backdrop.map { Image(uiImage: $0).resizable() },
            prompt: "Enter the Admin PIN to change setup",
            pin: $flow.pin, failures: flow.failures, isChecking: flow.isChecking, errorMessage: flow.errorMessage,
            lockedUntil: flow.lockedUntil, onBack: { flow.closePIN() },
            onComplete: { entered in Task { await flow.runSetupAgain(with: entered) } }
        )
        .onChange(of: flow.pin) { _, value in if !value.isEmpty { flow.errorMessage = nil } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.setupPIN")
    }

    /// A kid is told straight away: no keypad for something the PIN cannot change.
    private var refusedScreen: some View {
        ZStack {
            SetupBackdrop(art: flow.backdrop.map { AnyView(Image(uiImage: $0).resizable()) })
            VStack(spacing: 40) {
                Text(HomeStrings.askParent)
                    .font(PerchFont.stepTitle(.standard))
                    .foregroundStyle(PerchColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("home.setupRefused")
                Button("OK") { flow.refused = false }
                    .buttonStyle(.perchPrimary)
                    .accessibilityIdentifier("home.setupRefused.ok")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 90)
        }
        .ignoresSafeArea()
        .focusSection()
    }
}
