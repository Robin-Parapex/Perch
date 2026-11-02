import SwiftUI

@main
struct PerchMain: App {
    @State private var core = CoreServices()

    var body: some Scene {
        WindowGroup {
            AppRoot(core: core)
                .task {
                    // Try the saved profile first (the root waits for this), then ask plex.tv once.
                    let session = core.plexSignIn.session
                    let resumed = await session.resume()
                    core.launch.resumeFinished = true
                    if resumed { await session.refreshFromPlexTV() }
                }
                #if DEBUG
                .task { core.runStorageSelfCheck() }
                #endif
        }
    }
}
