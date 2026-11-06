import OSLog
import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI

/// Films or Series (WP-10, SPEC 4): a header with the section title, sort and filter chips, a Collections row, and
/// a poster grid paged in as focus nears the end, never a spinner. Sorted by title, a letter rail on the trailing
/// edge jumps to a letter. Focus is remembered per profile, section, sort and filters; Back from a collection or
/// the player lands on the poster or card that opened it.
struct LibraryGridScreen: View {
    let core: CoreServices
    let home: HomeProfile
    let onOpenCollection: (LibraryCollectionRoute) -> Void
    @State private var model: LibraryGridModel

    @Environment(\.perchStyle) private var style
    @FocusState private var focus: LibraryFocus?
    /// The poster or collection card that opened the player or a collection: focus returns to it.
    @State private var pendingRestore: LibraryFocus?
    @State private var currentLetter: String?

    init(
        core: CoreServices, home: HomeProfile, kind: PlexLibrarySection.Kind,
        onOpenCollection: @escaping (LibraryCollectionRoute) -> Void
    ) {
        self.core = core
        self.home = home
        self.onOpenCollection = onOpenCollection
        _model = State(initialValue: LibraryGridModel(kind: kind, context: home.context, browser: core.library))
    }

    static let columnCount = 6
    static let columnGap: CGFloat = 40
    static let columns = Array(
        repeating: GridItem(.fixed(PerchSize.posterGrid.width), spacing: columnGap, alignment: .top), count: columnCount)

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
        ZStack(alignment: .trailing) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: PerchSpacing.rowGap) {
                    header
                    if !model.collections.isEmpty, model.filters.isEmpty { collectionsRow }
                    content
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
                .padding(.trailing, 44)
                .transition(.opacity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("library.letters")
            }
        }
        .animation(.easeInOut(duration: PerchMotion.crossfadeDuration), value: model.showsLetters)
        .ignoresSafeArea()
        .defaultFocus($focus, restoredFocus, priority: .userInitiated)
        .onChange(of: focus) { _, new in focusChanged(new) }
        .onChange(of: model.focusRequest.token) { _, _ in moveFocus(to: model.focusRequest.target) }
        .onChange(of: model.items.count) { old, new in prefetchArrived(from: old, to: new) }
        .onChange(of: playerActive) { _, active in if !active { restorePending() } }
        .onAppear { restorePending() }
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
                sortMenu
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
                filterMenu(
                    LibraryStrings.collection, id: "collection",
                    choices: model.collections.map { LibraryFilterChoice(key: $0.id, title: $0.title) },
                    selected: model.filters.collection
                ) { var f = model.filters; f.collection = $0; return f }
                if model.filters.activeCount > 0 {
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

    private var collectionsRow: some View {
        Row(id: "library.collections", title: LibraryStrings.collections) {
            ForEach(model.collections) { collection in
                PosterCard(
                    title: collection.title, subtitle: LibraryStrings.collectionCount(collection.childCount),
                    action: { open(collection) }
                ) {
                    ArtworkImage(path: collection.thumbPath, size: .poster)
                }
                .focused($focus, equals: .collection(collection.id))
                .accessibilityIdentifier("library.collection.\(collection.id)")
            }
        }
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.collections")
        .transition(.opacity)
    }

    // MARK: Grid

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .starting:
            LibraryPlaceholderGrid(count: 12)
        case .content:
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 48) {
                ForEach(model.items) { item in
                    LibraryPoster(item: item, focus: $focus) { select(item) } onWatched: { watched in
                        Task { await model.setWatched(watched, item: item) }
                    }
                }
                if model.hasMore {
                    ForEach(0..<Self.columnCount, id: \.self) { _ in LibraryPlaceholderTile() }
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

    private func select(_ item: MediaSummary) {
        pendingRestore = .item(item.id)
        Task { await LibraryPlayback.play(item, core: core) }
    }

    private func open(_ collection: PlexCollection) {
        guard let section = model.section else { return }
        pendingRestore = .collection(collection.id)
        onOpenCollection(
            LibraryCollectionRoute(
                sectionID: section.id, kind: model.kind, collectionID: collection.id, title: collection.title))
    }
}

// MARK: - Shared pieces

/// A grid poster: title and year, progress for a started film, long-press to mark watched or unwatched.
struct LibraryPoster: View {
    let item: MediaSummary
    var focus: FocusState<LibraryFocus?>.Binding
    let onSelect: () -> Void
    let onWatched: (Bool) -> Void

    var body: some View {
        let caption = LibraryStrings.caption(item)
        PosterCard(
            size: .grid, title: caption.title, subtitle: caption.subtitle,
            progress: item.kind == .film && item.isInProgress ? item.progress : nil, action: onSelect
        ) {
            ArtworkImage(path: item.artworkPath(for: .poster), size: .poster)
        }
        .focused(focus, equals: .item(item.id))
        .onPlayPauseCommand(perform: onSelect)
        .contextMenu {
            Button(item.isWatched ? LibraryStrings.markUnwatched : LibraryStrings.markWatched) {
                onWatched(!item.isWatched)
            }
        }
        .accessibilityIdentifier("library.item.\(item.id)")
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

    var body: some View {
        LazyVGrid(columns: LibraryGridScreen.columns, alignment: .leading, spacing: 48) {
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
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.message")
    }

    /// The grid's width, so the message centres over where the posters were.
    static let width = CGFloat(LibraryGridScreen.columnCount) * PerchSize.posterGrid.width
        + CGFloat(LibraryGridScreen.columnCount - 1) * LibraryGridScreen.columnGap
}

/// Select on a library title (until title pages, WP-11): a film plays, resuming when started; a series plays its
/// first unwatched episode, else S1 E1, as Home's Recently added does (DECISIONS, WP-09).
@MainActor
enum LibraryPlayback {
    static func play(_ item: MediaSummary, core: CoreServices) async {
        switch item.kind {
        case .series:
            let episodes = (try? await core.library.allEpisodes(ofSeries: item.id)) ?? []
            if let episode = HomeModel.episodeToPlay(in: episodes) {
                core.playback.play(episode)
            } else {
                LibraryGridModel.log.notice("Library: no episode to play for series \(item.id, privacy: .public)")
            }
        default:
            core.playback.play(item, startMs: item.isInProgress ? nil : 0)
        }
    }
}
