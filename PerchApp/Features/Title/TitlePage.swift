import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI

/// A film's title page (WP-11, SPEC 5), pushed on the current tab's stack.
struct TitleScreen: View {
    let core: CoreServices
    let home: HomeProfile
    let route: TitleRoute
    let onBack: () -> Void

    var body: some View {
        TitlePage(core: core, home: home, route: route, isSeries: false, onBack: onBack)
    }
}

/// A series page (WP-11, SPEC 4): the hero with Play next, a season rail, the season's episodes, the cast.
struct SeriesScreen: View {
    let core: CoreServices
    let home: HomeProfile
    let route: TitleRoute
    let onBack: () -> Void

    var body: some View {
        TitlePage(core: core, home: home, route: route, isSeries: true, onBack: onBack)
    }
}

/// The shared page. The primary button takes the first focus (DESIGN:46); Back pops to the card or poster that
/// opened it (the shell's `PushedScreen` and the opener's own restore); Back from the player lands on the button or
/// episode that started it. The theme tune plays softly while the page is up (never for a kid) and stops on leaving
/// the page or when playback starts.
private struct TitlePage: View {
    let core: CoreServices
    let home: HomeProfile
    let isSeries: Bool
    let onBack: () -> Void

    @State private var model: TitlePageModel
    @State private var theme = ThemeMusicPlayer()
    @State private var showsSynopsis = false
    @State private var pendingRestore: TitleFocus?
    @FocusState private var focus: TitleFocus?
    @Environment(\.perchStyle) private var style

    private static let topID = "title.top"

    init(core: CoreServices, home: HomeProfile, route: TitleRoute, isSeries: Bool, onBack: @escaping () -> Void) {
        self.core = core
        self.home = home
        self.isSeries = isSeries
        self.onBack = onBack
        _model = State(
            initialValue: TitlePageModel(route: route, library: core.library, context: home.context, isKid: home.isKid))
    }

    private var playerActive: Bool { core.playback.activeSession != nil }
    private var sessionReady: Bool {
        if case .ready = core.plexSignIn.snapshot.state { true } else { false }
    }
    private var available: Bool { model.phase != .unavailable && model.phase != .failed }
    private var identifier: String { isSeries ? "series" : "title" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 40) {
                    hero.id(Self.topID)
                    switch model.phase {
                    case .unavailable:
                        LibraryMessage(
                            title: TitleStrings.unavailableTitle, message: TitleStrings.unavailableMessage,
                            action: .init(ShellStrings.back, identifier: "title.back", run: onBack))
                    case .failed:
                        LibraryMessage(
                            title: TitleStrings.failedTitle, message: TitleStrings.failedMessage,
                            action: .init(TitleStrings.tryAgain, identifier: "title.retry") {
                                Task { await load() }
                            })
                    case .loading, .ready:
                        if isSeries { episodesSection }
                        if let cast = model.detail?.cast, !cast.isEmpty {
                            CastRail(cast: cast, focus: $focus).transition(.opacity)
                        }
                    }
                }
                .padding(.bottom, 100)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: PerchMotion.crossfadeDuration), value: model.phase)
            }
            .scrollClipDisabled()
            .onChange(of: focus) { _, new in scroll(for: new, proxy: proxy) }
        }
        .ignoresSafeArea()
        .defaultFocus($focus, available ? .primary : nil, priority: .userInitiated)
        .overlay(alignment: .topLeading) { ThemeMarker(state: theme.state) }
        .perchFullScreen(isPresented: $showsSynopsis) {
            SynopsisPanel(
                title: model.summary?.title ?? "", text: model.detail?.synopsis ?? model.summary?.summary ?? "",
                onClose: { showsSynopsis = false })
        }
        .onAppear { if let seed = model.summary { core.artworkTint.focus(seed) } }
        .onDisappear { theme.stop() }
        .task(id: sessionReady) {
            guard sessionReady, model.phase != .ready else { return }
            await load()
        }
        .onChange(of: playerActive) { _, active in
            if active { theme.stop() } else { returnedFromPlayer() }
        }
        .onChange(of: model.detail?.summary.id) { _, _ in
            if let summary = model.summary { core.artworkTint.focus(summary) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifier).root")
    }

    // MARK: Hero

    private var hero: some View {
        TitleHero(
            summary: model.summary, metadata: TitleFacts.metadata(model.detail, seed: model.summary ?? placeholder),
            badges: TitleFacts.badges(model.detail),
            synopsis: model.detail?.synopsis ?? model.summary?.summary, focus: $focus,
            onMore: { showsSynopsis = true }
        ) {
            if available {
                if isSeries { seriesActions } else { filmActions }
            }
        }
    }

    private var placeholder: MediaSummary { MediaSummary(id: model.route.id, kind: isSeries ? .series : .film, title: "") }

    @ViewBuilder
    private var filmActions: some View {
        let item = model.summary ?? placeholder
        let action = FilmPrimaryAction(item)
        Button { playFilm(startMs: action.startMs) } label: {
            ActionLabel(title: action.title, detail: action.detail, systemImage: "play.fill")
        }
        .buttonStyle(.perchPrimary)
        .focused($focus, equals: .primary)
        .accessibilityIdentifier("title.primary")
        if case .resume = action {
            Button { playFilm(startMs: 0) } label: {
                Label(TitleStrings.fromStart, systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.perchSecondary)
            .focused($focus, equals: .fromStart)
            .accessibilityIdentifier("title.fromStart")
        }
        Button {
            Task { await model.setWatched(!item.isWatched, itemID: item.id) }
        } label: {
            Label(
                item.isWatched ? TitleStrings.markUnwatched : TitleStrings.markWatched,
                systemImage: item.isWatched ? "eye.slash" : "checkmark")
        }
        .buttonStyle(.perchSecondary)
        .focused($focus, equals: .watched)
        .accessibilityIdentifier("title.watched")
    }

    private var seriesActions: some View {
        let next = model.next
        return Button { playNext(from: .primary) } label: {
            ActionLabel(title: next?.title ?? TitleStrings.play, detail: next?.detail, systemImage: "play.fill")
        }
        .buttonStyle(.perchPrimary)
        .focused($focus, equals: .primary)
        .accessibilityIdentifier("series.primary")
        .animation(.easeInOut(duration: PerchMotion.crossfadeDuration), value: next)
    }

    // MARK: Episodes

    /// The season rail with Play next at its trailing end (SPEC 4: Play next stays reachable beside the episodes),
    /// then the chosen season's episodes as a shelf of landscape cards.
    @ViewBuilder
    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                ForEach(model.seasons, id: \.self) { season in
                    Button {
                        withAnimation(.easeInOut(duration: PerchMotion.crossfadeDuration)) { model.selectedSeason = season }
                    } label: {
                        FilterChipLabel(TitleStrings.seasonTitle(season), showsChevron: false)
                    }
                    .buttonStyle(.perchChip(active: season == model.selectedSeason))
                    .focused($focus, equals: .season(season))
                    .accessibilityIdentifier("series.season.\(season)")
                }
                Spacer(minLength: 24)
                if let next = model.next {
                    Button { playNext(from: .playNext) } label: {
                        FilterChipLabel(
                            HomeStrings.joined([next.title, next.detail]), systemImage: "play.fill", showsChevron: false)
                    }
                    .buttonStyle(.perchChip())
                    .focused($focus, equals: .playNext)
                    .accessibilityIdentifier("series.playNext")
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, PerchSpacing.horizontalMargin)
            .frame(width: LibraryGridLayout.screenWidth, alignment: .leading)
            .focusSection()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("series.seasons")

            if model.phase == .ready, model.episodes.isEmpty {
                Text(TitleStrings.noEpisodes)
                    .font(PerchFont.body(style))
                    .foregroundStyle(PerchColor.textHelper)
                    .padding(.leading, PerchSpacing.horizontalMargin)
                    .padding(.top, 24)
            } else {
                episodeShelf
            }
        }
    }

    private var episodeShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 40) {
                ForEach(model.seasonEpisodes) { episode in
                    VStack(alignment: .leading, spacing: 6) {
                        LandscapeCard(
                            title: TitleStrings.episodeTitle(episode), subtitle: TitleStrings.episodeSubtitle(episode),
                            progress: episode.isInProgress ? episode.progress : nil, action: { play(episode) }
                        ) {
                            ArtworkImage(path: episode.thumbPath ?? episode.artPath, size: .landscape)
                                .overlay(alignment: .topTrailing) {
                                    if episode.isWatched { WatchedTick().padding(12) }
                                }
                        }
                        .focused($focus, equals: .episode(episode.id))
                        .onPlayPauseCommand { play(episode) }
                        .contextMenu {
                            Button(episode.isWatched ? TitleStrings.markUnwatched : TitleStrings.markWatched) {
                                Task { await model.setWatched(!episode.isWatched, itemID: episode.id) }
                            }
                        }
                        .accessibilityIdentifier("series.episode.\(episode.id)")
                        if let synopsis = episode.summary {
                            Text(synopsis)
                                .font(PerchFont.metadata(style))
                                .foregroundStyle(PerchColor.textHelper)
                                .lineLimit(1)
                                .frame(width: PerchSize.landscape.width, alignment: .leading)
                        }
                    }
                }
            }
            .padding(.vertical, 32)
        }
        .id(model.selectedSeason)
        .contentMargins(.horizontal, PerchSpacing.horizontalMargin, for: .scrollContent)
        .scrollClipDisabled()
        .focusSection()
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("series.episodes")
    }

    // MARK: Actions

    private func load() async {
        await model.load(isSeries: isSeries)
        guard model.phase == .ready else { return }
        guard ThemeMusicPolicy.plays(themePath: model.detail?.themePath, isKid: home.isKid) else {
            if model.detail?.themePath != nil { theme.markOff() }
            return
        }
        guard !playerActive, let source = await model.themeSource(), !playerActive else { return }
        theme.start(source)
    }

    private func playFilm(startMs: Int?) {
        guard let item = model.summary else { return }
        pendingRestore = focus ?? .primary
        theme.stop()
        core.playback.play(item, startMs: startMs)
    }

    private func playNext(from origin: TitleFocus) {
        pendingRestore = origin
        theme.stop()
        Task {
            if model.episodes.isEmpty { await model.load(isSeries: true) }
            guard let next = model.next else { return }
            core.playback.play(next.episode, startMs: next.startMs)
        }
    }

    private func play(_ episode: MediaSummary) {
        pendingRestore = .episode(episode.id)
        theme.stop()
        core.playback.play(episode, startMs: episode.isInProgress ? nil : 0)
    }

    private func returnedFromPlayer() {
        let target = pendingRestore
        pendingRestore = nil
        Task {
            // After the cover has gone, so the focus engine takes the request.
            try? await Task.sleep(for: .milliseconds(250))
            if let target { focus = target }
            try? await Task.sleep(for: .seconds(1))
            await model.refresh(isSeries: isSeries)
        }
    }

    /// The hero's controls bring the page back to its top; the rails below scroll themselves into view.
    private func scroll(for new: TitleFocus?, proxy: ScrollViewProxy) {
        switch new {
        case .primary, .synopsis, .fromStart, .watched:
            withAnimation(PerchMotion.spring) { proxy.scrollTo(Self.topID, anchor: .top) }
        default:
            break
        }
    }
}

/// "Resume · 40 min left": the action, then a quieter detail.
private struct ActionLabel: View {
    let title: String
    let detail: String?
    let systemImage: String

    var body: some View {
        Label {
            if let detail {
                Text("\(title)\(Text(HomeStrings.separator + detail).foregroundStyle(.secondary))")
            } else {
                Text(title)
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { "\(title), \($0)" } ?? title)
    }
}
