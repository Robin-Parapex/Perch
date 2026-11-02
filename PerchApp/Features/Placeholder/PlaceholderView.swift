import PerchDesign
import SwiftUI

struct PlaceholderView: View {
    #if DEBUG
    @State private var path: [Route] = ProcessInfo.processInfo.arguments.contains("-PerchDesignGallery") ? [.gallery] : []

    private enum Route: Hashable { case gallery }
    #endif

    var body: some View {
        #if DEBUG
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: Route.self) { _ in DesignGallery() }
        }
        #else
        content
        #endif
    }

    private var content: some View {
        ZStack {
            Text("Perch")
                .font(.system(size: 120, weight: .bold))
                .foregroundStyle(PerchColor.textPrimary)
            #if DEBUG
            VStack {
                Spacer()
                Button("Design gallery") { path.append(.gallery) }
                    .buttonStyle(.perchSecondary)
                    .padding(.bottom, 80)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .perchPageBackground()
    }
}
