import PerchCore
import PerchDesign
import SwiftUI

/// Profiles and roles: select a profile's role to cycle it, its limit to lower it. Limits only go down
/// (back to Plex's own value after U). Every edit goes through the Authoriser with a fresh Admin PIN.
struct SetupProfilesStep: View {
    let model: SetupFlowModel

    var body: some View {
        SetupStepContainer(
            title: "Profiles and roles",
            helper: "Choose each person's role. Ratings can only be made stricter here.",
            step: model.stepNumber, of: model.stepCount,
            primaryTitle: "Continue", primaryAction: { Task { await model.advance() } },
            skipAction: { Task { await model.skip() } },
            backdrop: model.backdropView
        ) {
            VStack(spacing: 16) {
                SetupProfileGrid(
                    rows: model.profileRows,
                    name: { $0.name },
                    roleTitle: { Self.label($0.role) },
                    ratingTitle: { "Up to \($0.ceiling.label)" },
                    onRole: { row in Task { await model.cycleRole(row) } },
                    onRating: { row in Task { await model.lowerLimit(row) } }
                )
                if let message = model.profileMessage {
                    Text(message)
                        .font(.system(size: PerchFont.bodySize))
                        .foregroundStyle(PerchColor.textBody)
                        .accessibilityIdentifier("setup.profiles.message")
                }
            }
        }
    }

    private static func label(_ role: Role) -> String {
        switch role {
        case .parent: "Parent"
        case .teen: "Teen"
        case .kid: "Kid"
        case .topShelf: "Top Shelf"
        }
    }
}
