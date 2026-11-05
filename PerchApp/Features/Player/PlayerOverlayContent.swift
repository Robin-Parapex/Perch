import PerchPlayer
import SwiftUI

/// What the overlay window shows for a session request: the two app-owned overlays in the tvOS 26 player
/// style (PlayerChrome: bottom-left block on AVKit's title line, soft bottom gradient, glass pills, no
/// full-screen scrim). Context goes above the title (still watching: "Next: …"), an explanation below it
/// (couldn't play). The whole overlay, gradient included, fades in; the window fades it out on dismiss.
struct PlayerOverlayContent: View {
    let request: PlayerOverlayRequest
    let session: PlaybackSession
    let playback: PlaybackCoordinator

    static let failedTitle = "Couldn't play this"
    static let stillWatchingTitle = "Are you still watching?"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @FocusState private var primaryFocused: Bool
    /// True once the primary button has held focus; after that a move to another button is the user's.
    @State private var primaryEverFocused = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            PlayerChromeGradient()
            PlayerTitleBlock(title: title, titleID: "player.overlay.title") {
                if let context {
                    Text(context)
                        .font(PlayerChrome.secondaryFont)
                        .foregroundStyle(PlayerChrome.secondaryColor)
                        .accessibilityIdentifier("player.overlay.secondary")
                }
            } below: {
                if let explanation {
                    Text(explanation)
                        .font(PlayerChrome.secondaryFont)
                        .foregroundStyle(PlayerChrome.secondaryColor)
                        .padding(.top, 6)
                        .accessibilityIdentifier("player.overlay.explanation")
                }
                HStack(spacing: PlayerChrome.pillGap) { buttons }
                    .padding(.top, explanation == nil ? PlayerChrome.buttonsGap : PlayerChrome.buttonsGap - 10)
            }
            .offset(y: shown || reduceMotion ? 0 : 24)
        }
        .opacity(shown ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onExitCommand { session.stopWatching() }
        .onAppear {
            primaryFocused = true
            withAnimation(.easeOut(duration: reduceMotion ? 0.25 : PlayerChrome.fadeIn)) { shown = true }
        }
        .onChange(of: primaryFocused) { _, focused in if focused { primaryEverFocused = true } }
        .task {
            // The first request can be lost while the overlay window is still becoming key (seen as an
            // intermittent "Back should have focus" in PlayerUITests); ask again until it lands once.
            for delay in [0.3, 0.6, 1.2] {
                try? await Task.sleep(for: .seconds(delay))
                guard !primaryEverFocused else { return }
                primaryFocused = true
            }
        }
    }

    private var title: String {
        switch request {
        case .stillWatching: Self.stillWatchingTitle
        case .playbackFailed: Self.failedTitle
        }
    }

    /// Above the title: what comes next, for still watching.
    private var context: String? {
        switch request {
        case .stillWatching: playback.nextEpisodeLine ?? session.metadata.subtitle
        case .playbackFailed: nil
        }
    }

    /// Below the title: the app's own failure line (the session never passes raw error text).
    private var explanation: String? {
        switch request {
        case .stillWatching: nil
        case .playbackFailed(let message): message
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch request {
        case .stillWatching:
            Button("Continue Watching") { session.continueWatching() }
                .buttonStyle(PlayerPillButtonStyle())
                .focused($primaryFocused)
                .accessibilityIdentifier("player.stillWatching.continue")
            Button("Stop") { session.stopWatching() }
                .buttonStyle(PlayerPillButtonStyle())
                .accessibilityIdentifier("player.stillWatching.stop")
        case .playbackFailed:
            // Try Again is for parents only (GLOSSARY); the session refuses it too.
            if session.canRetry {
                Button("Try Again") { session.retry() }
                    .buttonStyle(PlayerPillButtonStyle())
                    .focused($primaryFocused)
                    .accessibilityIdentifier("player.failed.retry")
                Button("Back") { session.stopWatching() }
                    .buttonStyle(PlayerPillButtonStyle())
                    .accessibilityIdentifier("player.failed.back")
            } else {
                Button("Back") { session.stopWatching() }
                    .buttonStyle(PlayerPillButtonStyle())
                    .focused($primaryFocused)
                    .accessibilityIdentifier("player.failed.back")
            }
        }
    }
}

#if DEBUG
/// DEBUG: an invisible, accessible status element for the UI tests (AVKit's chrome is not in the
/// accessibility tree), e.g. "playing pos=12 skip=intro upnext=none overlay=none item=2101 items=1 chain=0".
struct PlayerStatusProbe: View {
    let session: PlaybackSession

    var body: some View {
        let skip = session.skipOffer.map { $0.kind == .intro ? "intro" : "credits" } ?? "none"
        let upNext = session.upNextShown == nil ? "none" : "shown"
        let overlay: String
        switch session.overlayRequest {
        case .none: overlay = "none"
        case .stillWatching: overlay = "stillWatching"
        case .playbackFailed: overlay = "failed"
        }
        return Color.white.opacity(0.01)
            .frame(width: 4, height: 4)
            .accessibilityElement()
            .accessibilityLabel(
                "\(session.phase) pos=\(session.positionMs / 1000) skip=\(skip) upnext=\(upNext) overlay=\(overlay) "
                    + "item=\(session.source.ratingKey) items=\(session.itemsStarted) chain=\(session.autoChainCount)"
            )
            .accessibilityIdentifier("player.status")
            .allowsHitTesting(false)
    }
}
#endif
