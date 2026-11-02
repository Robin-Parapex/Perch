import PerchDesign
import PerchPlex
import SwiftUI

/// Server choice (skipped for one server) and the "Connected to ..." confirmation.
struct PlexServerPickerView: View {
    let model: PlexSignInModel
    @Binding var path: NavigationPath
    @State private var error: String?
    // Reached by replacing the link-code screen, which has nothing focusable, so tvOS
    // assigns no focus on its own; claim it explicitly.
    @FocusState private var focusedServer: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PerchSpacing.itemGap) {
            Text("Choose a server")
                .font(.system(size: PerchFont.sectionSize, weight: .semibold))
                .foregroundStyle(PerchColor.textPrimary)
            ForEach(model.servers) { server in
                Button {
                    Task { await choose(server) }
                } label: {
                    HStack(spacing: PerchSpacing.itemGap) {
                        Text(server.name)
                        Text(server.hasLocalConnection ? "This home" : "Away")
                            // Relative to the button's colour, so it stays legible when focused.
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.perchSecondary)
                .focused($focusedServer, equals: server.machineID)
                .accessibilityIdentifier("plexServers.\(server.machineID)")
            }
            if let error {
                Text(error)
                    .font(.system(size: PerchFont.bodySize))
                    .foregroundStyle(PerchColor.textBody)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .perchPageMargins()
        .ignoresSafeArea()
        .perchPageBackground()
        .onAppear { focusedServer = model.servers.first?.machineID }
    }

    private func choose(_ server: PlexServer) async {
        error = nil
        do {
            try await model.session.choose(server: server)
            if !path.isEmpty { path.removeLast() }
            path.append(PlexRoute.connected)
        } catch {
            self.error = PlexSignInModel.message(for: error)
        }
    }
}

struct PlexConnectedView: View {
    let model: PlexSignInModel
    @Binding var path: NavigationPath
    @State private var summary: String?
    // Same as the server picker: replaces a screen with nothing focusable.
    @FocusState private var profilesFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PerchSpacing.rowGap) {
            Text(summary ?? " ")
                .font(.system(size: PerchFont.sectionSize, weight: .semibold))
                .foregroundStyle(PerchColor.textPrimary)
                .accessibilityIdentifier("plexConnected.summary")
            // Pushed, not replacing Connected, so Back returns here.
            Button("Profiles") { path.append(PlexRoute.profiles) }
                .buttonStyle(.perchPrimary)
                .focused($profilesFocused)
                .accessibilityIdentifier("plexConnected.profiles")
            Button("Done") { path = NavigationPath() }
                .buttonStyle(.perchSecondary)
                .accessibilityIdentifier("plexConnected.done")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .perchPageMargins()
        .ignoresSafeArea()
        .perchPageBackground()
        .onAppear { profilesFocused = true }
        .task { summary = await model.connectedSummary() }
    }
}
