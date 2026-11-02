import PerchDesign
import SwiftUI

/// Connect Plex: a choice, the link code, or an address and token; then the "Connected to ..." confirmation.
struct SetupConnectStep: View {
    let model: SetupFlowModel

    var body: some View {
        switch model.connectStage {
        case .choice: SetupConnectChoice(model: model)
        case .code: SetupLinkCode(model: model)
        case .address: SetupAddress(model: model)
        case .connected: SetupConnectedStep(model: model)
        }
    }
}

private struct SetupConnectChoice: View {
    let model: SetupFlowModel

    var body: some View {
        SetupStepContainer(
            title: "Connect Plex",
            helper: "Perch plays your library from your Plex server.",
            step: model.stepNumber, of: model.stepCount,
            primaryTitle: "Sign in with a code", primaryAction: { Task { await model.showCode() } }
        ) {
            Button("Enter a server address") { Task { await model.showAddress() } }
                .buttonStyle(.perchSecondary)
                .accessibilityIdentifier("setup.connect.address")
        }
    }
}

/// The 4-character code in large glass tiles (layout after Dusk SignInView, MIT; approach only).
private struct SetupLinkCode: View {
    let model: SetupFlowModel

    var body: some View {
        SetupStepContainer(
            title: "Sign in with a code",
            helper: "On your phone, go to plex.tv/link and enter this code",
            step: model.stepNumber, of: model.stepCount,
            primaryTitle: "Get a new code", primaryAction: { model.newCode() }
        ) {
            VStack(spacing: 24) {
                tiles
                if let error = model.linkError {
                    Text(error)
                        .font(.system(size: PerchFont.bodySize))
                        .foregroundStyle(PerchColor.textBody)
                        .accessibilityIdentifier("setup.code.error")
                }
            }
        }
        .task(id: model.linkAttempt) { await model.runLink() }
    }

    private var tiles: some View {
        let characters = Array(model.linkCode ?? "    ")
        return HStack(spacing: 20) {
            ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .font(.system(size: 96, weight: .bold, design: .monospaced))
                    .foregroundStyle(PerchColor.textPrimary)
                    .frame(width: 130, height: 160)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.linkCode ?? "Getting a code")
        .accessibilityIdentifier("setup.code.value")
    }
}

private struct SetupAddress: View {
    @Bindable var model: SetupFlowModel

    var body: some View {
        SetupStepContainer(
            title: "Enter a server address",
            helper: "The address of your Plex server, for example 192.168.1.20, and the token that goes with it.",
            step: model.stepNumber, of: model.stepCount,
            primaryTitle: model.connecting ? "Connecting" : "Connect",
            primaryAction: { Task { await model.connectManually() } }
        ) {
            VStack(spacing: 20) {
                TextField("Server address", text: $model.address)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .perchSetupField()
                    .accessibilityIdentifier("setup.address.field")
                SecureField("Token", text: $model.token)
                    .perchSetupField()
                    .accessibilityIdentifier("setup.address.token")
                if let error = model.addressError {
                    Text(error)
                        .font(.system(size: PerchFont.bodySize))
                        .foregroundStyle(PerchColor.textBody)
                        .accessibilityIdentifier("setup.address.error")
                }
            }
        }
    }
}

/// "Connected to <server>, <n> libraries" (SPEC 1a). Also used after choosing a server.
struct SetupConnectedStep: View {
    let model: SetupFlowModel

    var body: some View {
        SetupStepContainer(
            title: "Plex is connected",
            step: model.stepNumber, of: model.stepCount,
            primaryTitle: "Continue", primaryAction: { Task { await model.advance() } },
            backdrop: model.backdropView
        ) {
            Text(model.summary ?? " ")
                .font(.system(size: PerchFont.sectionSize, weight: .semibold))
                .foregroundStyle(PerchColor.textBody)
                .accessibilityIdentifier("setup.connected.summary")
        }
    }
}

/// Server list for an account with more than one server, then the same confirmation.
struct SetupServerStep: View {
    @Bindable var model: SetupFlowModel

    var body: some View {
        if model.serverChosen {
            SetupConnectedStep(model: model)
        } else {
            SetupStepContainer(
                title: "Choose your server",
                helper: "Your Plex account has more than one server.",
                step: model.stepNumber, of: model.stepCount,
                primaryTitle: "Use this server", primaryAction: { Task { await model.chooseSelectedServer() } }
            ) {
                VStack(spacing: 16) {
                    ForEach(model.servers) { server in
                        Button {
                            model.selectedServerID = server.machineID
                        } label: {
                            HStack(spacing: 24) {
                                Text(server.name)
                                Text(server.hasLocalConnection ? "This home" : "Away")
                                    // Relative to the button's colour, so it stays legible when focused.
                                    .foregroundStyle(.secondary)
                                Image(systemName: "checkmark")
                                    .opacity(model.selectedServerID == server.machineID ? 1 : 0)
                                    .accessibilityLabel("Selected")
                            }
                            .frame(minWidth: 520)
                        }
                        .buttonStyle(.perchSecondary)
                        .accessibilityIdentifier("setup.server.\(server.machineID)")
                    }
                    if let error = model.serverError {
                        Text(error)
                            .font(.system(size: PerchFont.bodySize))
                            .foregroundStyle(PerchColor.textBody)
                            .accessibilityIdentifier("setup.server.error")
                    }
                }
            }
        }
    }
}
