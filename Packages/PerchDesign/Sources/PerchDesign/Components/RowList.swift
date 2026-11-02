import SwiftUI

/// Vertical stack of Rows that shares focus state so the focused row lifts and the rest dim.
public struct RowList<Content: View>: View {
    @State private var context = RowFocusContext()
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: PerchSpacing.rowGap) { content }
                .environment(\.perchRowFocus, context)
        }
    }
}

#Preview {
    RowList {
        Row(title: "Recently Added") {
            ForEach(0..<8, id: \.self) { index in
                PosterCard(title: "Title \(index)", action: {}) {
                    LinearGradient(colors: [.orange, .black], startPoint: .top, endPoint: .bottom)
                }
            }
        }
        Row(title: "Because You Watched") {
            ForEach(0..<8, id: \.self) { index in
                PosterCard(title: "Title \(index)", action: {}) {
                    LinearGradient(colors: [.blue, .black], startPoint: .top, endPoint: .bottom)
                }
            }
        }
    }
    .perchPageBackground()
}
