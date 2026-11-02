import SwiftUI

extension View {
    /// Large field for the wizard (server address, names). Keeps the native TextField or SecureField, so
    /// the keyboard, Siri dictation and the iPhone keyboard prompt still work.
    public func perchSetupField() -> some View {
        modifier(SetupFieldModifier())
    }
}

private struct SetupFieldModifier: ViewModifier {
    @Environment(\.perchStyle) private var style

    func body(content: Content) -> some View {
        content
            .font(PerchFont.body(style))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 800)
    }
}
