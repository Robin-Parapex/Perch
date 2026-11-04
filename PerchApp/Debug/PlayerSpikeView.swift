#if DEBUG
import OSLog
import PerchCore
import PerchPlayer
import PerchPlex
import SwiftUI
import UIKit

/// WP-07 player harness, DEBUG only. `-PerchPlayerSpike local` plays the bundled 60 s clip
/// (PlayerSpikeClip.mp4, excluded from Release in project.yml) through the real PlaybackSession and
/// NativeEngine, with fake markers (intro 5 to 15 s, final credits from 45 s), the same clip as the
/// next item and a no-op reporter. `-PerchPlayerSpike <ratingKey> directplay|transcode` plays that title
/// from the signed-in server (token in AVURLAsset headers), logging only status and playback-log entries
/// (subsystem com.robrolabs.perch, category spike).
struct PlayerSpikeView: View {
    let core: CoreServices

    enum Mode: String { case passive, focus, upNext }

    struct Launch: Identifiable {
        let id = UUID()
        let mode: Mode
        let session: PlaybackSession
        let engine: NativeEngine
    }

    @State private var launch: Launch?
    @State private var exits = 0
    @State private var liveStarted = false

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-PerchPlayerSpike") }

    /// "local", "list", or the rating key plus "directplay" / "transcode".
    private static var arguments: [String] {
        let all = ProcessInfo.processInfo.arguments
        guard let index = all.firstIndex(of: "-PerchPlayerSpike") else { return [] }
        return Array(all[(index + 1)...].prefix(2))
    }

    var body: some View {
        VStack(spacing: 40) {
            Text("Player spike").font(.title2)
            Text("Exits: \(exits)").accessibilityIdentifier("spike.exits")
            HStack(spacing: 40) {
                Button("Other") {}.accessibilityIdentifier("spike.other")
                Button("Play, passive overlay") { play(.passive) }.accessibilityIdentifier("spike.play.passive")
                Button("Play, focus overlay") { play(.focus) }.accessibilityIdentifier("spike.play.focus")
                Button("Play from 0:40, up next") { play(.upNext) }.accessibilityIdentifier("spike.play.upnext")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullScreenCover(item: $launch, onDismiss: { exits += 1 }) { launch in
            PlayerSpikeRepresentable(launch: launch, onExit: { self.launch = nil })
                .ignoresSafeArea()
        }
        .task(id: core.plexSignIn.snapshot.state) { await startLiveIfAsked() }
    }

    private func play(_ mode: Mode) {
        guard let source = SpikeClip.source(startMs: mode == .upNext ? 40_000 : 0) else {
            PlayerSpikeLog.log.error("Spike clip missing from the bundle")
            return
        }
        let engine = NativeEngine()
        let session = PlaybackSession(
            engine: engine, source: source, metadata: SpikeClip.metadata,
            reporter: NoopReporter(sessionID: source.sessionID), log: PlayerSpikeLog.entry,
            nextItem: { SpikeClip.proposal },
            resolveNext: { _ in
                guard let next = SpikeClip.source(startMs: 0) else { throw SpikeError.clipMissing }
                return PlaybackItem(
                    source: next, metadata: SpikeClip.metadata, reporter: NoopReporter(sessionID: next.sessionID))
            },
            onTranscodeStop: { _ in }, canRetry: true)
        launch = Launch(mode: mode, session: session, engine: engine)
    }

    /// `-PerchPlayerSpike list`: logs rating key and container of recently added items, to pick test titles.
    private func listIfAsked() async {
        guard Self.arguments.first == "list", !liveStarted, case .ready = core.plexSignIn.snapshot.state else { return }
        liveStarted = true
        do {
            let rows = try await core.library.homeRows()
            for item in (rows.recentlyAdded.items + rows.continueWatching.items).prefix(25) {
                let detail = try? await core.library.detail(ratingKey: item.id)
                let container = detail?.versions.first?.parts.first?.container ?? "-"
                let codecs = "\(detail?.versions.first?.videoCodec ?? "-")/\(detail?.versions.first?.audioCodec ?? "-")"
                PlayerSpikeLog.log.notice(
                    "item \(item.id, privacy: .public) container=\(container, privacy: .public) codecs=\(codecs, privacy: .public) title=\(item.title, privacy: .public)")
            }
        } catch {
            PlayerSpikeLog.log.error("list failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func startLiveIfAsked() async {
        await listIfAsked()
        let args = Self.arguments
        guard !liveStarted, args.count == 2, args[0] != "local",
            ["directplay", "transcode"].contains(args[1]),
            case .ready = core.plexSignIn.snapshot.state
        else { return }
        liveStarted = true
        do {
            // The decision table picks the method; the mode argument is kept for the old launch lines.
            let source = try await core.library.playbackSource(for: args[0], startMs: nil, subtitleStreamID: nil)
            PlayerSpikeLog.log.notice(
                "live method=\(source.decision.method.rawValue, privacy: .public) path=\(source.url.path(percentEncoded: false), privacy: .public) reasons=\(source.decision.reasons.joined(separator: "; "), privacy: .public)")
            let library = core.library
            let engine = NativeEngine()
            // No-op reporter: the harness does not move the server's resume point.
            let session = PlaybackSession(
                engine: engine, source: source, metadata: PlayerItemMetadata(title: source.title),
                reporter: NoopReporter(sessionID: source.sessionID), log: PlayerSpikeLog.entry,
                nextItem: { nil }, resolveNext: { _ in throw SpikeError.noNext },
                onTranscodeStop: { id in
                    await library.stopTranscode(sessionID: id)
                    PlayerSpikeLog.log.notice("transcode stop sent")
                }, canRetry: true)
            launch = Launch(mode: .passive, session: session, engine: engine)
        } catch {
            PlayerSpikeLog.log.error("live request failed: \(String(describing: error), privacy: .public)")
        }
    }
}

enum SpikeError: Error { case clipMissing, noNext }

/// The bundled clip as a PlaybackSource with fake markers.
enum SpikeClip {
    static func source(startMs: Int) -> PlaybackSource? {
        guard let url = Bundle.main.url(forResource: "PlayerSpikeClip", withExtension: "mp4") else { return nil }
        return PlaybackSource(
            ratingKey: "spike-clip", title: "Player spike clip", url: url,
            decision: PlaybackDecision(method: .directPlay, reasons: ["Local test clip"]),
            startMs: startMs, durationMs: 60_000, sessionID: UUID().uuidString,
            markers: [
                MediaMarker(kind: .intro, startMs: 5_000, endMs: 15_000),
                MediaMarker(kind: .credits, startMs: 45_000, endMs: 60_000, isFinal: true),
            ])
    }

    static let metadata = PlayerItemMetadata(
        title: "Player spike clip", subtitle: "Test pattern", summary: "Sixty seconds of test pattern.")

    @MainActor static var proposal: UpNextProposal {
        UpNextProposal(
            title: "Player spike clip, again", subtitle: "The same sixty seconds",
            previewImageData: UIImage(systemName: "play.rectangle.fill")?.pngData(), ratingKey: "spike-clip")
    }
}

struct NoopReporter: PlaybackReporting {
    let sessionID: String
    func report(_ state: PlaybackState, positionMs: Int) async {}
    func stop(positionMs: Int) async {}
}

/// Status logging: no URL query, no headers, no token.
enum PlayerSpikeLog {
    static let log = Logger(subsystem: "com.robrolabs.perch", category: "spike")

    @Sendable static func entry(_ entry: PlaybackLogEntry) async {
        let latency = entry.startLatencyMs.map { "\($0)" } ?? "-"
        let position = entry.positionMs.map { "\($0)" } ?? "-"
        log.notice(
            "playback log \(entry.outcome.rawValue, privacy: .public) engine=\(entry.engine, privacy: .public) method=\(entry.method?.rawValue ?? "unknown", privacy: .public) key=\(entry.ratingKey, privacy: .public) positionMs=\(position, privacy: .public) startLatencyMs=\(latency, privacy: .public) error=\(entry.error ?? "-", privacy: .public)")
    }
}

/// Counts actions on the harness's own focus overlay.
@MainActor
final class PlayerSpikeState {
    var actions = 0
}

struct PlayerSpikeRepresentable: UIViewControllerRepresentable {
    let launch: PlayerSpikeView.Launch
    let onExit: () -> Void

    func makeUIViewController(context: Context) -> PlayerContainerViewController {
        let session = launch.session
        let engine = launch.engine
        let container = PlayerContainerViewController(session: session)
        let state = PlayerSpikeState()
        let mode = launch.mode
        container.onExit = onExit
        // The app's styled overlays come later; plain text here.
        container.overlayContent = { request in AnyView(SpikeRequestOverlay(request: request, session: session)) }
        container.onOverlayHostReady = { host in
            switch mode {
            case .passive:
                host.show(PassiveSpikeOverlay(), mode: .passive)
            case .focus:
                Task { @MainActor [weak host] in
                    try? await Task.sleep(for: .seconds(3))
                    guard let host else { return }
                    host.show(
                        FocusSpikeOverlay(onAction: { state.actions += 1 }, onClose: { [weak host] in host?.dismiss() }),
                        mode: .focusTaking)
                }
            case .upNext:
                break
            }
        }
        // Status label for the UI tests (AVKit's chrome is not in the accessibility tree).
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 24, weight: .regular)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        label.accessibilityIdentifier = "spike.status"
        label.translatesAutoresizingMaskIntoConstraints = false
        container.loadViewIfNeeded()
        container.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.view.leadingAnchor, constant: 80),
            label.topAnchor.constraint(equalTo: container.view.topAnchor, constant: 60),
        ])
        Task { @MainActor [weak container, weak label] in
            while let container, let label {
                let playing = session.phase == .playing ? "playing" : "paused"
                let overlay = container.overlays?.isShowing == true ? "shown" : "none"
                let key = container.overlays?.isKey == true ? "overlay" : "main"
                let actions = state.actions + session.skipsTaken
                let skip = engine.isShowingSkip ? (session.skipOffer?.kind == .credits ? "credits" : "intro") : "none"
                let upNext = engine.isShowingUpNext ? "shown" : "none"
                let text =
                    "\(playing) overlay=\(overlay) key=\(key) actions=\(actions) item=\(session.itemsStarted) "
                    + "skip=\(skip) upnext=\(upNext) advances=\(session.automaticAdvances)"
                if label.text != text {
                    label.text = text
                    label.accessibilityLabel = text
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        return container
    }

    func updateUIViewController(_ controller: PlayerContainerViewController, context: Context) {}
}

/// Plain stand-ins for the app's real "still watching" and failure overlays.
struct SpikeRequestOverlay: View {
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

/// Like PerchCornerPill, but in the overlay window: visible, never focused.
struct PassiveSpikeOverlay: View {
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text("Passive notice")
                    .padding(24)
                    .background(.regularMaterial, in: Capsule())
                    .accessibilityIdentifier("overlay.passive")
            }
            Spacer()
        }
        .padding(80)
    }
}

/// A Skip Intro pill that takes focus. Menu closes it and focus goes back to the player.
struct FocusSpikeOverlay: View {
    let onAction: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button("Skip Intro", action: onAction).accessibilityIdentifier("overlay.skip")
            }
        }
        .padding(80)
        .onExitCommand(perform: onClose)
    }
}
#endif
