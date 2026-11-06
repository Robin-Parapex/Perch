import OSLog
import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI
import UIKit

/// Films or Series (WP-10, SPEC 4): a header with the section title, sort and filter chips, a Collections row, and
/// a poster grid paged in as focus nears the end, never a spinner. Sorted by title, a letter rail on the trailing
/// edge jumps to a letter. Focus is remembered per profile, section, sort and filters; Back from a collection or
/// the player lands on the poster or card that opened it.
struct LibraryGridScreen: View {
    let core: CoreServices
    let home: HomeProfile
    /// Pushes a collection or a title page on the tab's stack.
    let onOpen: (ShellRoute) -> Void
    @State private var model: LibraryGridModel

    @Environment(\.perchStyle) private var style
    @FocusState private var focus: LibraryFocus?
    /// The poster or collection card that opened the player or a collection: focus returns to it.
    @State private var pendingRestore: LibraryFocus?
    /// False while a pushed page covers the grid.
    @State private var onScreen = true
    @State private var currentLetter: String?

    init(
        core: CoreServices, home: HomeProfile, kind: PlexLibrarySection.Kind,
        onOpen: @escaping (ShellRoute) -> Void
    ) {
        self.core = core
        self.home = home
        self.onOpen = onOpen
        _model = State(
            initialValue: LibraryGridModel(kind: kind, context: home.context, isKid: home.isKid, browser: core.library))
    }

    static let columnCount = LibraryGridLayout.columnCount
    /// Scroll anchors: the page top, and a zero-height mark just above the grid's first row.
    static let topAnchor = "library.top"
    static let gridAnchor = "library.gridTop"
    /// Where the grid's first row sits when it takes focus under the Collections row: low enough that the lifted
    /// poster clears the top margin, high enough that the Collections row is fully out of view.
    static let gridAnchorPoint = UnitPoint(x: 0, y: 72 / LibraryGridLayout.screenHeight)

    #if DEBUG
    @MainActor static var openedFirstCollection = false
    @MainActor static var openedFirstTitle = false
    #endif

    private var layout: LibraryGridLayout { LibraryGridLayout(showsRail: model.showsLetters) }
    private var showsCollections: Bool { !model.collections.isEmpty && model.filters.isEmpty }

    private var memory: FocusMemory { .shared }
    private var scope: FocusMemory.Scope { .init(profileID: home.profile.id.rawValue, screen: model.memoryScreen) }
    private var playerActive: Bool { core.playback.activeSession != nil }
    /// The grid loads once the session is ready: at launch the shell can show while it still connects (WP-09),
    /// and a load then would fail and show "Couldn't reach your library" on a good launch (seen live).
    private var sessionReady: Bool {
        if case .ready = core.plexSignIn.snapshot.state { true } else { false }
    }

    /// Where focus lands when it comes into the grid from the sidebar: the remembered place, else the first poster.
    private var restoredFocus: LibraryFocus? {
        if let last = memory.lastFocus(LibraryFocus.self, in: scope), isPresent(last) { return last }
        return model.items.first.map { .item($0.id) } ?? .control("sort")
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: PerchSpacing.rowGap) {
                        header.id(Self.topAnchor)
                        if showsCollections { collectionsRow }
                        VStack(alignment: .leading, spacing: 0) {
                            Color.clear.frame(height: 0).id(Self.gridAnchor)
                            content
                        }
                    }
                    .padding(.top, PerchSpacing.topMargin)
                    .padding(.bottom, 120)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollClipDisabled()
                if model.showsLetters {
                    LetterRail(
                        letters: model.letters.map(\.title), current: currentLetter, identifierPrefix: "library.letter"
                    ) { letter in
                        Task { await model.jump(to: letter) }
                    }
                    // Inside the 80 pt margin, in the gutter the grid leaves for it.
                    .padding(.trailing, PerchSpacing.horizontalMargin)
                    .transition(.opacity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("library.letters")
                }
            }
            .onChange(of: focus) { old, new in
                focusChanged(new)
                scrollForFocus(from: old, to: new, proxy: proxy)
            }
        }
        .animation(.easeInOut(duration: PerchMotion.crossfadeDuration), value: model.showsLetters)
        .ignoresSafeArea()
        .defaultFocus($focus, restoredFocus, priority: .userInitiated)
        .onChange(of: model.focusRequest.token) { _, _ in moveFocus(to: model.focusRequest.target) }
        .onChange(of: model.items.count) { old, new in prefetchArrived(from: old, to: new) }
        // A page pushed over the grid plays from there: the grid restores only when it is on screen again.
        .onChange(of: playerActive) { _, active in if !active, onScreen { restorePending() } }
        .onAppear {
            onScreen = true
            restorePending()
        }
        .onDisappear { onScreen = false }
        #if DEBUG
        // `-PerchOpenFirstCollection` (DEBUG): opens the first collection once it loads, for live screenshots.
        .onChange(of: model.collections.first?.id) { _, id in
            guard id != nil, !Self.openedFirstCollection,
                ProcessInfo.processInfo.arguments.contains("-PerchOpenFirstCollection"),
                let first = model.collections.first
            else { return }
            Self.openedFirstCollection = true
            open(first)
        }
        // `-PerchOpenFirstTitle` (DEBUG, WP-11): opens the first title's page once it loads, for live screenshots.
        .onChange(of: model.items.first?.id) { _, id in
            guard id != nil, !Self.openedFirstTitle,
                ProcessInfo.processInfo.arguments.contains("-PerchOpenFirstTitle"),
                let first = model.items.first
            else { return }
            Self.openedFirstTitle = true
            select(first)
        }
        #endif
        .task(id: sessionReady) { if sessionReady { await model.startOrRetry() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.root")
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 24) {
            // No page title: the collapsed sidebar's own capsule ("Films") sits top left on tvOS 27 and covered it.
            // The chips start below that capsule.
            Color.clear.frame(height: 57)
            if model.sections.count > 1 {
                HStack(spacing: 16) {
                    ForEach(model.sections) { section in
                        Button { Task { await model.select(section: section) } } label: {
                            FilterChipLabel(section.title, showsChevron: false)
                        }
                        .buttonStyle(.perchChip(active: section.id == model.section?.id))
                        .accessibilityIdentifier("library.section.\(section.id)")
                    }
                }
                .focusSection()
            }
            HStack(spacing: 16) {
                // Sort is a different kind of control from the filters: its own gap.
                sortMenu.padding(.trailing, 24)
                filterMenu(
                    LibraryStrings.genre, id: "genre", choices: model.genres, selected: model.filters.genre
                ) { var f = model.filters; f.genre = $0; return f }
                filterMenu(
                    LibraryStrings.decade, id: "decade", choices: model.decades, selected: model.filters.decade
                ) { var f = model.filters; f.decade = $0; return f }
                filterMenu(
                    LibraryStrings.resolution, id: "resolution", choices: model.resolutions,
                    selected: model.filters.resolution
                ) { var f = model.filters; f.resolution = $0; return f }
                Button {
                    var filters = model.filters
                    filters.unwatched.toggle()
                    Task { await model.setFilters(filters) }
                } label: {
                    FilterChipLabel(
                        LibraryStrings.unwatched, systemImage: model.filters.unwatched ? "checkmark" : nil,
                        showsChevron: false)
                }
                .buttonStyle(.perchChip(active: model.filters.unwatched))
                .focused($focus, equals: .control("unwatched"))
                .accessibilityIdentifier("library.filter.unwatched")
                // No Collection chip: the Collections row covers it. No Clear chip while the empty state shows its
                // own "Clear filters" pill (one clear action).
                if model.filters.activeCount > 0, model.phase != .empty {
                    Button { Task { await model.clearFilters() } } label: {
                        FilterChipLabel(
                            LibraryStrings.clearFilters(count: model.filters.activeCount), systemImage: "xmark",
                            showsChevron: false)
                    }
                    .buttonStyle(.perchChip())
                    .focused($focus, equals: .control("clear"))
                    .accessibilityIdentifier("library.filter.clear")
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: PerchMotion.crossfadeDuration), value: model.filters.activeCount)
        }
        .padding(.leading, PerchSpacing.horizontalMargin)
        .focusSection()
    }

    private var sortMenu: some View {
        Menu {
            ForEach(LibrarySort.allCases, id: \.self) { sort in
                Button { Task { await model.setSort(sort) } } label: {
                    menuLabel(LibraryStrings.sortTitle(sort), selected: sort == model.sort)
                }
                .accessibilityIdentifier("library.sort.\(sort.rawValue)")
            }
        } label: {
            FilterChipLabel(
                LibraryStrings.sort, value: LibraryStrings.sortTitle(model.sort), systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.button)
        .buttonStyle(.perchChip())
        .focused($focus, equals: .control("sort"))
        .accessibilityIdentifier("library.sort")
    }

    @ViewBuilder
    private func filterMenu(
        _ title: String, id: String, choices: [LibraryFilterChoice], selected: LibraryFilterChoice?,
        applying: @escaping (LibraryFilterChoice?) -> LibraryFilters
    ) -> some View {
        if !choices.isEmpty {
            Menu {
                Button { Task { await model.setFilters(applying(nil)) } } label: {
                    menuLabel(LibraryStrings.any, selected: selected == nil)
                }
                ForEach(choices) { choice in
                    Button { Task { await model.setFilters(applying(choice)) } } label: {
                        menuLabel(choice.title, selected: choice == selected)
                    }
                    .accessibilityIdentifier("library.filter.\(id).\(choice.key)")
                }
            } label: {
                FilterChipLabel(title, value: selected?.title)
            }
            .menuStyle(.button)
            .buttonStyle(.perchChip(active: selected != nil))
            .focused($focus, equals: .control(id))
            .accessibilityIdentifier("library.filter.\(id)")
        }
    }

    @ViewBuilder
    private func menuLabel(_ title: String, selected: Bool) -> some View {
        if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    // MARK: Collections

    /// Grid-size cards on the grid's columns, so the row's edges line up with the grid's. With the letter rail
    /// showing, cards beyond the grid's right edge are masked so they never pass under the rail.
    private var collectionsRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LibraryStrings.collections)
                .font(PerchFont.section(style))
                .foregroundStyle(PerchColor.textPrimary)
                .padding(.leading, PerchSpacing.horizontalMargin)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: layout.gap) {
                    ForEach(model.collections) { collection in
                        PosterCard(
                            size: .grid, title: LibraryStrings.collectionTitle(collection.title),
                            subtitle: LibraryStrings.collectionCount(collection.childCount),
                            expandsTitleWhenFocused: true, action: { open(collection) }
                        ) {
                            ArtworkImage(path: collection.thumbPath, size: .poster)
                        }
                        .focused($focus, equals: .collection(collection.id))
                        .accessibilityIdentifier("library.collection.\(collection.id)")
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 40)
            }
            .contentMargins(.leading, PerchSpacing.horizontalMargin, for: .scrollContent)
            .contentMargins(.trailing, layout.trailingInset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .mask {
                Rectangle()
                    .padding(.trailing, model.showsLetters ? layout.trailingInset - 24 : -200)
                    .padding(.leading, -200)
                    .padding(.vertical, -80)
            }
            .focusSection()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.collections")
        .transition(.opacity)
    }

    // MARK: Grid

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .starting:
            LibraryPlaceholderGrid(count: 12, layout: layout)
        case .content:
            LazyVGrid(columns: layout.columns, alignment: .leading, spacing: 48) {
                ForEach(model.items) { item in
                    LibraryPoster(item: item, focus: $focus) { select(item) } onPlay: { play(item) } onWatched: { watched in
                        Task { await model.setWatched(watched, item: item) }
                    }
                }
                if model.hasMore {
                    ForEach(0..<Self.columnCount, id: \.self) { index in
                        LibraryPlaceholderTile().id("library.placeholder.\(index)")
                    }
                }
            }
            .padding(.leading, PerchSpacing.horizontalMargin)
            .focusSection()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("library.grid")
            .transition(.opacity)
        case .empty:
            if model.filters.isEmpty {
                LibraryMessage(title: LibraryStrings.emptyTitle(model.kind), message: LibraryStrings.emptyMessage(model.kind))
            } else {
                LibraryMessage(
                    title: LibraryStrings.noMatchesTitle, message: LibraryStrings.noMatchesMessage,
                    action: .init(LibraryStrings.clearFilters, identifier: "library.empty.clear") {
                        Task { await model.clearFilters() }
                    })
            }
        case .failed:
            LibraryMessage(
                title: LibraryStrings.failedTitle, message: LibraryStrings.failedMessage,
                action: .init(LibraryStrings.tryAgain, identifier: "library.retry") { Task { await model.retry() } })
        }
    }

    // MARK: Focus

    private func isPresent(_ target: LibraryFocus) -> Bool {
        switch target {
        case .item(let id): model.items.contains { $0.id == id }
        case .collection(let id): model.collections.contains { $0.id == id } && model.filters.isEmpty
        case .control, .letter: true
        }
    }

    private func focusChanged(_ new: LibraryFocus?) {
        guard let new else { return }
        memory.record(new, in: scope)
        guard case .item(let id) = new, let item = model.items.first(where: { $0.id == id }) else { return }
        core.artworkTint.focus(item)
        currentLetter = model.letter(of: id)
        Task { await model.focusMoved(to: id) }
    }

    /// Keeps the Collections row whole: focus on the grid's first row scrolls it fully out of view; focus on the
    /// header or a collection card brings the page back to its top. Only while the Collections row shows.
    private func scrollForFocus(from old: LibraryFocus?, to new: LibraryFocus?, proxy: ScrollViewProxy) {
        guard showsCollections, let new else { return }
        let animation: Animation? =
            UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: PerchMotion.crossfadeDuration)
        switch new {
        case .item(let id):
            guard let index = model.items.firstIndex(where: { $0.id == id }), index < Self.columnCount else { return }
            if case .item(let oldID) = old, let oldIndex = model.items.firstIndex(where: { $0.id == oldID }),
                oldIndex < Self.columnCount
            {
                return  // moving along the first row: already placed
            }
            withAnimation(animation) { proxy.scrollTo(Self.gridAnchor, anchor: Self.gridAnchorPoint) }
        case .collection, .control:
            switch old {
            case .collection, .control: return
            default: withAnimation(animation) { proxy.scrollTo(Self.topAnchor, anchor: .top) }
            }
        case .letter:
            return
        }
    }

    /// After a sort, filter or letter change: the first item (or the letter's first title).
    private func moveFocus(to target: LibraryFocus?) {
        guard let target else { return }
        Task {
            // After the grid has laid out the new items and a closing menu has handed focus back to its chip (which
            // it does after its own animation), so the request sticks. Re-asserted only while focus is still on the
            // header or the rail, never over a move the viewer made.
            for delay in [150, 350, 500] {
                try? await Task.sleep(for: .milliseconds(delay))
                switch focus {
                case .item, .collection: if focus != target { return }
                default: break
                }
                if focus == target { continue }
                focus = target
            }
        }
    }

    private func restorePending() {
        guard let target = pendingRestore else { return }
        pendingRestore = nil
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            if isPresent(target) { focus = target }
        }
    }

    /// The page that just arrived lies beyond the screen: warm its posters.
    private func prefetchArrived(from old: Int, to new: Int) {
        guard new > old, old > 0 || new > 18 else { return }
        let start = old == 0 ? min(18, new) : old
        core.artworkPrefetcher.prefetch(row: Array(model.items[start..<new]), size: .poster)
    }

    // MARK: Actions

    /// Select opens the title or series page (WP-11); Play is on the page, two clicks from the grid.
    private func select(_ item: MediaSummary) {
        pendingRestore = .item(item.id)
        if let route = TitleRoute.page(for: item) {
            onOpen(route)
        } else {
            Task { await LibraryPlayback.play(item, core: core) }
        }
    }

    /// Play/Pause on a poster plays at once, as on Home.
    private func play(_ item: MediaSummary) {
        pendingRestore = .item(item.id)
        Task { await LibraryPlayback.play(item, core: core) }
    }

    private func open(_ collection: PlexCollection) {
        guard let section = model.section else { return }
        pendingRestore = .collection(collection.id)
        onOpen(
            .collection(
                LibraryCollectionRoute(
                    sectionID: section.id, kind: model.kind, collectionID: collection.id,
                    title: LibraryStrings.collectionTitle(collection.title), summary: collection.summary,
                    artPath: collection.artPath, thumbPath: collection.thumbPath)))
    }
}

// MARK: - Shared pieces

/// A grid poster: title and year, progress for a started film, long-press to mark watched or unwatched or open the
/// page. Select opens the title page, Play/Pause plays (WP-11).
struct LibraryPoster: View {
    let item: MediaSummary
    var focus: FocusState<LibraryFocus?>.Binding
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onWatched: (Bool) -> Void

    var body: some View {
        let caption = LibraryStrings.caption(item)
        PosterCard(
            size: .grid, title: caption.title, subtitle: caption.subtitle,
            progress: item.kind == .film && item.isInProgress ? item.progress : nil,
            expandsTitleWhenFocused: true, action: onSelect
        ) {
            ArtworkImage(path: item.artworkPath(for: .poster), size: .poster)
                .overlay(alignment: .topTrailing) {
                    if item.isWatched { WatchedTick().padding(12) }
                }
        }
        .focused(focus, equals: .item(item.id))
        .onPlayPauseCommand(perform: onPlay)
        .contextMenu {
            Button(item.isWatched ? LibraryStrings.markUnwatched : LibraryStrings.markWatched) {
                onWatched(!item.isWatched)
            }
        }
        .accessibilityIdentifier("library.item.\(item.id)")
    }
}

/// The small tick on a watched poster (in place of a "Watched" caption).
struct WatchedTick: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.black.opacity(0.6)))
            .accessibilityLabel("Watched")
            .accessibilityIdentifier("library.watched")
    }
}

/// The grid's columns: six posters, 80 pt margins. Without the letter rail they spread evenly from x 80 to x 1840
/// (64 pt gaps). With it, a fixed gutter (rail plus 40 pt) is reserved inside the right margin and the six columns
/// fill what remains, so the grid and the Collections row end at the same edge.
struct LibraryGridLayout: Equatable {
    static let screenWidth: CGFloat = 1920
    static let screenHeight: CGFloat = 1080
    static let columnCount = 6
    static let railWidth: CGFloat = 56
    static let railGap: CGFloat = 40

    /// Space between columns.
    let gap: CGFloat
    /// From the grid's right edge to the screen's.
    let trailingInset: CGFloat

    init(showsRail: Bool) {
        let margin = PerchSpacing.horizontalMargin
        let right = Self.screenWidth - margin - (showsRail ? Self.railWidth + Self.railGap : 0)
        let available = right - margin
        let posters = CGFloat(Self.columnCount) * PerchSize.posterGrid.width
        gap = ((available - posters) / CGFloat(Self.columnCount - 1)).rounded(.down)
        trailingInset = Self.screenWidth - margin - Self.width(gap: gap)
    }

    static func width(gap: CGFloat) -> CGFloat {
        CGFloat(columnCount) * PerchSize.posterGrid.width + CGFloat(columnCount - 1) * gap
    }

    var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(PerchSize.posterGrid.width), spacing: gap, alignment: .top),
            count: Self.columnCount)
    }
}

/// A poster-shaped stand-in while a page is on its way: the quiet artwork wash, no indicator, not focusable.
struct LibraryPlaceholderTile: View {
    @Environment(\.perchStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArtworkPlaceholder(image: nil, tint: nil)
                .frame(width: PerchSize.posterGrid.width, height: PerchSize.posterGrid.height)
                .clipShape(RoundedRectangle(cornerRadius: PerchRadius.card(for: style), style: .continuous))
            Color.clear.frame(height: 80)
        }
        .accessibilityHidden(true)
    }
}

struct LibraryPlaceholderGrid: View {
    let count: Int
    var layout = LibraryGridLayout(showsRail: false)

    var body: some View {
        LazyVGrid(columns: layout.columns, alignment: .leading, spacing: 48) {
            ForEach(0..<count, id: \.self) { _ in LibraryPlaceholderTile() }
        }
        .padding(.leading, PerchSpacing.horizontalMargin)
        .accessibilityIdentifier("library.placeholder")
    }
}

/// A centred message in the grid's place (nothing matches, nothing here yet, the server is away), styled as
/// `HeroMessage` but with fixed sizes: HeroMessage's container-relative frames inside the grid's scroll view
/// re-laid out every frame (the app never went idle).
struct LibraryMessage: View {
    let title: String
    let message: String
    var action: HeroMessage.Action?
    @Environment(\.perchStyle) private var style

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(PerchFont.stepTitle(style))
                .foregroundStyle(PerchColor.textPrimary)
                .multilineTextAlignment(.center)
            if !message.isEmpty {
                Text(message)
                    .font(PerchFont.body(style))
                    .foregroundStyle(PerchColor.textHelper)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            if let action {
                Button(action: action.run) {
                    Text(action.label)
                        .font(PerchFont.body(style).weight(.semibold))
                        .frame(minHeight: PerchSize.buttonMinHeight)
                }
                .buttonStyle(.perchPrimary)
                .accessibilityIdentifier(action.identifier ?? "library.message.action")
                .padding(.top, 20)
            }
        }
        .frame(width: 900)
        .frame(width: LibraryMessage.width, height: 520)
        .padding(.leading, PerchSpacing.horizontalMargin)
        .frame(width: LibraryGridLayout.screenWidth, alignment: .leading)
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.message")
    }

    /// The screen between the margins, so the message centres on the full width.
    static let width = LibraryGridLayout.screenWidth - 2 * PerchSpacing.horizontalMargin
}

/// Play/Pause on a library title (Select opens its page since WP-11): a film plays, resuming when started; a series
/// plays its next episode by the series page's rule (`SeriesNext`).
@MainActor
enum LibraryPlayback {
    static func play(_ item: MediaSummary, core: CoreServices) async {
        switch item.kind {
        case .series:
            let episodes = (try? await core.library.allEpisodes(ofSeries: item.id)) ?? []
            if let next = SeriesNext.choose(in: episodes, seasonID: nil) {
                core.playback.play(next.episode, startMs: next.startMs)
            } else {
                LibraryGridModel.log.notice("Library: no episode to play for series \(item.id, privacy: .public)")
            }
        default:
            core.playback.play(item, startMs: item.isInProgress ? nil : 0)
        }
    }
}
