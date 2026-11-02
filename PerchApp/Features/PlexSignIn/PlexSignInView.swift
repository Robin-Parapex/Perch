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
            // Equal-width choices share one leading edge, also while the focused one scales up.
            VStack(alignment: .leading, spacing: PerchSpacing.itemGap) {
                Button { path.append(PlexRoute.code) } label: { choice("Sign in with a code") }
                    .buttonStyle(.perchPrimary)
                    .accessibilityIdentifier("plexSignIn.code")
                Button { path.append(PlexRoute.address) } label: { choice("Enter a server address") }
                    .buttonStyle(.perchSecondary)
                    .accessibilityIdentifier("plexSignIn.address")
                if model.isReady {
                    Button { path.append(PlexRoute.profiles) } label: { choice("Profiles") }
                        .buttonStyle(.perchSecondary)
                        .accessibilityIdentifier("plexSignIn.profiles")
                }
            }
            ConnectionNotice(model: model) { Task { await model.resume() } }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .perchPageMargins()
        .ignoresSafeArea()
        .perchPageBackground()
    }

    private func choice(_ title: String) -> some View {
        Text(title).frame(width: 520)
    }
}
