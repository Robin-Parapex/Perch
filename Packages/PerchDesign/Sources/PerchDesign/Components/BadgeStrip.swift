import SwiftUI

/// A row of at most `maxBadges` pills.
public struct BadgeStrip: View {
    public nonisolated static let maxBadges = 3

    public nonisolated static func visible(_ kinds: [Pill.Kind]) -> [Pill.Kind] {
        Array(kinds.prefix(maxBadges))
    }

    private let kinds: [Pill.Kind]

    public init(_ kinds: [Pill.Kind]) { self.kinds = Self.visible(kinds) }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(kinds.enumerated()), id: \.offset) { _, kind in
                Pill(kind)
            }
        }
    }
}
