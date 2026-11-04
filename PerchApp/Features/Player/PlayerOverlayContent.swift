import PerchPlayer
import SwiftUI

/// What the overlay window shows for a session request. A placeholder until the styled views land.
struct PlayerOverlayContent: View {
    let request: PlayerOverlayRequest
    let session: PlaybackSession

    var body: some View {
        VStack(spacing: 30) {
            switch request {
            case .stillWatching:
                Text("Are you still watching?").font(.title2)
                HStack(spacing: 40) {
                    Button("Continue") { session.continueWatching() }.accessibilityIdentifier("overlay.continue")
                    Button("Stop") { session.stopWatching() }.accessibilityIdentifier("overlay.stop")
                }
            case .playbackFailed(let message):
                Text("This didn't play").font(.title2)
                Text(message).font(.caption)
                HStack(spacing: 40) {
                    Button("Try again") { session.retry() }.accessibilityIdentifier("overlay.retry")
                    Button("Close") { session.stopWatching() }.accessibilityIdentifier("overlay.close")
                }
            }
        }
        .padding(60)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30))
    }
}
