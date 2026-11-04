import PerchDesign
import PerchPlayer
import SwiftUI

/// What the overlay window shows for a session request: the two app-owned overlays, in the tvOS 26 player
/// style (bottom-left block over a soft bottom gradient, glass pills, no full-screen scrim).
struct PlayerOverlayContent: View {
    /// AVKit's title and transport bar start at the tvOS title-safe edge: 80 pt from the screen edge on a
    /// 1920 pt screen (measured on a 3840 px capture: chrome at x = 160 px). Our block uses the same line,
    /// counted from the screen edge (the window's safe area would add a second 80 pt).
    static let chromeLeadingInset: CGFloat = 80

    let request: PlayerOverlayRequest
    let session: PlaybackSession
    let playback: PlaybackCoordinator

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @FocusState private var primaryFocused: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.55), .black.opacity(0.8)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 560)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 10) {
                if let line = secondaryLine {
                    Text(line)
                        .font(.system(size: PerchFont.bodySize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .accessibilityIdentifier("player.overlay.secondary")
                }
                Text(title)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("player.overlay.title")
                HStack(spacing: PerchSpacing.itemGap) { buttons }
                    .padding(.top, 26)
            }
            .padding(.leading, Self.chromeLeadingInset)
            .padding(.bottom, 90)
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : PerchMotion.panelOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .horizontal)
        .onExitCommand { session.stopWatching() }
        .onAppear {
            primaryFocused = true
            withAnimation(reduceMotion ? .easeOut(duration: PerchMotion.crossfadeDuration) : .easeOut(duration: PerchMotion.panelDuration)) {
                shown = true
            }
        }
    }

    private var title: String {
        switch request {
        case .stillWatching: "Are you still watching?"
        case .playbackFailed: "Couldn't play this"
        }
    }

    private var secondaryLine: String? {
        switch request {
        case .stillWatching: playback.nextEpisodeLine ?? session.metadata.subtitle
        case .playbackFailed(let message): message
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch request {
        case .stillWatching:
            Button("Continue watching") { session.continueWatching() }
                .buttonStyle(.perchSecondary)
                .focused($primaryFocused)
                .accessibilityLabel("Continue watching")
                .accessibilityIdentifier("player.stillWatching.continue")
            Button("Stop") { session.stopWatching() }
                .buttonStyle(.perchSecondary)
                .accessibilityLabel("Stop")
                .accessibilityIdentifier("player.stillWatching.stop")
        case .playbackFailed:
            Button("Try again") { session.retry() }
                .buttonStyle(.perchSecondary)
                .focused($primaryFocused)
                .accessibilityLabel("Try again")
                .accessibilityIdentifier("player.failed.retry")
            Button("Back") { session.stopWatching() }
                .buttonStyle(.perchSecondary)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("player.failed.back")
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
