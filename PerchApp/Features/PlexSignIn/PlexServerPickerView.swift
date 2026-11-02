import PerchDesign
import PerchPlex
import SwiftUI

/// Server choice (skipped for one server) and the "Connected to ..." confirmation.
struct PlexServerPickerView: View {
    let model: PlexSignInModel
    @Binding var path: NavigationPath
    @State private var error: String?

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
                            .foregroundStyle(PerchColor.textSecondary)
                    }
                }
                .buttonStyle(.perchSecondary)
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
        .perchPageBackground()
    }

    private func choose(_ server: PlexServer) async {
        error = nil
        do {
            try await model.session.choose(server: server)
            if !path.isEmpty { path.removeLast() }
            path.append(PlexRoute.connected)
        } catch {
            self.error = "Can't reach that server"
        }
    }
}

struct PlexConnectedView: View {
    let model: PlexSignInModel
    @Binding var path: NavigationPath
    @State private var summary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PerchSpacing.rowGap) {
            Text(summary ?? " ")
                .font(.system(size: PerchFont.sectionSize, weight: .semibold))
                .foregroundStyle(PerchColor.textPrimary)
                .accessibilityIdentifier("plexConnected.summary")
            Button("Profiles") {
                if !path.isEmpty { path.removeLast() }
                path.append(PlexRoute.profiles)
            }
            .buttonStyle(.perchPrimary)
            .accessibilityIdentifier("plexConnected.profiles")
            Button("Done") { path = NavigationPath() }
                .buttonStyle(.perchSecondary)
                .accessibilityIdentifier("plexConnected.done")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .perchPageMargins()
        .perchPageBackground()
        .task { summary = await model.connectedSummary() }
    }
}
