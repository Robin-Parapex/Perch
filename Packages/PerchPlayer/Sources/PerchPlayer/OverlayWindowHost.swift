import OSLog
import SwiftUI
import UIKit

/// A second `UIWindow` on the player's scene, one level above the app window, hosting SwiftUI overlays
/// (Skip Intro, next-episode countdown, "Are you still watching?", later the doorbell).
/// - Passive: visible, not key, no user interaction, so remote input and focus stay with the player.
/// - Focus-taking: the window is made key and focus moves into it; `dismiss()` hides it, makes the app
///   window key again and asks the player container for a focus update.
@MainActor
public final class OverlayWindowHost {
    public enum Mode: Sendable { case passive, focusTaking }

    private let window: UIWindow
    private weak var mainWindow: UIWindow?
    private weak var focusReturn: UIViewController?
    public private(set) var mode: Mode?

    public var isKey: Bool { window.isKeyWindow }
    public var isShowing: Bool { !window.isHidden }

    public init(scene: UIWindowScene, mainWindow: UIWindow, focusReturn: UIViewController) {
        window = UIWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        window.backgroundColor = .clear
        window.isHidden = true
        self.mainWindow = mainWindow
        self.focusReturn = focusReturn
    }

    public func show(_ content: some View, mode: Mode) {
        let host = UIHostingController(rootView: AnyView(content))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isUserInteractionEnabled = mode == .focusTaking
        window.isHidden = false
        self.mode = mode
        if mode == .focusTaking {
            window.makeKey()
            host.setNeedsFocusUpdate()
            host.updateFocusIfNeeded()
            // AVKit reacts to its controls being hidden on the next turn of the run loop; take key and
            // focus again after that so the overlay keeps them.
            DispatchQueue.main.async { [weak self, weak host] in
                guard let self, let host, self.mode == .focusTaking, self.window.rootViewController === host else { return }
                if !self.window.isKeyWindow { self.window.makeKey() }
                host.setNeedsFocusUpdate()
                host.updateFocusIfNeeded()
            }
        }
        Logger.player.notice(
            "Overlay shown mode=\(String(describing: mode), privacy: .public) key=\(self.window.isKeyWindow, privacy: .public)")
    }

    /// Hides the overlay and hands key and focus back to the player.
    public func dismiss() {
        guard !window.isHidden else { return }
        window.isHidden = true
        window.rootViewController = nil
        mode = nil
        mainWindow?.makeKey()
        focusReturn?.setNeedsFocusUpdate()
        focusReturn?.updateFocusIfNeeded()
        Logger.player.notice(
            "Overlay dismissed; app window key=\(self.mainWindow?.isKeyWindow ?? false, privacy: .public)")
    }

    /// The player is going away: hide without touching focus (the presenter restores it).
    func tearDown() {
        window.isHidden = true
        window.rootViewController = nil
        mode = nil
        if let mainWindow, !mainWindow.isKeyWindow { mainWindow.makeKey() }
    }
}
