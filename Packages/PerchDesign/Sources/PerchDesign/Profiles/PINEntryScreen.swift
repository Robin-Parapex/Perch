import SwiftUI

/// "Enter the PIN for Sam": one centred column with the avatar, name, prompt, PIN dots and keypad.
/// While `isChecking` the keypad is dimmed and a small spinner shows; `errorMessage` is plain words.
public struct PINEntryScreen: View {
    private let name: String
    private let image: AnyView?
    private let prompt: String
    private let errorMessage: String?
    private let isChecking: Bool
    private let failures: Int
    @Binding private var pin: String
    private let onComplete: (String) -> Void
    @Environment(\.perchStyle) private var style

    /// Bump `failures` after a wrong PIN to shake and clear; clear `pin` yourself when you reset.
    public init(
        name: String, image: (any View)? = nil, prompt: String = "Enter your PIN",
        pin: Binding<String>, failures: Int = 0, isChecking: Bool = false, errorMessage: String? = nil,
        onComplete: @escaping (String) -> Void
    ) {
        self.name = name
        self.image = image.map { AnyView($0) }
        self.prompt = prompt
        _pin = pin
        self.failures = failures
        self.isChecking = isChecking
        self.errorMessage = errorMessage
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 14) {
            ProfileAvatarImage(name: name, size: 140, image: image)
                .padding(.bottom, 10)
            Text(name)
                .font(PerchFont.section(style).weight(.bold))
                .foregroundStyle(PerchColor.textPrimary)
            statusLine
                .frame(height: 36)
                .padding(.bottom, 26)
            PerchPINPad(pin: $pin, failures: failures, isDisabled: isChecking, onComplete: onComplete)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .perchPageMargins([.horizontal, .vertical])
        .ignoresSafeArea()
        .perchPageBackground()
    }

    @ViewBuilder
    private var statusLine: some View {
        if isChecking {
            HStack(spacing: 14) {
                ProgressView()
                Text("Checking").font(PerchFont.body(style)).foregroundStyle(PerchColor.textSecondary)
            }
        } else if let errorMessage {
            Text(errorMessage).font(PerchFont.body(style)).foregroundStyle(PerchColor.textBody)
                .accessibilityIdentifier("pinEntry.error")
        } else {
            Text(prompt).font(PerchFont.body(style)).foregroundStyle(PerchColor.textSecondary)
        }
    }
}
