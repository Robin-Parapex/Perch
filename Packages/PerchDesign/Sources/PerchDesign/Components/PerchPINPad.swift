import SwiftUI

/// Four-digit PIN entry in the phone-keypad layout Plex and Apple use: dots that fill as digits go
/// in, a 3x3 grid with 0 centred underneath and delete beside it. Number keys on a connected
/// keyboard work too. Calls `onComplete` on the last digit; bump `failures` to shake and clear.
/// `isDisabled` dims the pad and ignores input while a PIN is being checked.
public struct PerchPINPad: View {
    @Binding private var pin: String
    private let length: Int
    private let failures: Int
    private let isDisabled: Bool
    private let keySize: CGFloat
    private let disabledOpacity: Double
    private let onComplete: (String) -> Void
    @State private var shake: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var gap: CGFloat { keySize < 112 ? 20 : 28 }

    private static let rows: [[String?]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [nil, "0", "delete"]]

    public init(pin: Binding<String>, length: Int = 4, failures: Int = 0, isDisabled: Bool = false,
        keySize: CGFloat = 112, disabledOpacity: Double = 0.5, onComplete: @escaping (String) -> Void) {
        _pin = pin
        self.length = length
        self.failures = failures
        self.isDisabled = isDisabled
        self.keySize = keySize
        self.disabledOpacity = disabledOpacity
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: keySize < 112 ? 40 : 56) {
            dots
            VStack(spacing: gap) {
                ForEach(Self.rows.indices, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(Self.rows[row].indices, id: \.self) { column in
                            key(Self.rows[row][column])
                        }
                    }
                }
            }
            .focusSection()
        }
        .opacity(isDisabled ? disabledOpacity : 1)
        .animation(PerchMotion.spring, value: isDisabled)
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            add(press.characters)
            return .handled
        }
        .onKeyPress(.delete, phases: .down) { _ in
            deleteLast()
            return .handled
        }
        .onChange(of: failures) {
            guard !reduceMotion else { return }
            shake = 0
            withAnimation(.linear(duration: 0.3)) { shake = 1 }
        }
    }

    private var dots: some View {
        HStack(spacing: 28) {
            ForEach(0..<length, id: \.self) { index in
                Circle()
                    .strokeBorder(PerchColor.textPrimary.opacity(0.6), lineWidth: 2)
                    .background(Circle().fill(index < pin.count ? PerchColor.textPrimary : .clear))
                    .frame(width: 24, height: 24)
                    .animation(PerchMotion.spring, value: pin.count)
            }
        }
        .modifier(ShakeEffect(progress: shake))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pin.count) of \(length) digits entered")
    }

    @ViewBuilder
    private func key(_ value: String?) -> some View {
        switch value {
        case nil:
            Color.clear.frame(width: keySize, height: keySize)
        case "delete":
            Button(action: deleteLast) {
                Image(systemName: "delete.left").font(.system(size: 34, weight: .medium))
            }
            .buttonStyle(PINKeyStyle(quiet: true, size: keySize))
            .accessibilityLabel("Delete")
            .accessibilityIdentifier("pinPad.delete")
        case let digit?:
            Button(digit) { add(digit) }
                .buttonStyle(PINKeyStyle(quiet: false, size: keySize))
                .accessibilityIdentifier("pinPad.\(digit)")
        }
    }

    private func add(_ digit: String) {
        guard !isDisabled, pin.count < length, digit.count == 1 else { return }
        // Work from a local copy: inside a key press handler, reading the binding straight after
        // writing it still returns the old value, so the fourth digit never looked complete.
        let entered = pin + digit
        pin = entered
        if entered.count == length { onComplete(entered) }
    }

    private func deleteLast() {
        if !isDisabled, !pin.isEmpty { pin.removeLast() }
    }
}

/// Round key: translucent at rest, white with dark text and a lift when focused.
private struct PINKeyStyle: ButtonStyle {
    let quiet: Bool
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        KeyBody(configuration: configuration, quiet: quiet, size: size)
    }

    private struct KeyBody: View {
        let configuration: Configuration
        let quiet: Bool
        let size: CGFloat
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.system(size: size * 0.39, weight: .medium, design: .rounded))
                .foregroundStyle(isFocused ? PerchColor.base : PerchColor.textPrimary)
                .frame(width: size, height: size)
                .background {
                    Circle().fill(
                        isFocused ? AnyShapeStyle(Color.white)
                            : quiet ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Color.white.opacity(0.14)))
                }
                .scaleEffect(isFocused && !reduceMotion ? (configuration.isPressed ? 1.04 : 1.12) : 1)
                .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 18, y: 10)
                .animation(PerchMotion.spring, value: isFocused)
                .animation(PerchMotion.spring, value: configuration.isPressed)
        }
    }
}

/// Horizontal shake for a refused PIN.
private struct ShakeEffect: GeometryEffect {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 18 * sin(progress * .pi * 6) * (1 - progress), y: 0))
    }
}
