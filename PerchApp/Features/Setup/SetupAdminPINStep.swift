import PerchCore
import PerchDesign
import SwiftUI

/// Admin PIN: says what it protects, then offers the route that fits the Plex account (SPEC 1a, MODULES PINs).
/// Both routes verify through `AdminPIN` on the full-screen PIN entry. There is no way past this step.
struct SetupAdminPINStep: View {
    let model: SetupFlowModel

    private static let protects =
        "The Admin PIN protects Settings, Integrations, unlocking doors and other household controls. Only a parent can use it."

    var body: some View {
        SetupStepContainer(
            title: title, helper: helper,
            step: model.stepNumber, of: model.stepCount,
            primaryTitle: primaryTitle, primaryAction: { Task { await primary() } },
            backdrop: model.backdropView
        ) {
            VStack(spacing: 24) {
                if let detail {
                    Text(detail)
                        .font(.system(size: PerchFont.bodySize))
                        .foregroundStyle(PerchColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("setup.admin.status")
                }
                if let message = model.adminMessage {
                    Text(message)
                        .font(.system(size: PerchFont.sectionSize, weight: .semibold))
                        .foregroundStyle(PerchColor.textPrimary)
                        .accessibilityIdentifier("setup.admin.message")
                }
                if showsPerchRoute {
                    Button("Set a Perch PIN instead") { Task { await model.startPIN(.verifyPlexForPerch) } }
                        .buttonStyle(.perchSecondary)
                        .accessibilityIdentifier("setup.admin.perch")
                }
            }
        }
    }

    private var confirmed: Bool { model.progress.canFinish }

    private var showsPerchRoute: Bool {
        !confirmed && model.adminSource == .plexOwner
    }

    private var title: String {
        if confirmed { return "Admin PIN confirmed" }
        return model.adminSource == .unavailable ? "Checking your Plex Home" : "Admin PIN"
    }

    private var helper: String? {
        model.adminSource == .unavailable && !confirmed ? nil : Self.protects
    }

    private var detail: String? {
        if confirmed { return nil }
        switch model.adminSource {
        case .plexOwner: return "Your Plex PIN can be the Admin PIN, so there is nothing new to remember."
        case .setupRequired: return "Your Plex account has no PIN, so Perch needs one of its own. Choose 4 digits."
        case .perch: return "Enter the Admin PIN you chose for Perch."
        case .unavailable:
            return model.adminChecking
                ? "Perch is checking whether your Plex account has a PIN."
                : "Perch could not check your Plex account yet."
        }
    }

    private var primaryTitle: String {
        if confirmed { return "Continue" }
        switch model.adminSource {
        case .plexOwner: return "Use your Plex PIN"
        case .setupRequired: return "Set a Perch PIN"
        case .perch: return "Enter the Admin PIN"
        case .unavailable: return "Try again"
        }
    }

    private func primary() async {
        if confirmed {
            await model.advance()
            return
        }
        switch model.adminSource {
        case .plexOwner: await model.startPIN(.usePlexPIN)
        case .setupRequired: await model.startPIN(.newPIN)
        case .perch: await model.startPIN(.enterPerchPIN)
        case .unavailable: await model.retryAdminCheck()
        }
    }
}

/// Full-screen PIN entry for the Admin PIN routes and for profile edits that need a fresh PIN.
struct SetupPINScreen: View {
    @Bindable var model: SetupFlowModel
    let mode: SetupFlowModel.PINMode

    var body: some View {
        PINEntryScreen(
            name: "Admin", prompt: mode.prompt, pin: $model.pin, failures: model.pinFailures,
            isChecking: model.pinChecking, errorMessage: model.pinError,
            onComplete: { entered in Task { await model.submitPIN(entered) } }
        )
        .overlay(alignment: .topTrailing) {
            if !mode.isReauthorise {
                ProgressDots(current: model.stepNumber, total: model.stepCount)
                    .padding(.top, PerchSpacing.topMargin)
                    .padding(.trailing, PerchSpacing.horizontalMargin)
            }
        }
    }
}
