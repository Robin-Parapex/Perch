import PerchDesign
import SwiftUI

struct PlaceholderView: View {
    let plex: PlexSignInModel
    #if DEBUG
    @State private var path = PlaceholderView.initialPath()

    private enum Route: Hashable { case gallery }

    private static func initialPath() -> NavigationPath {
        let arguments = ProcessInfo.processInfo.arguments
        var path = NavigationPath()
        if arguments.contains("-PerchDesignGallery") { path.append(Route.gallery) }
        if arguments.contains("-PerchPlexSignIn") { path.append(PlexRoute.signIn) }
        return path
    }
    #endif

    var body: some View {
        #if DEBUG
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: Route.self) { _ in DesignGallery() }
                .navigationDestination(for: PlexRoute.self) { route in destination(route) }
        }
        #else
        content
        #endif
    }

    #if DEBUG
    @ViewBuilder
    private func destination(_ route: PlexRoute) -> some View {
        switch route {
        case .signIn: PlexSignInView(model: plex, path: $path)
        case .code: PlexLinkCodeView(model: plex, path: $path)
        case .address: PlexAddressView(model: plex, path: $path)
        case .servers: PlexServerPickerView(model: plex, path: $path)
        case .connected: PlexConnectedView(model: plex, path: $path)
        case .profiles: PlexProfilesDebugView(model: plex, path: $path)
        }
    }
    #endif

    private var content: some View {
        ZStack {
            Text("Perch")
                .font(.system(size: 120, weight: .bold))
                .foregroundStyle(PerchColor.textPrimary)
            #if DEBUG
            VStack {
                Spacer()
                HStack(spacing: 40) {
                    Button("Design gallery") { path.append(Route.gallery) }
                        .buttonStyle(.perchSecondary)
                        .accessibilityIdentifier("placeholder.gallery")
                    Button("Plex sign-in") { path.append(PlexRoute.signIn) }
                        .buttonStyle(.perchSecondary)
                        .accessibilityIdentifier("placeholder.plexSignIn")
                }
                .padding(.bottom, 80)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .perchPageBackground()
    }
}
