import SwiftUI

extension View {
    /// The one margin rule. tvOS already insets pages by its safe area (80 pt sides, 60 pt top);
    /// Perch ignores that and applies the DESIGN margins itself, once, so text and focusable
    /// content sit at exactly `PerchSpacing.horizontalMargin` and `topMargin` from the screen edge.
    /// Put `.ignoresSafeArea()` on a page's outermost ScrollView or container, and this on the
    /// content that needs margins. Full-bleed art (hero, rows) skips it and insets its own content.
    public func perchPageMargins(_ edges: Edge.Set = [.horizontal, .top]) -> some View {
        padding(.horizontal, edges.contains(.horizontal) || edges.contains(.leading) ? PerchSpacing.horizontalMargin : 0)
            .padding(.top, edges.contains(.top) || edges.contains(.vertical) ? PerchSpacing.topMargin : 0)
            .padding(.bottom, edges.contains(.bottom) || edges.contains(.vertical) ? PerchSpacing.topMargin : 0)
    }
}
