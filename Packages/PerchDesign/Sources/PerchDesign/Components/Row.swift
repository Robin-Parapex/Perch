import SwiftUI

/// A titled, snapping horizontal row. Inside a RowList the focused row lifts and the others dim.
public struct Row<Content: View>: View {
    @Environment(\.perchStyle) private var style
    @Environment(\.perchRowFocus) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let id: AnyHashable
    private let title: String
    private let content: Content

    public init(id: AnyHashable? = nil, title: String, @ViewBuilder content: () -> Content) {
        self.id = id ?? AnyHashable(title)
        self.title = title
        self.content = content()
    }

    private var hasFocusedRow: Bool { context?.focusedRowID != nil }
    private var isFocusedRow: Bool { context?.focusedRowID == id }

    private var lift: CGFloat {
        guard hasFocusedRow, isFocusedRow else { return 0 }
        if case .lift(let points) = PerchMotion.resolve(.lift(points: PerchMotion.rowLift), reduceMotion: reduceMotion) {
            return -points
        }
        return 0
    }

    private var opacity: Double {
        guard hasFocusedRow, !isFocusedRow else { return 1 }
        if case .dim(let value) = PerchMotion.resolve(.dim(opacity: PerchMotion.rowDimOpacity), reduceMotion: reduceMotion) {
            return value
        }
        return 1
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(PerchFont.section(style))
                .foregroundStyle(PerchColor.textPrimary)
                .padding(.leading, PerchSpacing.horizontalMargin)
            // Approach after Dusk Shared/MediaCarousel.swift:27-39 (horizontal ScrollView + LazyHStack + focusSection).
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: PerchSpacing.itemGap) { content }
                    .scrollTargetLayout()
                    .padding(.vertical, 40)
            }
            // Content inset, not outer padding: the row spans the screen and cards scroll off its edge.
            .contentMargins(.horizontal, PerchSpacing.horizontalMargin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .focusSection()
        }
        .environment(\.perchFocusReporter, reporter)
        .offset(y: lift)
        .opacity(opacity)
        .animation(PerchMotion.spring, value: context?.focusedRowID)
    }

    private var reporter: (@MainActor (Bool) -> Void)? {
        guard let context else { return nil }
        let id = id
        return { focused in context.report(rowID: id, focused: focused) }
    }
}

#Preview {
    Row(title: "Continue Watching") {
        ForEach(0..<6, id: \.self) { index in
            LandscapeCard(title: "Episode \(index + 1)", subtitle: "31 min left", progress: 0.3, action: {}) {
                LinearGradient(colors: [.purple, .black], startPoint: .top, endPoint: .bottom)
            }
        }
    }
    .perchPageBackground()
}
