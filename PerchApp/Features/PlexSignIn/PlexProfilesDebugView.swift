import PerchDesign
import PerchCore
import PerchPlex
import SwiftUI

/// Plain Home user list to exercise switching. The real picker is WP-05.
struct PlexProfilesDebugView: View {
    let model: PlexSignInModel
    @Binding var path: NavigationPath
    @State private var rows: [PlexProfileRow] = []
    @State private var selected: PlexProfileRow?
    @State private var pin = ""
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PerchSpacing.itemGap) {
                Text("Profiles")
                    .font(.system(size: PerchFont.sectionSize, weight: .semibold))
                    .foregroundStyle(PerchColor.textPrimary)
                ForEach(rows) { row in
                    Button { tap(row) } label: {
                        HStack(spacing: PerchSpacing.itemGap) {
                            Text(row.name)
                            Text("\(row.roleLabel), up to \(row.ceilingLabel)")
                                .foregroundStyle(PerchColor.textSecondary)
                            if row.id == model.currentProfileID {
                                Image(systemName: "checkmark")
                                    .accessibilityLabel("Current profile")
                            }
                        }
                    }
                    .buttonStyle(.perchSecondary)
                    .disabled(locked(row))
                    .accessibilityIdentifier("plexProfiles.\(row.id)")
                }
                if let selected {
                    SecureField("PIN for \(selected.name)", text: $pin)
                        .accessibilityIdentifier("plexProfiles.pin")
                    Button("Switch") { Task { await switchTo(selected) } }
                        .buttonStyle(.perchPrimary)
                        .disabled(pin.isEmpty)
                        .accessibilityIdentifier("plexProfiles.switch")
                }
                if let message {
                    Text(message)
                        .font(.system(size: PerchFont.bodySize))
                        .foregroundStyle(PerchColor.textBody)
                        .accessibilityIdentifier("plexProfiles.message")
                }
                ConnectionNotice(model: model) { Task { await model.resume() } }
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
    }

    private func locked(_ row: PlexProfileRow) -> Bool {
        row.isProtected && !model.plexTVReachable && row.id != model.currentProfileID
    }

    private func load() async {
        do { rows = try await model.profileRows() } catch { message = PlexSignInModel.message(for: error) }
    }

    private func tap(_ row: PlexProfileRow) {
        message = nil
        pin = ""
        if row.id == model.currentProfileID { selected = nil; return }
        if row.isProtected {
            selected = row
        } else {
            selected = nil
            Task { await switchTo(row) }
        }
    }

    private func switchTo(_ row: PlexProfileRow) async {
        do {
            try await model.session.switchProfile(to: PlexUserID(row.id), pin: row.isProtected ? pin : nil)
            selected = nil
            pin = ""
            message = nil
        } catch {
            pin = ""
            message = PlexSignInModel.message(for: error)
        }
    }
}
