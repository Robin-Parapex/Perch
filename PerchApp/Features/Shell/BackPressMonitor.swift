import SwiftUI
import UIKit

/// Watches every Menu (Back) press in the window without taking it from anyone, and reports two presses within
/// `BackPressTimer.window` as double-tap Back (SPEC 3). A tap recogniser on the window sees the presses of every
/// focused view and presentation in it; it never cancels or delays them, and recognises alongside UIKit's own
/// Back handling, so it never stops Menu reaching the system (MainShell's exit command decides whether Back in the
/// sidebar leaves). Removed when the shell leaves the window, so the root picker keeps the system's Back.
struct BackPressMonitor: UIViewRepresentable {
    let onDoubleBack: @MainActor () -> Void

    func makeUIView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onDoubleBack = onDoubleBack
        return view
    }

    func updateUIView(_ view: MonitorView, context: Context) {
        view.onDoubleBack = onDoubleBack
    }

    final class MonitorView: UIView, UIGestureRecognizerDelegate {
        var onDoubleBack: (@MainActor () -> Void)?
        private var timer = BackPressTimer()
        private weak var installedOn: UIWindow?
        private lazy var recogniser: UITapGestureRecognizer = {
            let tap = UITapGestureRecognizer(target: self, action: #selector(pressed))
            tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
            tap.cancelsTouchesInView = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            return tap
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window !== installedOn {
                installedOn?.removeGestureRecognizer(recogniser)
                installedOn = window
                window?.addGestureRecognizer(recogniser)
            }
        }

        @objc private func pressed() {
            if timer.press(at: ProcessInfo.processInfo.systemUptime) { onDoubleBack?() }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// Two presses within `window` seconds make a double tap; a third starts again.
struct BackPressTimer {
    static let window: TimeInterval = 0.4
    private var last: TimeInterval?

    /// True when this press completes a double tap.
    mutating func press(at time: TimeInterval) -> Bool {
        if let last, time - last <= Self.window {
            self.last = nil
            return true
        }
        last = time
        return false
    }
}
