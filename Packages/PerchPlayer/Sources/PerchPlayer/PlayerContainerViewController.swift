import OSLog
import SwiftUI
import UIKit

/// Our full-screen player container: the engine's view controller embedded as a child, never presented
/// modally (docs/ARCHITECTURE.md, DECISIONS 2026-10-30), so the overlay window above it can take and
/// hand back focus. Menu that the engine does not use itself (AVKit's transport bar hidden) ends here
/// and exits the session. Starts the session once it is in a window (display criteria need the window).
@MainActor
public final class PlayerContainerViewController: UIViewController {
    public let session: PlaybackSession
    /// Called once when the session has finished (Back, end of playback, "stop watching").
    public var onExit: (() -> Void)?
    /// Called once the container is in a window and its overlay window exists.
    public var onOverlayHostReady: ((OverlayWindowHost) -> Void)?
    /// Renders the session's overlay requests (the app supplies PerchDesign views).
    public var overlayContent: ((PlayerOverlayRequest) -> AnyView)?
    public private(set) var overlays: OverlayWindowHost?
    private var started = false

    public init(session: PlaybackSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var engineController: UIViewController { session.engine.viewController }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let child = engineController
        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        child.didMove(toParent: self)
        session.onFinished = { [weak self] in self?.onExit?() }
        session.onOverlayRequestChange = { [weak self] request in self?.render(request) }
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if overlays == nil, let window = view.window, let scene = window.windowScene {
            let host = OverlayWindowHost(scene: scene, mainWindow: window, focusReturn: self)
            overlays = host
            onOverlayHostReady?(host)
        }
        if !started {
            started = true
            session.start()
        }
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        overlays?.tearDown()
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Dismissed some other way (a doorbell route, the app backgrounding the cover): still stop cleanly.
        if session.phase != .finished {
            let session = session
            Task { await session.exit() }
        }
    }

    /// Focus always goes back into the engine (transport bar, info panel), never to our own views.
    override public var preferredFocusEnvironments: [UIFocusEnvironment] { [engineController] }

    private func render(_ request: PlayerOverlayRequest?) {
        guard let overlays else { return }
        if let request, let content = overlayContent?(request) {
            overlays.show(content, mode: .focusTaking)
        } else if overlays.mode == .focusTaking {
            overlays.dismiss()
        }
    }

    // Menu: AVKit consumes it while its transport bar or info panel is up; otherwise it travels up the
    // responder chain to here. Swallow both phases so UIKit's default (dismiss or leave) never runs.
    override public func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .menu }) { return }
        super.pressesBegan(presses, with: event)
    }

    override public func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .menu }) {
            Logger.player.notice("Menu reached the player container: exit")
            let session = session
            Task { await session.exit() }
            return
        }
        super.pressesEnded(presses, with: event)
    }
}

/// The player for a SwiftUI `.fullScreenCover`: hosts the session's engine and renders its overlay
/// requests with the app's own views in the overlay window.
public struct PlayerContainerView<Overlay: View>: UIViewControllerRepresentable {
    let session: PlaybackSession
    let onExit: () -> Void
    let onOverlayHostReady: ((OverlayWindowHost) -> Void)?
    let overlay: (PlayerOverlayRequest) -> Overlay

    public init(
        session: PlaybackSession, onExit: @escaping () -> Void,
        onOverlayHostReady: ((OverlayWindowHost) -> Void)? = nil,
        @ViewBuilder overlay: @escaping (PlayerOverlayRequest) -> Overlay
    ) {
        self.session = session
        self.onExit = onExit
        self.onOverlayHostReady = onOverlayHostReady
        self.overlay = overlay
    }

    public func makeUIViewController(context: Context) -> PlayerContainerViewController {
        let container = PlayerContainerViewController(session: session)
        container.onExit = onExit
        container.onOverlayHostReady = onOverlayHostReady
        let overlay = overlay
        container.overlayContent = { AnyView(overlay($0)) }
        return container
    }

    public func updateUIViewController(_ controller: PlayerContainerViewController, context: Context) {}
}

extension Logger {
    static let player = Logger(subsystem: "com.robrolabs.perch", category: "player")
}
