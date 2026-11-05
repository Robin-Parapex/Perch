import SwiftUI

/// Adult or kids presentation. Kids get slightly larger type and rounder cards.
public enum PerchStyle: Sendable, Hashable {
    case standard, kids
}

extension EnvironmentValues {
    @Entry public var perchStyle: PerchStyle = .standard
    /// Optional page tint (for example from artwork) laid over the base colour.
    @Entry public var perchTint: Color? = nil
    /// False stops ambient motion (hero Ken Burns pan); entrance fades stay. Set by UI tests.
    @Entry public var perchAmbientMotion: Bool = true
}
