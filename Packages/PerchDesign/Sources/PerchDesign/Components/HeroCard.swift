import SwiftUI

/// Full-bleed hero: backdrop with scrim, logo or title, badges, synopsis and actions.
/// Entrance re-runs when `replayKey` changes; Reduce Motion turns it into short fades.
public struct HeroCard<Backdrop: View, Logo: View, Actions: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let title: String
    private let synopsis: String
    private let badges: [Pill.Kind]
    private let replayKey: AnyHashable?
    private let backdrop: Backdrop
    private let logo: Logo?
    private let actions: Actions

    public init(
        title: String,
        synopsis: String,
        badges: [Pill.Kind] = [],
        replayKey: AnyHashable? = nil,
        @ViewBuilder backdrop: () -> Backdrop,
        @ViewBuilder logo: () -> Logo,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.synopsis = synopsis
        self.badges = badges
        self.replayKey = replayKey
        self.backdrop = backdrop()
        self.logo = logo()
        self.actions = actions()
    }

    fileprivate init(
        title: String, synopsis: String, badges: [Pill.Kind], replayKey: AnyHashable?,
        backdrop: Backdrop, actions: Actions
    ) {
        self.title = title
        self.synopsis = synopsis
        self.badges = badges
        self.replayKey = replayKey
        self.backdrop = backdrop
        self.logo = nil
        self.actions = actions
    }

    public var body: some View {
        // A new key rebuilds the inner view from scratch, so the entrance replays and a second
        // repeatForever Ken Burns never stacks on the first. Reduce Motion is part of the key
        // because it changes which effects exist.
        HeroEntrance(
            title: title, synopsis: synopsis, badges: badges,
            backdrop: backdrop, logo: logo, actions: actions
        )
        .id(EntranceKey(replay: replayKey, reduceMotion: reduceMotion))
    }
}

private struct EntranceKey: Hashable {
    let replay: AnyHashable?
    let reduceMotion: Bool
}

private struct HeroEntrance<Backdrop: View, Logo: View, Actions: View>: View {
    @Environment(\.perchStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var backdropIn = false
    @State private var logoIn = false
    @State private var textIn = false
    @State private var panning = false

    let title: String
    let synopsis: String
    let badges: [Pill.Kind]
    let backdrop: Backdrop
    let logo: Logo?
    let actions: Actions

    private static var height: CGFloat { 800 }

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
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    if let logo {
                        logo.frame(maxWidth: 600, maxHeight: 140, alignment: .leading)
                    } else {
                        Text(title).font(PerchFont.hero(style)).foregroundStyle(PerchColor.textPrimary)
                    }
                }
                .scaleEffect(logoScale, anchor: .bottomLeading)
                .opacity(logoIn ? 1 : 0)

                Group {
                    if !badges.isEmpty { BadgeStrip(badges) }
                    Text(synopsis)
                        .font(PerchFont.body(style))
                        .foregroundStyle(PerchColor.textBody)
                        .lineLimit(2)
                        .frame(maxWidth: 900, alignment: .leading)
                    HStack(spacing: 24) { actions }.focusSection()
                }
                .offset(y: textOffset)
                .opacity(textIn ? 1 : 0)
            }
            .padding(.horizontal, PerchSpacing.horizontalMargin)
            .padding(.bottom, PerchSpacing.topMargin)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .task { runEntrance() }
    }

    private var backdropLayer: some View {
        backdrop
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .scaleEffect(1 + kenBurns)
            .offset(x: -kenBurns * 200, y: -kenBurns * 100)
            .clipped()
            .opacity(backdropIn ? 1 : 0)
    }

    private var scrim: some View {
        ZStack {
            LinearGradient(colors: [PerchColor.base, PerchColor.base.opacity(0)], startPoint: .bottom, endPoint: .center)
            LinearGradient(colors: [PerchColor.base.opacity(0.8), PerchColor.base.opacity(0)], startPoint: .leading, endPoint: .center)
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
        if !reduceMotion {
            withAnimation(.linear(duration: PerchMotion.kenBurnsDuration).repeatForever(autoreverses: true)) { panning = true }
        }
    }
}

extension HeroCard where Logo == EmptyView {
    /// No logo artwork: the title is rendered as text in the hero font.
    public init(
        title: String,
        synopsis: String,
        badges: [Pill.Kind] = [],
        replayKey: AnyHashable? = nil,
        @ViewBuilder backdrop: () -> Backdrop,
        @ViewBuilder actions: () -> Actions
    ) {
        self.init(title: title, synopsis: synopsis, badges: badges, replayKey: replayKey, backdrop: backdrop(), actions: actions())
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
