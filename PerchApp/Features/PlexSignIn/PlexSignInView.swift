import PerchDesign
import SwiftUI

/// The two ways to sign in. A signed-in session also offers the profiles screen.
struct PlexSignInView: View {
    let model: PlexSignInModel
    @Binding var path: NavigationPath

    var body: some View {
        VStack(alignment: .leading, spacing: PerchSpacing.rowGap) {
            Text("Connect your library")
                .font(.system(size: PerchFont.heroSize, weight: .bold))
                .foregroundStyle(PerchColor.textPrimary)
                .accessibilityIdentifier("plexSignIn.title")
            VStack(alignment: .leading, spacing: PerchSpacing.itemGap) {
                Button("Sign in with a code") { path.append(PlexRoute.code) }
                    .buttonStyle(.perchPrimary)
                    .accessibilityIdentifier("plexSignIn.code")
                Button("Enter a server address") { path.append(PlexRoute.address) }
                    .buttonStyle(.perchSecondary)
                    .accessibilityIdentifier("plexSignIn.address")
                if model.isReady {
                    Button("Profiles") { path.append(PlexRoute.profiles) }
                        .buttonStyle(.perchSecondary)
                        .accessibilityIdentifier("plexSignIn.profiles")
                }
            }
            ConnectionNotice(model: model) { Task { await model.resume() } }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .perchPageMargins()
        .perchPageBackground()
    }
}
