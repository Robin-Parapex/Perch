import SwiftUI

@main
struct PerchMain: App {
    @State private var core = CoreServices()

    var body: some Scene {
        WindowGroup {
            PlaceholderView()
                #if DEBUG
                .task { core.runStorageSelfCheck() }
                #endif
        }
    }
}
