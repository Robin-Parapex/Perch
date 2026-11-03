import PerchDesign
import PerchPlex
import SwiftUI

/// Shows the plex.tv/link code, renews it by itself and moves on once the phone has linked.
struct PlexLinkCodeView: View {
    let model: PlexSignInModel
    @Binding var path: NavigationPath
    @State private var code: String?
    @State private var failed = false
    @State private var message = "Can't reach Plex right now"
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: PerchSpacing.rowGap) {
            if failed {
                Text(message)
                    .font(.system(size: PerchFont.sectionSize, weight: .semibold))
                    .foregroundStyle(PerchColor.textPrimary)
                    .accessibilityIdentifier("plexCode.error")
                Button("Try again") { failed = false; message = "Can't reach Plex right now"; attempt += 1 }
                    .buttonStyle(.perchPrimary)
                    .accessibilityIdentifier("plexCode.retry")
            } else {
                Text("On your phone, go to plex.tv/link and enter this code")
                    .font(.system(size: PerchFont.sectionSize, weight: .semibold))
                    .foregroundStyle(PerchColor.textBody)
                Text(code ?? " ")
                    .font(.system(size: PerchFont.heroSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(PerchColor.textPrimary)
                    .accessibilityIdentifier("plexCode.value")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .perchPageMargins()
        .ignoresSafeArea()
        .perchPageBackground()
        .task(id: attempt) { await run() }
    }

    private func run() async {
        let flow = PlexLinkFlow(transport: model.transport, endpoints: model.endpoints)
        for await state in flow.start() {
            switch state {
            case .code(let value, _): code = value
            case .failed: failed = true; return
            case .linked(let token): await finish(token: token); return
            }
        }
    }

    private func finish(token: String) async {
        do {
            let servers = try await model.session.signIn(accountToken: token)
            model.servers = servers
            if !path.isEmpty { path.removeLast() }
            path.append(servers.count > 1 ? PlexRoute.servers : PlexRoute.connected)
        } catch {
            message = PlexSignInModel.message(for: error)
            failed = true
        }
    }
}
