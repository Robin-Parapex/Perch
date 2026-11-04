import OSLog
import SwiftUI
import UIKit

/// A second `UIWindow` on the player's scene, one level above the app window, hosting SwiftUI overlays
/// (Skip Intro, next-episode countdown, "Are you still watching?", later the doorbell).
/// - Passive: visible, not key, no user interaction, so remote input and focus stay with the player.
/// - Focus-taking: the window is made key and focus moves into it; `dismiss()` fades it out, then hides it,
///   makes the app window key again and asks the player container for a focus update.
@MainActor
public final class OverlayWindowHost {
    public enum Mode: Sendable { case passive, focusTaking }

    private let window: UIWindow
    private weak var mainWindow: UIWindow?
    private weak var focusReturn: UIViewController?
    public private(set) var mode: Mode?
    /// Bumped by every show, dismiss and tear-down, so a fade that finishes late never hides newer content.
    private var generation = 0
    /// How long the overlay fades out before the window hides.
    public static let fadeOutDuration: TimeInterval = 0.25

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
        generation += 1
        let host = UIHostingController(rootView: AnyView(content))
        host.view.backgroundColor = .clear
        window.layer.removeAllAnimations()
        window.alpha = 1
        window.transform = .identity
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

    /// Fades the overlay out (a plain cross-fade with Reduce Motion, else with a short drop), then hides it
    /// and hands key and focus back to the player; `completion` runs after the hand-back. Input is off
    /// during the fade so a second press cannot act twice.
    public func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard !window.isHidden else {
            completion?()
            return
        }
        generation += 1
        let token = generation
        window.isUserInteractionEnabled = false
        guard animated else {
            finishDismiss(token, completion: completion)
            return
        }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        UIView.animate(
            withDuration: Self.fadeOutDuration, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]
        ) { [window] in
            window.alpha = 0
            if !reduceMotion { window.transform = CGAffineTransform(translationX: 0, y: 24) }
        } completion: { [weak self] _ in
            self?.finishDismiss(token, completion: completion)
        }
    }

    private func finishDismiss(_ token: Int, completion: (() -> Void)?) {
        // A newer show or tear-down took over while fading: leave its state alone.
        guard token == generation else {
            completion?()
            return
        }
        window.isHidden = true
        window.rootViewController = nil
        window.alpha = 1
        window.transform = .identity
        mode = nil
        mainWindow?.makeKey()
        focusReturn?.setNeedsFocusUpdate()
        focusReturn?.updateFocusIfNeeded()
        Logger.player.notice(
            "Overlay dismissed; app window key=\(self.mainWindow?.isKeyWindow ?? false, privacy: .public)")
        completion?()
    }

    /// The player is going away: hide without touching focus (the presenter restores it).
    func tearDown() {
        generation += 1
        window.layer.removeAllAnimations()
        window.alpha = 1
        window.transform = .identity
        window.isHidden = true
        window.rootViewController = nil
        mode = nil
        if let mainWindow, !mainWindow.isKeyWindow { mainWindow.makeKey() }
    }
}
