import NukeUI
import OSLog
import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI

/// The Home screen (docs/design/wp-09-home.md): the hero, then up to three rows, from the cached rows in the
/// first frame and refreshed in place. Never a spinner.
struct HomeView: View {
    let core: CoreServices
    let home: HomeProfile?
    @Bindable var model: HomeModel
    let onSwitchProfile: () -> Void
    /// Bumped by the shell when double-tap Back returns to Home's root: focus goes to the hero, the page to the top.
    var rootRequest = 0
    /// Pushes a title or series page on Home's stack (WP-11).
    var onOpen: (ShellRoute) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.perchStyle) private var style
    @FocusState private var focus: HomeFocus?
    /// False in the first frame: rows sit at opacity 0 and fade up in turn (spec 7).
    @State private var revealed = false
    @State private var started = false
    /// The card or button that started playback, so Back from the player lands on it.
    @State private var playbackOrigin: HomeFocus?
    /// The card that opened a title or series page, so Back from it lands on the card.
    @State private var pageOrigin: HomeFocus?

    private static let log = Logger(subsystem: "com.robrolabs.perch", category: "home")
    private static let topID = "home.scroll.top"
    /// Brings a row's header to the 60 pt top margin when one of its cards takes focus (spec 3.2).
    private static let rowAnchor = UnitPoint(x: 0.5, y: PerchSpacing.topMargin / 1080)

    private var memory: FocusMemory { .shared }
    private var scope: FocusMemory.Scope { .init(profileID: home?.profile.id.rawValue ?? "", screen: HomeFocus.screen) }
    /// Where focus lands when it comes back into Home from the sidebar: the last focused card or the hero (WP-13).
    private var restoredFocus: HomeFocus {
        if let last = memory.lastFocus(HomeFocus.self, in: scope), isPresent(last) { return last }
        return .hero
    }
    private var playerActive: Bool { core.playback.activeSession != nil }
    private var serverUnreachable: Bool { core.plexSignIn.snapshot.state == .serverUnreachable }
    private var connecting: Bool { core.plexSignIn.snapshot.state == .connecting }

    var body: some View {
        ScrollViewReader { proxy in
            RowList {
                heroArea
                    .id(Self.topID)
                // Rows arriving or leaving animate inside their own stack only. Animating the whole RowList
                // also animated the scroll view's content size; when the focused message button left at the
                // same moment (cached empty library, then rows), the focus engine and the animated scroll
                // view re-laid out every frame for good: a blank screen at 100% CPU.
                VStack(alignment: .leading, spacing: PerchSpacing.rowGap) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, index: index)
                    }
                }
                .animation(.easeOut(duration: PerchMotion.crossfadeDuration), value: model.rows.map(\.id))
            }
            .ignoresSafeArea()
            .onChange(of: focus) { old, new in focusChanged(from: old, to: new, proxy: proxy) }
        }
        // Focus coming back from the sidebar (a tab switch, Back at the root) lands where it was (WP-13).
        .defaultFocus($focus, restoredFocus, priority: .userInitiated)
        .perchCornerNotice(isPresented: $model.offlineNotice, autoDismissAfter: .seconds(6)) {
            Text(HomeStrings.offlineCached)
                .font(PerchFont.body(style))
                .foregroundStyle(PerchColor.textPrimary)
                .accessibilityIdentifier("home.serverDown")
        }
        // On a card, Back goes to the hero (as the TV app does); at the hero (or with no hero) the shell's Back
        // applies, which moves focus to the sidebar (WP-13).
        .onExitCommand(perform: focus?.rowID != nil && model.heroItem != nil ? { focus = .hero } : nil)
        .onAppear { appeared() }
        .task { await start() }
        .onChange(of: rootRequest) { _, _ in returnToRoot() }
        .onChange(of: playerActive) { _, active in if !active { returnedFromPlayer() } }
        .onChange(of: serverUnreachable) { _, unreachable in model.serverStateChanged(unreachable: unreachable) }
        // Refresh once the server question is settled: ready fetches, unreachable fails and raises the notice.
        // A refresh while still connecting would fail and show the notice on a good launch.
        .onChange(of: connecting) { was, now in
            if was && !now { Task { await model.refresh() } }
        }
        .onChange(of: model.heroItem?.id) { _, _ in
            core.artworkPrefetcher.focus(item: model.heroItem)
            core.artworkTint.focus(model.heroItem)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.root")
    }

    // MARK: Lifecycle

    private func appeared() {
        #if DEBUG
        LaunchSignpost.homeFirstFrame()
        #endif
        if let origin = pageOrigin {
            pageOrigin = nil
            Task {
                // After the pop transition, so the focus engine takes the request.
                try? await Task.sleep(for: .milliseconds(250))
                if isPresent(origin) { focus = origin }
                // Something may have been watched from the page: Continue watching and Up next catch up.
                await model.refresh()
            }
        }
        guard !revealed else { return }
        if model.heroItem != nil {
            focus = .hero

        }
        if model.state == .content {
            revealed = true  // each row's own delayed animation runs the stagger
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { revealed = true }
        }
    }

    /// Rows 2 and 3 after the first frame, then the refresh; first launch waits at most 20 s for anything.
    private func start() async {
        guard !started else { return }
        started = true
        for row in model.rows.dropFirst() { Self.prefetch(row, with: core) }
        if model.state == .firstLaunch, serverUnreachable { model.serverStateChanged(unreachable: true) }
        // While the session is still connecting (Home shown from the snapshot at launch), `connecting` ending
        // starts the refresh instead.
        let refreshing = connecting ? nil : Task { await model.refresh() }
        if model.state == .firstLaunch {
            // Home going away cancels the wait; it must not resolve the state early.
            do { try await Task.sleep(for: HomeModel.firstLaunchTimeout) } catch { return }
            model.firstLaunchTimedOut()
        }
        await refreshing?.value
    }

    private func returnedFromPlayer() {
        guard let origin = playbackOrigin else { return }
        playbackOrigin = nil
        Task {
            // After the cover has gone, so the focus engine takes the request.
            try? await Task.sleep(for: .milliseconds(150))
            focus = origin
            try? await Task.sleep(for: .seconds(1))
            await model.refresh()
        }
    }

    /// Double-tap Back: the hero (or the first card when there is none), the page at the top.
    private func returnToRoot() {
        let first = model.rows.first?.items.first.map { HomeFocus.card(row: model.rows[0].id, item: $0.id) }
        Task {
            // After the tab switch has settled, so the focus engine takes the request.
            try? await Task.sleep(for: .milliseconds(150))
            focus = model.heroItem != nil ? .hero : first
        }
    }

    /// The focus target still exists on the page.
    private func isPresent(_ target: HomeFocus) -> Bool {
        switch target {
        case .hero: model.heroItem != nil
        case .card(let row, let item):
            model.rows.first(where: { $0.id == row })?.items.contains(where: { $0.id == item }) == true
        }
    }

    // MARK: Focus

    private func focusChanged(from old: HomeFocus?, to new: HomeFocus?, proxy: ScrollViewProxy) {
        guard let new else { return }
        // Entering a row from another row or the hero: its remembered card, when that card is still there.
        // Coming in from the sidebar (old is nil) the default focus has already chosen the remembered place.
        if case .card(let row, let item) = new, old != nil, old?.rowID != row,
            let remembered = memory.rememberedItem(group: row, in: scope), remembered != item,
            model.rows.first(where: { $0.id == row })?.items.contains(where: { $0.id == remembered }) == true
        {
            focus = .card(row: row, item: remembered)
            return
        }
        memory.record(new, in: scope, group: new.rowID, item: new.itemID)
        withAnimation(PerchMotion.spring) {
            if let row = new.rowID {
                proxy.scrollTo(Self.anchorID(row), anchor: Self.rowAnchor)
            } else {
                proxy.scrollTo(Self.topID, anchor: .top)
            }
        }
        // The next row's artwork as a row takes focus.
        if let row = new.rowID, let index = model.rows.firstIndex(where: { $0.id == row }),
            model.rows.indices.contains(index + 1)
        {
            Self.prefetch(model.rows[index + 1], with: core)
        }
    }

    private static func anchorID(_ rowID: String) -> String { "home.scroll.\(rowID)" }

    // MARK: Hero

    @ViewBuilder
    private var heroArea: some View {
        Group {
            switch model.state {
            case .content:
                if let item = model.heroItem {
                    hero(item)
                } else {
                    // Rows but no hero pick (only Up next, or only episodes): a header for the menu.
                    Color.clear.frame(height: 160).containerRelativeFrame(.horizontal)
                }
            case .firstLaunch:
                Text(HomeStrings.firstLaunch)
                    .font(PerchFont.body(style))
                    .foregroundStyle(PerchColor.textHelper)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .containerRelativeFrame(.horizontal)
                    .containerRelativeFrame(.vertical) { height, _ in height * 0.8 }
                    .accessibilityIdentifier("home.message")
            case .emptyLibrary:
                HeroMessage(
                    title: HomeStrings.emptyTitle, message: HomeStrings.emptyMessage,
                    secondary: .init(HomeStrings.checkAgain, identifier: "home.message.secondary") {
                        Task { await model.refresh() }
                    }
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.message")
            case .offlineNoCache:
                HeroMessage(
                    title: HomeStrings.offlineTitle, message: HomeStrings.offlineMessage,
                    primary: .init(HomeStrings.tryAgain, identifier: "home.retry") {
                        Task {
                            await core.plexSignIn.resume()
                            await model.refresh()
                        }
                    },
                    secondary: .init(HomeStrings.switchProfile, identifier: "home.message.secondary") { onSwitchProfile() }
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.message")
            }
        }
        // The whole hero width is one focus section, so Up from any card in row 1 reaches the hero button.
        .focusSection()
        // With a hero up and nothing on Home focused, focus is in the sidebar: the expanded panel's glass would
        // show the 96 pt title through it, cut at its edge, so the hero text fades back (WP-13). The system's
        // own dimming of unfocused content still applies.
        .environment(\.perchHeroDimmed, focus == nil && model.heroItem != nil)
        .transition(.opacity)
        .animation(.easeInOut(duration: PerchMotion.crossfadeDuration), value: model.state)
    }

    @ViewBuilder
    private func hero(_ item: MediaSummary) -> some View {
        let title = HomeStrings.heroTitle(item)
        let metadata = HomeStrings.heroMetadata(item)
        Group {
            if let logo = item.logoPath {
                HeroCard(
                    title: title, synopsis: item.summary ?? "", metadata: metadata,
                    titleIdentifier: "home.hero.title",
                    backdrop: { heroBackdrop(item) },
                    logo: { HeroLogo(path: logo, title: title) },
                    actions: { heroButton(item) })
            } else {
                HeroCard(
                    title: title, synopsis: item.summary ?? "", metadata: metadata,
                    titleIdentifier: "home.hero.title",
                    backdrop: { heroBackdrop(item) },
                    actions: { heroButton(item) })
            }
        }
        // A hero change after a refresh crossfades in place; no re-entrance (spec 7).
        .animation(.easeInOut(duration: 0.5), value: item.id)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.hero")
    }

    private func heroBackdrop(_ item: MediaSummary) -> some View {
        ArtworkImage(path: item.artworkPath(for: .backdrop), size: .backdrop)
    }

    private func heroButton(_ item: MediaSummary) -> some View {
        let resumes = model.heroResumes
        let row = resumes ? HomeRowID.continueWatching : HomeRowID.recentlyAdded
        return Button {
            select(item, row: row, origin: .hero)
        } label: {
            Label(resumes ? HomeStrings.resume : HomeStrings.play, systemImage: "play.fill")
        }
        .buttonStyle(.perchPrimary)
        .focused($focus, equals: .hero)
        .accessibilityIdentifier("home.hero.action")
    }

    // MARK: Rows

    private func rowView(_ row: MediaRow, index: Int) -> some View {
        Row(id: row.id, title: HomeStrings.rowTitle(row)) {
            ForEach(row.items) { item in card(item, row: row) }
        }
        .animation(PerchMotion.spring, value: row.items.map(\.id))
        .overlay(alignment: .top) { Color.clear.frame(height: 1).id(Self.anchorID(row.id)) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.row.\(row.id)")
        // Entrance: rows at 0.25, 0.35, 0.45 s, a 12 pt slide and a 0.3 s fade (fade only with Reduce Motion).
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed || reduceMotion ? 0 : PerchMotion.heroTextOffset)
        .animation(
            .easeOut(duration: PerchMotion.crossfadeDuration).delay(0.25 + 0.1 * Double(min(index, 2))), value: revealed
        )
        .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : PerchMotion.heroTextOffset)))
    }

    @ViewBuilder
    private func card(_ item: MediaSummary, row: MediaRow) -> some View {
        let caption = HomeStrings.caption(for: item, in: row.id)
        let key = HomeFocus.card(row: row.id, item: item.id)
        Group {
            if row.id == HomeRowID.recentlyAdded {
                PosterCard(title: caption.title, subtitle: caption.subtitle, action: { select(item, row: row.id, origin: key) }) {
                    ArtworkImage(path: item.artworkPath(for: .poster), size: .poster)
                }
            } else {
                LandscapeCard(
                    title: caption.title, subtitle: caption.subtitle,
                    progress: row.id == HomeRowID.continueWatching ? item.progress : nil,
                    action: { select(item, row: row.id, origin: key) }
                ) {
                    ArtworkImage(path: Self.landscapePath(item), size: .landscape)
                }
            }
        }
        .focused($focus, equals: key)
        // Play/Pause plays, as on the grids: a series or season card plays its next episode; Select opens the page.
        .onPlayPauseCommand { select(item, row: row.id, origin: key, playing: true) }
        .contextMenu {
            // Long-press (WP-11, as the grids' menu): the page behind a card that plays at once.
            if item.kind == .film || item.kind == .episode, let page = TitleRoute.page(for: item) {
                Button(item.kind == .film ? TitleStrings.details : TitleStrings.goToSeries) { open(page, origin: key) }
            }
        }
        .animation(.easeInOut(duration: PerchMotion.crossfadeDuration), value: item.viewOffsetMs)
        .accessibilityIdentifier("home.card.\(item.id)")
        .transition(.opacity)
    }

    /// Landscape cards: the episode still; a film shows its backdrop (not the poster cropped), spec 3.2.
    static func landscapePath(_ item: MediaSummary) -> String? {
        item.kind == .episode ? (item.thumbPath ?? item.artPath) : (item.artPath ?? item.thumbPath)
    }

    /// Prefetches a row's card artwork at the size its cards show.
    static func prefetch(_ row: MediaRow, with core: CoreServices) {
        if row.id == HomeRowID.recentlyAdded {
            core.artworkPrefetcher.prefetch(row: row.items, size: .poster)
        } else {
            // The prefetcher asks each item for its landscape path; hand it the path the card shows.
            let items = row.items.map { item -> MediaSummary in
                var copy = item
                copy.thumbPath = landscapePath(item)
                return copy
            }
            core.artworkPrefetcher.prefetch(row: items, size: .landscape)
        }
    }

    // MARK: Select

    /// Spec 5: Continue watching resumes; Up next and a Recently added film play from the start (two-click resume);
    /// a series or season card opens the series page (WP-11), unless Play/Pause pressed it (`playing`). The hero's
    /// button still plays a series directly.
    private func select(_ item: MediaSummary, row: String, origin: HomeFocus, playing: Bool = false) {
        if !playing, origin != .hero, item.kind == .series || item.kind == .season, let page = TitleRoute.page(for: item) {
            open(page, origin: origin)
            return
        }
        playbackOrigin = origin
        if item.kind == .series {
            Task { await playSeries(item.id) }
        } else if item.kind == .season, let seriesID = item.seriesID {
            // A season has no media of its own: its first unwatched episode, through the series path.
            Task { await playSeries(seriesID, season: item.id) }
        } else if row == HomeRowID.continueWatching {
            core.playback.play(item)
        } else {
            core.playback.play(item, startMs: 0)
        }
    }

    private func open(_ page: ShellRoute, origin: HomeFocus) {
        pageOrigin = origin
        onOpen(page)
    }

    private func playSeries(_ seriesID: String, season seasonID: String? = nil) async {
        // The series page's rule (`SeriesNext`), so the hero, Play/Pause and the page agree; a season plays within it.
        let episodes = (try? await core.library.allEpisodes(ofSeries: seriesID)) ?? []
        if let next = SeriesNext.choose(in: episodes, seasonID: seasonID) {
            core.playback.play(next.episode, startMs: next.startMs)
            return
        }
        // No episode list: the series' Up next episode, when there is one.
        let upNext = model.rows.first { $0.id == HomeRowID.upNext }?.items.first { $0.seriesID == seriesID }
        if let upNext {
            core.playback.play(upNext, startMs: 0)
        } else {
            Self.log.notice("Home: no episode to play for series \(seriesID, privacy: .public)")
        }
    }
}

/// The hero's clearLogo, fitted and bottom-left in its 600 x 140 box; the title text if the image fails.
struct HeroLogo: View {
    @Environment(ArtworkService.self) private var service: ArtworkService?
    @Environment(\.perchStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let path: String
    let title: String

    var body: some View {
        if let service, let request = service.request(path: path, size: .logo, priority: .high) {
            LazyImage(request: request, transaction: Transaction(animation: reduceMotion ? nil : .easeInOut(duration: 0.3))) {
                state in
                if let image = state.image {
                    image.resizable().scaledToFit()
                        .frame(maxWidth: 600, maxHeight: 140, alignment: .bottomLeading)
                        .transition(.opacity)
                } else if state.error != nil {
                    fallback
                } else {
                    Color.clear
                }
            }
            .pipeline(service.pipeline)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
        } else {
            fallback
        }
    }

    private var fallback: some View {
        Text(title)
            .font(PerchFont.hero(style))
            .foregroundStyle(PerchColor.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .shadow(color: .black.opacity(0.4), radius: 2, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}
