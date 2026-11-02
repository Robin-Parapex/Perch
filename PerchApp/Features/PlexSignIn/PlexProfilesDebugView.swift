import PerchDesign
import PerchCore
import PerchPlex
import SwiftUI

/// Plain Home user list to exercise switching. The real picker is WP-05.
struct PlexProfilesDebugView: View {
    let model: PlexSignInModel
    @Binding var path: NavigationPath
    @State private var rows: [PlexProfileRow] = []
    @State private var pinTarget: PINTarget?
    @State private var pin = ""
    @State private var message: String?
    @State private var switching = false
    @State private var failures = 0

    /// What the PIN screen is for: switching to a protected profile, or checking the Admin PIN.
    private enum PINTarget: Identifiable {
        case profile(PlexProfileRow)
        case admin

        var id: String {
            switch self {
            case .profile(let row): "profile.\(row.id)"
            case .admin: "admin"
            }
        }

        var title: String {
            switch self {
            case .profile(let row): "Enter the PIN for \(row.name)"
            case .admin: "Enter the Admin PIN"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PerchSpacing.itemGap) {
                Text("Profiles")
                    .font(.system(size: PerchFont.sectionSize, weight: .semibold))
                    .foregroundStyle(PerchColor.textPrimary)
                    .accessibilityIdentifier("plexProfiles.title")
                ForEach(rows) { row in
                    Button { tap(row) } label: {
                        HStack(spacing: PerchSpacing.itemGap) {
                            Text(row.name)
                            Text("\(row.roleLabel), up to \(row.ceilingLabel)")
                                // Relative to the button's colour, so it stays legible when focused.
                                .foregroundStyle(.secondary)
                            if row.id == model.currentProfileID {
                                Image(systemName: "checkmark")
                                    .accessibilityLabel("Current profile")
                            }
                        }
                    }
                    .buttonStyle(.perchSecondary)
                    .disabled(locked(row) || switching)
                    .accessibilityIdentifier("plexProfiles.\(row.id)")
                }
                if pinTarget == nil, let message {
                    Text(message)
                        .font(.system(size: PerchFont.bodySize))
                        .foregroundStyle(PerchColor.textBody)
                        .accessibilityIdentifier("plexProfiles.message")
                }
                ConnectionNotice(model: model) { Task { await model.resume() } }
                Button("Check Admin PIN") { open(.admin) }
                    .buttonStyle(.perchSecondary)
                    .disabled(switching)
                    .accessibilityIdentifier("plexProfiles.checkAdmin")
                Button("Sign out") {
                    Task {
                        await model.signOut()
                        path = NavigationPath()
                    }
                }
                .buttonStyle(.perchSecondary)
                .accessibilityIdentifier("plexProfiles.signOut")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .perchPageMargins()
        }
        .ignoresSafeArea()
        .perchPageBackground()
        .task { await load() }
        // Full screen and centred, like the Plex and Apple TV PIN screens; Back cancels.
        .fullScreenCover(item: $pinTarget) { target in pinScreen(for: target) }
    }

    private func pinScreen(for target: PINTarget) -> some View {
        PINScreen(
            title: target.title, pin: $pin, message: $message, failures: $failures, switching: $switching
        ) { entered in
            switch target {
            case .profile(let row): await switchTo(row, pin: entered)
            case .admin: await checkAdmin(entered)
            }
        }
    }

    private func locked(_ row: PlexProfileRow) -> Bool {
        row.isProtected && !model.plexTVReachable && row.id != model.currentProfileID
    }

    private func load() async {
        do { rows = try await model.profileRows() } catch { message = PlexSignInModel.message(for: error) }
    }

    private func open(_ target: PINTarget) {
        message = nil
        pin = ""
        pinTarget = target
    }

    private func tap(_ row: PlexProfileRow) {
        message = nil
        pin = ""
        if row.id == model.currentProfileID { pinTarget = nil; return }
        if row.isProtected {
            open(.profile(row))
        } else {
            pinTarget = nil
            Task { await switchTo(row, pin: nil) }
        }
    }

    /// Takes the entered PIN rather than reading `pin`, which may not have caught up with the pad yet.
    private func switchTo(_ row: PlexProfileRow, pin entered: String?) async {
        guard !switching else { return }
        switching = true
        defer { switching = false }
        do {
            // Debug only: slice C replaces this view with the policy-driven ProfileSwitcher.
            try await model.session.switchProfile(
                to: PlexUserID(row.id), pin: row.isProtected ? entered : nil,
                requirement: row.isProtected ? .targetPlexPIN : .none)
            pinTarget = nil
            pin = ""
            message = nil
        } catch {
            pin = ""
            if row.isProtected { failures += 1 }
            message = PlexSignInModel.message(for: error, switchingProfile: true)
        }
    }

    private func checkAdmin(_ entered: String) async {
        guard !switching else { return }
        switching = true
        defer { switching = false }
        let result = await model.adminPIN.verify(entered)
        pin = ""
        switch result {
        case .accepted:
            pinTarget = nil
            message = "Admin PIN accepted"
        case .rejected:
            failures += 1
            message = "That PIN isn't right"
        case .lockedOut(let until):
            failures += 1
            message = "Too many tries. Try again in \(PlexSignInModel.duration(until))"
        case .setupRequired: message = "No Admin PIN is set up yet"
        case .plexUnreachable: message = "The PIN can't be checked right now"
        case .unavailable: message = "Couldn't read the Admin PIN"
        }
    }
}

/// Its own view, reading the state through bindings, so the cover redraws when the message or
/// the failure count change (a cover closure in the parent does not).
private struct PINScreen: View {
    let title: String
    @Binding var pin: String
    @Binding var message: String?
    @Binding var failures: Int
    @Binding var switching: Bool
    let submit: (String) async -> Void

    var body: some View {
        VStack(spacing: 48) {
            Text(title)
                .font(.system(size: PerchFont.sectionSize + 8, weight: .semibold))
                .foregroundStyle(PerchColor.textPrimary)
            PerchPINPad(pin: $pin, failures: failures) { entered in
                Task { await submit(entered) }
            }
            .disabled(switching)
            // Spinner while the PIN is checked, then the outcome line (after Dusk's tvOS PIN screen).
            ZStack {
                if switching {
                    ProgressView()
                } else {
                    Text(message ?? " ")
                        .font(.system(size: PerchFont.bodySize))
                        .foregroundStyle(PerchColor.textBody)
                        .accessibilityIdentifier("plexProfiles.pinMessage")
                }
            }
            .frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .perchPageBackground()
        .onDisappear { pin = "" }
    }
}
