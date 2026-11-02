import PerchCore
import SwiftUI

/// Landscape card for continue watching and episodes. Only the artwork lifts and rings.
public struct LandscapeCard<Artwork: View>: View {
    private let title: String
    private let subtitle: String?
    private let badges: [Pill.Kind]
    private let availability: TitleAvailability?
    private let progress: Double?
    private let action: () -> Void
    private let artwork: Artwork

    public init(
        title: String,
        subtitle: String? = nil,
        badges: [Pill.Kind] = [],
        availability: TitleAvailability? = nil,
        progress: Double? = nil,
        action: @escaping () -> Void,
        @ViewBuilder artwork: () -> Artwork
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badges = badges
        self.availability = availability
        self.progress = progress
        self.action = action
        self.artwork = artwork()
    }

    public var body: some View {
        PerchCardButton(action: action) {
            CardArtwork(size: PerchSize.landscape, badges: badges, progress: progress) { artwork }
        } caption: {
            CardCaption(width: PerchSize.landscape.width, title: title, subtitle: subtitle, availability: availability)
        }
    }
}

#Preview {
    LandscapeCard(title: "Severance", subtitle: "31 min left", progress: 0.6, action: {}) {
        LinearGradient(colors: [.teal, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    .padding()
    .perchPageBackground()
}
