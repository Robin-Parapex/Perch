import PerchCore
import PerchDesign
import SwiftUI

/// Profiles and roles: select a profile's role to cycle it, its limit to lower it. Limits only go down
/// (back to Plex's own value after U). Every edit goes through the Authoriser with a fresh Admin PIN.
struct SetupProfilesStep: View {
    let model: SetupFlowModel
    @Environment(\.perchStyle) private var style

    var body: some View {
        SetupStepContainer(
            title: "Profiles and roles",
            helper: "Roles decide what each person can do. Limits can only be lowered here. Plex sets where they start.",
            step: model.stepNumber, of: model.stepCount,
            primaryTitle: "Continue", primaryAction: { Task { await model.advance() } },
            skipAction: { Task { await model.skip() } },
            backdrop: model.backdropView
        ) {
            VStack(spacing: 16) {
                ForEach(model.profileRows) { row in
                    HStack(spacing: 24) {
                        ProfileAvatarImage(name: row.name, size: 72)
                        Text(row.name)
                            .font(PerchFont.body(style))
                            .foregroundStyle(PerchColor.textPrimary)
                            .lineLimit(1)
                            .frame(width: 260, alignment: .leading)
                        Button(Self.label(row.role)) { Task { await model.cycleRole(row) } }
                            .buttonStyle(.perchSecondary)
                            .disabled(row.isOwner)
                            .accessibilityIdentifier("setup.profile.\(row.id.rawValue).role")
                        Button("Up to \(row.ceiling.label)") { Task { await model.lowerLimit(row) } }
                            .buttonStyle(.perchSecondary)
                            .accessibilityIdentifier("setup.profile.\(row.id.rawValue).limit")
                    }
                }
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
