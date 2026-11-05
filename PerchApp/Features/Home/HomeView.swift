import NukeUI
import OSLog
import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI
import UIKit

/// The Home screen (docs/design/wp-09-home.md): the hero, then up to three rows, from the cached rows in the
/// first frame and refreshed in place. Never a spinner.
struct HomeView: View {
    let core: CoreServices
    let home: HomeProfile?
    @Bindable var model: HomeModel
    let onSwitchProfile: () -> Void
    let onRunSetup: () -> Void
    let onGallery: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.perchStyle) private var style
    @FocusState private var focus: HomeFocus?
    /// False in the first frame: rows sit at opacity 0 and fade up in turn (spec 7).
    @State private var revealed = false
    @State private var started = false
    @State private var menuShown = false
    @State private var avatar: UIImage?
    /// The card or button that started playback, so Back from the player lands on it.
    @State private var playbackOrigin: HomeFocus?

    private static let log = Logger(subsystem: "com.robrolabs.perch", category: "home")
    private static let topID = "home.scroll.top"
    /// Brings a row's header to the 60 pt top margin when one of its cards takes focus (spec 3.2).
    private static let rowAnchor = UnitPoint(x: 0.5, y: PerchSpacing.topMargin / 1080)

    private var memory: HomeFocusMemory { .shared }
    private var profileID: String { home?.profile.id.rawValue ?? "" }
    private var playerActive: Bool { core.playback.activeSession != nil }
    private var serverUnreachable: Bool { core.plexSignIn.snapshot.state == .serverUnreachable }

    var body: some View {
        ScrollViewReader { proxy in
            RowList {
                heroArea
                    .id(Self.topID)
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    rowView(row, index: index)
                }
            }
            .animation(.easeOut(duration: PerchMotion.crossfadeDuration), value: model.rows.map(\.id))
            .ignoresSafeArea()
            .onChange(of: focus) { old, new in focusChanged(from: old, to: new, proxy: proxy) }
        }
        .defaultFocus($focus, .hero)
        .perchCornerNotice(isPresented: $model.offlineNotice, autoDismissAfter: .seconds(6)) {
            Text(HomeStrings.offlineCached)
                .font(PerchFont.body(style))
                .foregroundStyle(PerchColor.textPrimary)
                .accessibilityIdentifier("home.serverDown")
        }
        .perchTopSheet(isPresented: $menuShown) { menuSheet }
        // On a card, Back goes to the hero (as the TV app does); at the hero the system's Back applies.
        .onExitCommand(perform: focus?.rowID != nil ? { focus = .hero } : nil)
        .onAppear { appeared() }
        .task { await start() }
        .task(id: home?.profile.id) { await loadAvatar() }
        .onChange(of: playerActive) { _, active in if !active { returnedFromPlayer() } }
        .onChange(of: serverUnreachable) { _, unreachable in
            model.serverStateChanged(unreachable: unreachable)
            if !unreachable { Task { await model.refresh() } }
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
        guard !revealed else { return }
        if model.heroItem != nil { focus = .hero }
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
        async let refresh: Void = model.refresh()
        if model.state == .firstLaunch {
            try? await Task.sleep(for: HomeModel.firstLaunchTimeout)
            model.firstLaunchTimedOut()
        }
        await refresh
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

    private func loadAvatar() async {
        guard let home else { return }
        let users = await core.plexSignIn.session.cachedHomeUsers()
        guard let user = users.first(where: { $0.id == home.profile.id.rawValue }),
            let request = await core.artwork.avatarRequest(thumb: user.thumb)
        else { return }
        if let image = core.artwork.cachedImage(request) {
            avatar = image
        } else {
            avatar = await core.artwork.image(request)
        }
    }

    // MARK: Focus

    private func focusChanged(from old: HomeFocus?, to new: HomeFocus?, proxy: ScrollViewProxy) {
        guard let new else { return }
        // Up from a row lands on the hero button, never on the profile menu above it (spec 5).
        if new == .profileMenu, old?.rowID != nil, model.heroItem != nil {
            focus = .hero
            return
        }
        // Entering a row from elsewhere: its remembered card, when that card is still there.
        if case .card(let row, let item) = new, old?.rowID != row,
            let remembered = memory.rememberedItem(row: row, profileID: profileID), remembered != item,
            model.rows.first(where: { $0.id == row })?.items.contains(where: { $0.id == remembered }) == true
        {
            focus = .card(row: row, item: remembered)
            return
        }
        memory.record(new, profileID: profileID)
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
        .overlay(alignment: .topTrailing) { profileMenu }
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

    /// Top-right, scrolls with the hero; its column is a focus section so Right from the hero button reaches it.
    private var profileMenu: some View {
        let name = home?.profile.displayName ?? ""
        return VStack {
            ProfileMenuButton(name: name, action: { menuShown = true }) {
                ProfileAvatarImage(name: name, size: 44, image: avatar.map { Image(uiImage: $0).resizable() })
            }
            .focused($focus, equals: .profileMenu)
            .accessibilityIdentifier("home.profileMenu")
            Spacer(minLength: 0)
        }
        .padding(.top, PerchSpacing.topMargin)
        .padding(.trailing, PerchSpacing.horizontalMargin)
        .frame(maxHeight: .infinity, alignment: .top)
        .focusSection()
    }

    private var menuSheet: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text(home?.profile.displayName ?? "")
                .font(PerchFont.section(style))
                .foregroundStyle(PerchColor.textPrimary)
            HStack(spacing: 24) {
                Button(HomeStrings.switchProfile) {
                    menuShown = false
                    onSwitchProfile()
                }
                .buttonStyle(.perchPrimary)
                .accessibilityIdentifier("home.switchProfile")
                if home?.isKid == true {
                    // A kid sees why there is no setup control (spec 6, kid profile).
                    Text(HomeStrings.askParent)
                        .font(PerchFont.body(style))
                        .foregroundStyle(PerchColor.textSecondary)
                        .accessibilityIdentifier("home.setupRefused")
                } else {
                    Button(HomeStrings.runSetup) {
                        menuShown = false
                        onRunSetup()
                    }
                    .buttonStyle(.perchSecondary)
                    .accessibilityIdentifier("home.runSetup")
                }
                if let onGallery {
                    Button("Design gallery") {
                        menuShown = false
                        onGallery()
                    }
                    .buttonStyle(.perchSecondary)
                    .accessibilityIdentifier("placeholder.gallery")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .onPlayPauseCommand { select(item, row: row.id, origin: key) }
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

    /// Spec 5: Continue watching resumes; Up next and a Recently added film play from the start; a series
    /// plays its first unwatched episode, else S1 E1.
    private func select(_ item: MediaSummary, row: String, origin: HomeFocus) {
        playbackOrigin = origin
        if item.kind == .series {
            Task { await playSeries(item) }
        } else if row == HomeRowID.continueWatching {
            core.playback.play(item)
        } else {
            core.playback.play(item, startMs: 0)
        }
    }

    private func playSeries(_ series: MediaSummary) async {
        let episodes = (try? await core.library.allEpisodes(ofSeries: series.id)) ?? []
        if let episode = HomeModel.episodeToPlay(in: episodes) {
            core.playback.play(episode)
            return
        }
        // No episode list: the series' Up next episode, when there is one.
        let upNext = model.rows.first { $0.id == HomeRowID.upNext }?.items.first { $0.seriesID == series.id }
        if let upNext {
            core.playback.play(upNext, startMs: 0)
        } else {
            Self.log.notice("Home: no episode to play for series \(series.id, privacy: .public)")
        }
    }
}

/// The hero's clearLogo, fitted and bottom-left in its 600 x 140 box; the title text if the image fails.
private struct HeroLogo: View {
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
