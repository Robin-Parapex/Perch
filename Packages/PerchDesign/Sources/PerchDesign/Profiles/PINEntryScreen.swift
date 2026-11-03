import SwiftUI

/// "Enter the PIN for Sam": one vertically centred column with the avatar, name, status line, PIN dots and keypad,
/// over the blurred `backdrop` art when given. While `isChecking` the keypad is dimmed and a small spinner shows;
/// `errorMessage` is plain words. While `lockedUntil` is in the future the keypad is dimmed and disabled, a live
/// "Try again in 0:45" line shows and an OK button (calling `onBack`) takes focus.
public struct PINEntryScreen: View {
    private let name: String
    private let image: AnyView?
    private let backdrop: AnyView?
    private let prompt: String
    private let errorMessage: String?
    private let isChecking: Bool
    private let failures: Int
    private let lockedUntil: Date?
    private let onBack: (() -> Void)?
    @Binding private var pin: String
    private let onComplete: (String) -> Void
    @Environment(\.perchStyle) private var style
    @FocusState private var okFocused: Bool

    /// Bump `failures` after a wrong PIN to shake and clear; clear `pin` yourself when you reset.
    public init(
        name: String, image: (any View)? = nil, backdrop: (any View)? = nil, prompt: String = "Enter your PIN",
        pin: Binding<String>, failures: Int = 0, isChecking: Bool = false, errorMessage: String? = nil,
        lockedUntil: Date? = nil, onBack: (() -> Void)? = nil,
        onComplete: @escaping (String) -> Void
    ) {
        self.name = name
        self.image = image.map { AnyView($0) }
        self.backdrop = backdrop.map { AnyView($0) }
        self.prompt = prompt
        _pin = pin
        self.failures = failures
        self.isChecking = isChecking
        self.errorMessage = errorMessage
        self.lockedUntil = lockedUntil
        self.onBack = onBack
        self.onComplete = onComplete
    }

    /// "Try again in 0:45": minutes and two-digit seconds, rounded up so it never shows 0:00 while locked.
    nonisolated public static func countdownText(remaining: TimeInterval) -> String {
        let total = max(Int(remaining.rounded(.up)), 0)
        return "Try again in \(total / 60):" + String(format: "%02d", total % 60)
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = lockedUntil.map { $0.timeIntervalSince(context.date) } ?? 0
            content(locked: remaining > 0, remaining: remaining)
        }
    }

    private func content(locked: Bool, remaining: TimeInterval) -> some View {
        VStack(spacing: 14) {
            ProfileAvatarImage(name: name, size: 120, image: image)
                .padding(.bottom, 6)
            Text(name)
                .font(PerchFont.section(style).weight(.bold))
                .foregroundStyle(PerchColor.textPrimary)
            statusLine(locked: locked, remaining: remaining)
                .frame(height: 36)
                .padding(.bottom, 14)
            PerchPINPad(
                pin: $pin, failures: failures, isDisabled: isChecking || locked, keySize: 100,
                disabledOpacity: locked ? 0.4 : 0.5, onComplete: onComplete
            )
            .disabled(locked)
            if locked {
                Button("OK") { onBack?() }
                    .buttonStyle(.perchSecondary)
                    .focused($okFocused)
                    .padding(.top, 20)
                    .accessibilityIdentifier("pinEntry.ok")
                    .onAppear { okFocused = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .perchPageMargins([.horizontal, .vertical])
        .background {
            if backdrop != nil { SetupBackdrop(art: backdrop) } else { PageBackground() }
        }
        .ignoresSafeArea()
        .focusSection()
    }

    @ViewBuilder
    private func statusLine(locked: Bool, remaining: TimeInterval) -> some View {
        if locked {
            Text(Self.countdownText(remaining: remaining))
                .font(PerchFont.body(style)).foregroundStyle(PerchColor.textPrimary)
                .monospacedDigit()
                .accessibilityIdentifier("pinEntry.locked")
        } else if isChecking {
            HStack(spacing: 14) {
                ProgressView()
                Text("Checking").font(PerchFont.body(style)).foregroundStyle(PerchColor.textSecondary)
            }
        } else if let errorMessage {
            Text(errorMessage).font(PerchFont.body(style)).foregroundStyle(PerchColor.textPrimary)
                .accessibilityIdentifier("pinEntry.error")
        } else {
            Text(prompt).font(PerchFont.body(style)).foregroundStyle(PerchColor.textSecondary)
        }
    }
}
