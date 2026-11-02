import SwiftUI

@main
struct PerchMain: App {
    @State private var core = CoreServices()

    var body: some Scene {
        WindowGroup {
            PlaceholderView(plex: core.plexSignIn)
                .task { await core.plexSignIn.resume() }
                #if DEBUG
                .task { core.runStorageSelfCheck() }
                #endif
        }
    }
}
