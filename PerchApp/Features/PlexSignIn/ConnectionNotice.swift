import PerchDesign
import SwiftUI

/// The two unreachable states (WP-04 decision 11). Nothing here names a backend service.
struct ConnectionNotice: View {
    let model: PlexSignInModel
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PerchSpacing.itemGap) {
            if model.serverUnreachable {
                Text("Can't reach your library right now")
                    .font(.system(size: PerchFont.bodySize))
                    .foregroundStyle(PerchColor.textBody)
                    .accessibilityIdentifier("plexNotice.library")
                Button("Try again", action: retry)
                    .buttonStyle(.perchSecondary)
                    .accessibilityIdentifier("plexNotice.retry")
            }
            if !model.plexTVReachable {
                Text("Profile PINs can't be checked right now")
                    .font(.system(size: PerchFont.bodySize))
                    .foregroundStyle(PerchColor.textSecondary)
                    .accessibilityIdentifier("plexNotice.pins")
            }
        }
    }
}
