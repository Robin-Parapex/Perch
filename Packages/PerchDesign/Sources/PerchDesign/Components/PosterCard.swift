import PerchCore
import SwiftUI

/// Artwork with badges and an optional progress bar, plus the shared caption.
struct CardArtwork<Artwork: View>: View {
    let size: CGSize
    let badges: [Pill.Kind]
    let progress: Double?
    @ViewBuilder let artwork: Artwork

    private static var barHeight: CGFloat { 4 }
    private static var badgePadding: CGFloat { 10 }

    var body: some View {
        artwork
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if !badges.isEmpty {
                    BadgeStrip(badges).padding(Self.badgePadding)
                        .padding(.bottom, progress == nil ? 0 : Self.barHeight)
                }
            }
            .overlay(alignment: .bottom) {
                if let progress {
                    let value = min(max(progress.isNaN ? 0 : progress, 0), 1)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.3))
                        Rectangle().fill(Color.white).frame(width: size.width * value)
                    }
                    .frame(height: Self.barHeight)
                }
            }
    }
}

struct CardCaption: View {
    @Environment(\.perchStyle) private var style
    @Environment(\.isFocused) private var isFocused
    let width: CGFloat
    let title: String
    let subtitle: String?
    let availability: TitleAvailability?
    /// Focused, a title too long for one line takes the subtitle's line as well, so it reads in full in the same
    /// height (nothing below moves).
    var expandsTitleWhenFocused = false

    private var titleText: some View {
        Text(title).font(PerchFont.metadata(style)).foregroundStyle(PerchColor.textBody)
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleText.lineLimit(1)
            if let subtitle {
                Text(subtitle).font(PerchFont.metadata(style)).foregroundStyle(PerchColor.textSecondary).lineLimit(1)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if expandsTitleWhenFocused && subtitle != nil {
                // The resting two lines always reserve the height; focused, the title gets both lines when it needs them.
                lines.opacity(isFocused ? 0 : 1)
                    .overlay(alignment: .topLeading) {
                        if isFocused {
                            ViewThatFits(in: .horizontal) {
                                lines
                                titleText.lineLimit(2).frame(width: width, alignment: .leading)
                            }
                        }
                    }
            } else {
                lines
            }
            if let availability {
                Pill(.availability(availability, kids: style == .kids))
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

/// Portrait poster card (row or grid size). Only the artwork lifts and rings.
public struct PosterCard<Artwork: View>: View {
    public enum Size: Sendable, Hashable {
        case row, grid

        var dimensions: CGSize { self == .row ? PerchSize.posterRow : PerchSize.posterGrid }
    }

    private let size: Size
    private let title: String
    private let subtitle: String?
    private let badges: [Pill.Kind]
    private let availability: TitleAvailability?
    private let progress: Double?
    private let expandsTitleWhenFocused: Bool
    private let action: () -> Void
    private let artwork: Artwork

    public init(
        size: Size = .row,
        title: String,
        subtitle: String? = nil,
        badges: [Pill.Kind] = [],
        availability: TitleAvailability? = nil,
        progress: Double? = nil,
        expandsTitleWhenFocused: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder artwork: () -> Artwork
    ) {
        self.size = size
        self.title = title
        self.subtitle = subtitle
        self.badges = badges
        self.availability = availability
        self.progress = progress
        self.expandsTitleWhenFocused = expandsTitleWhenFocused
        self.action = action
        self.artwork = artwork()
    }

    public var body: some View {
        PerchCardButton(action: action) {
            CardArtwork(size: size.dimensions, badges: badges, progress: progress) { artwork }
        } caption: {
            CardCaption(
                width: size.dimensions.width, title: title, subtitle: subtitle, availability: availability,
                expandsTitleWhenFocused: expandsTitleWhenFocused)
        }
    }
}

#Preview {
    PosterCard(title: "Dune", subtitle: "2021", badges: [.format("4K"), .new], availability: .readyToWatch, progress: 0.4, action: {}) {
        LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom)
    }
    .padding()
    .perchPageBackground()
}
