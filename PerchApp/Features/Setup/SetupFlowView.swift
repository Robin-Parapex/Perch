import PerchDesign
import SwiftUI

/// The first-run wizard (and its re-run). Owns a `SetupFlowModel`; the model holds the step logic.
/// Steps crossfade and slide with the direction of travel (after Dusk's ContentView routing, MIT).
struct SetupFlowView: View {
    @State private var model: SetupFlowModel

    init(core: CoreServices, isRerun: Bool, onFinish: @escaping () -> Void) {
        _model = State(initialValue: SetupFlowModel(core: core, isRerun: isRerun, onFinish: onFinish))
    }

    var body: some View {
        ZStack {
            PerchColor.base.ignoresSafeArea()
            screen
                .id(model.screenID)
                .perchStepTransition(model.direction)
        }
        // Nil at Welcome on a first run, so Back leaves the app instead of being swallowed.
        .onExitCommand(perform: model.interceptsBack ? { Task { await model.back() } } : nil)
        .task(id: model.showsBackdrop) { await model.loadBackdropIfNeeded() }
    }

    @ViewBuilder
    private var screen: some View {
        if let mode = model.pinMode {
            SetupPINScreen(model: model, mode: mode)
        } else {
            switch model.progress.current {
            case .welcome: SetupWelcomeStep(model: model)
            case .connectPlex: SetupConnectStep(model: model)
            case .chooseServer: SetupServerStep(model: model)
            case .adminPIN: SetupAdminPINStep(model: model)
            case .profiles: SetupProfilesStep(model: model)
            case .addLater: SetupAddLaterStep(model: model)
            case .done: SetupDoneStep(model: model)
            }
        }
    }
}

struct SetupWelcomeStep: View {
    let model: SetupFlowModel

    var body: some View {
        SetupStepContainer(
            title: "Welcome to Perch",
            helper: "Setup takes a few minutes. You will connect Plex, choose a PIN for the grown-up controls, and check who is in your home.",
            titleSize: .hero, step: model.stepNumber, of: model.stepCount,
            primaryTitle: "Get started", primaryAction: { Task { await model.advance() } }
        ) {}
    }
}

struct SetupDoneStep: View {
    let model: SetupFlowModel

    var body: some View {
        SetupStepContainer(
            title: "You're all set",
            helper: "Perch is ready for the whole household.",
            titleSize: .hero, step: model.stepNumber, of: model.stepCount,
            primaryTitle: "Choose who's watching", primaryAction: { model.finish() },
            backdrop: model.backdropView
        ) {}
    }
}

struct SetupAddLaterStep: View {
    let model: SetupFlowModel
    @Environment(\.perchStyle) private var style

    var body: some View {
        SetupStepContainer(
            title: "More to add later",
            helper: "These connect from Settings when they are ready. Nothing here is needed now.",
            step: model.stepNumber, of: model.stepCount,
            primaryTitle: "Continue", primaryAction: { Task { await model.advance() } },
            skipAction: { Task { await model.skip() } },
            backdrop: model.backdropView
        ) {
            VStack(spacing: 14) {
                ForEach(model.addLater.entries()) { entry in
                    HStack {
                        Text(entry.title).foregroundStyle(PerchColor.textPrimary)
                        Spacer()
                        Text(entry.detail).foregroundStyle(PerchColor.textSecondary)
                    }
                    .font(PerchFont.body(style))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("setup.addLater.\(entry.moduleID.rawValue)")
                }
            }
            .frame(width: 620)
        }
    }
}
