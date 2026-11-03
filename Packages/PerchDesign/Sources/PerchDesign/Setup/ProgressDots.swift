import SwiftUI

/// Step indicator for the setup wizard: one dot per step, the current one filled.
public struct ProgressDots: View {
    private let current: Int
    private let total: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `current` is 1-based.
    public init(current: Int, total: Int) {
        self.current = current
        self.total = total
    }

    /// The spoken label, "Step 2 of 6".
    nonisolated public static func label(current: Int, total: Int) -> String {
        "Step \(current) of \(total)"
    }

    public var body: some View {
        HStack(spacing: 14) {
            ForEach(1...max(total, 1), id: \.self) { index in
                Circle()
                    .fill(index == current ? PerchColor.textPrimary : PerchColor.textPrimary.opacity(0.28))
                    .frame(width: 14, height: 14)
                    .scaleEffect(index == current && !reduceMotion ? 1.25 : 1)
                    .animation(PerchMotion.spring, value: current)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(current: current, total: total))
    }
}
