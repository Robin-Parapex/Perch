import SwiftUI

/// Full-bleed hero: backdrop with scrim, logo or title, badges, synopsis and actions.
/// Entrance re-runs when `replayKey` changes; Reduce Motion turns it into short fades.
public struct HeroCard<Backdrop: View, Logo: View, Actions: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let title: String
    private let synopsis: String
    private let metadata: String?
    private let badges: [Pill.Kind]
    private let replayKey: AnyHashable?
    private let titleIdentifier: String?
    private let heightFraction: CGFloat
    private let backdrop: Backdrop
    private let logo: Logo?
    private let actions: Actions

    public init(
        title: String,
        synopsis: String,
        metadata: String? = nil,
        badges: [Pill.Kind] = [],
        replayKey: AnyHashable? = nil,
        heightFraction: CGFloat = 0.8,
        titleIdentifier: String? = nil,
        @ViewBuilder backdrop: () -> Backdrop,
        @ViewBuilder logo: () -> Logo,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.synopsis = synopsis
        self.metadata = metadata
        self.badges = badges
        self.replayKey = replayKey
        self.titleIdentifier = titleIdentifier
        self.heightFraction = heightFraction
        self.backdrop = backdrop()
        self.logo = logo()
        self.actions = actions()
    }

    fileprivate init(
        title: String, synopsis: String, metadata: String?, badges: [Pill.Kind], replayKey: AnyHashable?, heightFraction: CGFloat, titleIdentifier: String?,
        backdrop: Backdrop, actions: Actions
    ) {
        self.title = title
        self.synopsis = synopsis
        self.metadata = metadata
        self.badges = badges
        self.replayKey = replayKey
        self.titleIdentifier = titleIdentifier
        self.heightFraction = heightFraction
        self.backdrop = backdrop
        self.logo = nil
        self.actions = actions
    }

    public var body: some View {
        // A new key rebuilds the inner view from scratch, so the entrance replays and the
        // one-shot Ken Burns restarts cleanly. Reduce Motion is part of the key
        // because it changes which effects exist.
        HeroEntrance(
            title: title, synopsis: synopsis, metadata: metadata, badges: badges, heightFraction: heightFraction, titleIdentifier: titleIdentifier,
            backdrop: backdrop, logo: logo, actions: actions
        )
        .id(EntranceKey(replay: replayKey, reduceMotion: reduceMotion))
    }
}

/// Layout numbers from docs/design/wp-09-home.md 3.1.
enum HeroMetrics {
    static let logoWidth: CGFloat = 600
    static let logoHeight: CGFloat = 140
    static let titleMaxWidth: CGFloat = 1200
    static let synopsisWidth: CGFloat = 900
    /// Two lines of the 26 pt body, reserved even when the synopsis is empty so a late synopsis never moves the block.
    static let synopsisHeight: CGFloat = 68
    static let contentBottomInset: CGFloat = 72
    static let leftScrimWidth: CGFloat = 1000
    static let leftScrimOpacity: Double = 0.55
    static let bottomScrimStart: CGFloat = 0.44
    static let bottomScrimTail: CGFloat = 36
    /// The text block's opacity while the sidebar holds focus (`perchHeroDimmed`).
    static let dimmedTextOpacity: Double = 0.15

    /// 0% at 44% of the height, 92% where the last 36 pt begin, 100% at the bottom.
    /// `strength` scales every opacity (used for the tint layer that sits over the base layer).
    static func bottomScrimStops(height: CGFloat, color: Color = PerchColor.base, strength: Double = 1) -> [Gradient.Stop] {
        let h = max(height, bottomScrimTail * 2)
        let tail = (h - bottomScrimTail) / h
        return [
            .init(color: color.opacity(0), location: bottomScrimStart),
            .init(color: color.opacity(0.92 * strength), location: tail),
            .init(color: color.opacity(strength), location: 1),
        ]
    }

    /// Two body lines at the style's font size: 68 pt at the standard 26 pt, scaled with the font (76 pt for kids).
    static func synopsisHeight(for style: PerchStyle) -> CGFloat {
        (synopsisHeight * PerchFont.size(PerchFont.bodySize, for: style) / PerchFont.bodySize).rounded(.up)
    }

    /// The reservation applies only when there is a synopsis; otherwise the row is absent.
    static func reservedSynopsisHeight(for synopsis: String, style: PerchStyle = .standard) -> CGFloat? {
        synopsis.isEmpty ? nil : synopsisHeight(for: style)
    }
}

extension EnvironmentValues {
    /// True while focus is outside the hero's page (the sidebar is open): the hero's text block fades back.
    @Entry public var perchHeroDimmed: Bool = false
}

private extension View {
    @ViewBuilder func optionalIdentifier(_ id: String?) -> some View {
        if let id { accessibilityIdentifier(id) } else { self }
    }
}

private struct EntranceKey: Hashable {
    let replay: AnyHashable?
    let reduceMotion: Bool
}

private struct HeroEntrance<Backdrop: View, Logo: View, Actions: View>: View {
    @Environment(\.perchStyle) private var style
    @Environment(\.perchTint) private var tint
    @Environment(\.perchAmbientMotion) private var ambientMotion
    @Environment(\.perchHeroDimmed) private var dimmed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var backdropIn = false
    @State private var logoIn = false
    @State private var textIn = false
    @State private var panning = false

    let title: String
    let synopsis: String
    let metadata: String?
    let badges: [Pill.Kind]
    let heightFraction: CGFloat
    let titleIdentifier: String?
    let backdrop: Backdrop
    let logo: Logo?
    let actions: Actions

    // MARK: Resolved effects

    private var logoScale: CGFloat {
        if case .scale(let from) = PerchMotion.resolve(.scale(from: PerchMotion.heroLogoStartScale), reduceMotion: reduceMotion) {
            return logoIn ? 1 : from
        }
        return 1
    }

    private var textOffset: CGFloat {
        if case .slide(let offset) = PerchMotion.resolve(.slide(offset: PerchMotion.heroTextOffset), reduceMotion: reduceMotion) {
            return textIn ? 0 : offset
        }
        return 0
    }

    private var kenBurns: CGFloat {
        if case .kenBurns(let amount) = PerchMotion.resolve(.kenBurns(amount: PerchMotion.kenBurnsAmount), reduceMotion: reduceMotion) {
            return panning ? amount : 0
        }
        return 0
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdropLayer
            scrim
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if let logo {
                        logo.frame(maxWidth: HeroMetrics.logoWidth, maxHeight: HeroMetrics.logoHeight, alignment: .bottomLeading)
                            .optionalIdentifier(titleIdentifier)
                    } else {
                        // Text fallback: same box and baseline as the logo, so it reads as a choice.
                        Text(title)
                            .font(PerchFont.hero(style))
                            .foregroundStyle(PerchColor.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .shadow(color: .black.opacity(0.4), radius: 2, y: 2)
                            .frame(maxWidth: HeroMetrics.titleMaxWidth, alignment: .leading)
                            .optionalIdentifier(titleIdentifier)
                    }
                }
                .frame(height: HeroMetrics.logoHeight, alignment: .bottomLeading)
                .scaleEffect(logoScale, anchor: .bottomLeading)
                .opacity(logoIn ? 1 : 0)

                Group {
                    if let metadata, !metadata.isEmpty {
                        Text(metadata)
                            .font(PerchFont.metadata(style))
                            .foregroundStyle(PerchColor.textSecondary)
                            .lineLimit(1)
                            .padding(.top, 20)
                    }
                    if !badges.isEmpty { BadgeStrip(badges).padding(.top, 16) }
                    if let reserved = HeroMetrics.reservedSynopsisHeight(for: synopsis, style: style) {
                        Text(synopsis)
                            .font(PerchFont.body(style))
                            .foregroundStyle(PerchColor.textBody)
                            .lineLimit(2)
                            .frame(maxWidth: HeroMetrics.synopsisWidth, minHeight: reserved, maxHeight: reserved, alignment: .topLeading)
                            .padding(.top, 16)
                    }
                    HStack(spacing: 24) { actions }.focusSection().padding(.top, 24)
                }
                .offset(y: textOffset)
                .opacity(textIn ? 1 : 0)
            }
            .padding(.horizontal, PerchSpacing.horizontalMargin)
            .padding(.bottom, HeroMetrics.contentBottomInset)
            // Faded back while the sidebar is open, so the title never reads through its glass (a fade only).
            .opacity(dimmed ? HeroMetrics.dimmedTextOpacity : 1)
            .animation(.easeInOut(duration: PerchMotion.crossfadeDuration), value: dimmed)
        }
        .containerRelativeFrame(.horizontal)
        .containerRelativeFrame(.vertical) { height, _ in height * heightFraction }
        .task { runEntrance() }
    }

    private var backdropLayer: some View {
        // The clear base takes the hero's size; the backdrop only fills it, so artwork never sizes the hero.
        Color.clear
            .overlay {
                backdrop
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(1 + kenBurns)
                    .offset(x: -kenBurns * 200, y: -kenBurns * 100)
            }
            .clipped()
            .opacity(backdropIn ? 1 : 0)
    }

    private var scrim: some View {
        ZStack(alignment: .leading) {
            // Base then tint at the page's own opacity, so the bottom edge equals PageBackground exactly.
            GeometryReader { proxy in
                ZStack {
                    LinearGradient(stops: HeroMetrics.bottomScrimStops(height: proxy.size.height), startPoint: .top, endPoint: .bottom)
                    if let tint {
                        LinearGradient(
                            stops: HeroMetrics.bottomScrimStops(height: proxy.size.height, color: tint, strength: PerchColor.pageTintOpacity),
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                }
            }
            LinearGradient(
                colors: [PerchColor.base.opacity(HeroMetrics.leftScrimOpacity), PerchColor.base.opacity(0)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: HeroMetrics.leftScrimWidth)
        }
        .allowsHitTesting(false)
    }

    // MARK: Entrance

    /// Runs once per instance; the outer view rebuilds this view to replay.
    private func runEntrance() {
        let fade = reduceMotion ? PerchMotion.crossfadeDuration : PerchMotion.heroBackdropFade
        withAnimation(.easeOut(duration: fade)) { backdropIn = true }
        withAnimation(.easeOut(duration: reduceMotion ? PerchMotion.crossfadeDuration : PerchMotion.heroLogoDuration)
            .delay(reduceMotion ? 0 : PerchMotion.heroLogoDelay)) { logoIn = true }
        withAnimation(.easeOut(duration: reduceMotion ? PerchMotion.crossfadeDuration : PerchMotion.panelDuration)
            .delay(reduceMotion ? 0 : PerchMotion.heroTextDelay)) { textIn = true }
        // One-shot pan that then holds; it replays only when the entrance does (spec 7).
        if !reduceMotion && ambientMotion {
            withAnimation(.linear(duration: PerchMotion.kenBurnsDuration)) { panning = true }
        }
    }
}

extension HeroCard where Logo == EmptyView {
    /// No logo artwork: the title is rendered as text in the hero font.
    public init(
        title: String,
        synopsis: String,
        metadata: String? = nil,
        badges: [Pill.Kind] = [],
        replayKey: AnyHashable? = nil,
        heightFraction: CGFloat = 0.8,
        titleIdentifier: String? = nil,
        @ViewBuilder backdrop: () -> Backdrop,
        @ViewBuilder actions: () -> Actions
    ) {
        self.init(title: title, synopsis: synopsis, metadata: metadata, badges: badges, replayKey: replayKey, heightFraction: heightFraction, titleIdentifier: titleIdentifier, backdrop: backdrop(), actions: actions())
    }
}

#Preview {
    HeroCard(title: "Dune: Part Two", synopsis: "Paul Atreides unites with the Fremen while seeking revenge against those who destroyed his family.", badges: [.format("4K"), .format("Dolby Vision")], backdrop: {
        LinearGradient(colors: [.indigo, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
    }, actions: {
        Button("Play") {}.buttonStyle(.perchPrimary)
        Button("My List") {}.buttonStyle(.perchSecondary)
    })
    .perchPageBackground()
}
