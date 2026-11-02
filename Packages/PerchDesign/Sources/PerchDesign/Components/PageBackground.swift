import SwiftUI

/// Full-bleed base colour with an optional faint tint from `perchTint`.
public struct PageBackground: View {
    @Environment(\.perchTint) private var tint

    public init() {}

    public var body: some View {
        ZStack {
            PerchColor.base
            if let tint {
                tint.opacity(PerchColor.pageTintOpacity)
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    public func perchPageBackground() -> some View {
        background { PageBackground() }
    }
}
