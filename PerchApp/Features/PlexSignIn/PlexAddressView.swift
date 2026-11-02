import PerchDesign
import SwiftUI

/// Manual route: an address and a token, typed on the native keyboard (the iPhone keyboard prompt works).
struct PlexAddressView: View {
    let model: PlexSignInModel
    @Binding var path: NavigationPath
    @State private var address = ""
    @State private var token = ""
    @State private var error: String?
    @State private var connecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: PerchSpacing.itemGap) {
            Text("Enter a server address")
                .font(.system(size: PerchFont.sectionSize, weight: .semibold))
                .foregroundStyle(PerchColor.textPrimary)
                .accessibilityIdentifier("plexAddress.title")
            TextField("Address, for example 192.168.1.20", text: $address)
                .textContentType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("plexAddress.field")
            SecureField("Token", text: $token)
                .accessibilityIdentifier("plexAddress.token")
            if let error {
                Text(error)
                    .font(.system(size: PerchFont.bodySize))
                    .foregroundStyle(PerchColor.textBody)
                    .accessibilityIdentifier("plexAddress.error")
            }
            Button("Connect") { Task { await connect() } }
                .buttonStyle(.perchPrimary)
                .disabled(connecting || address.isEmpty || token.isEmpty)
                .accessibilityIdentifier("plexAddress.connect")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .perchPageMargins()
        .perchPageBackground()
    }

    private func connect() async {
        connecting = true
        error = nil
        defer { connecting = false }
        do {
            try await model.session.signInManually(address: address, token: token)
            token = ""
            if !path.isEmpty { path.removeLast() }
            path.append(PlexRoute.connected)
        } catch {
            self.error = PlexSignInModel.message(for: error)
        }
    }
}
