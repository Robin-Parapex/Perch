import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI

/// The Search tab (WP-12, SPEC 7): the system search field and keyboard (`.searchable`), so holding the Siri button
/// while the field has focus dictates into it; library results in rows below: Films, Series, Episodes, Collections.
/// Select opens a title or series page (an episode plays, as on Home); Play/Pause plays, as on the grids. The query,
/// results and focused result survive leaving the tab or opening a page; a profile switch starts afresh.
struct SearchScreen: View {
    let core: CoreServices
    let home: HomeProfile
    let onOpen: (ShellRoute) -> Void

    @State private var model: SearchModel
    @State private var text: String
    @FocusState private var focus: SearchFocus?
    /// The result a page or the player was opened from; focus returns to it on Back.
    @State private var pendingRestore: SearchFocus?
    @Environment(\.perchStyle) private var style

    init(core: CoreServices, home: HomeProfile, onOpen: @escaping (ShellRoute) -> Void) {
        self.core = core
        self.home = home
        self.onOpen = onOpen
        let model = SearchStore.shared.model(for: home, core: core)
        _model = State(initialValue: model)
        _text = State(initialValue: model.query)
    }

    static let rowInsetCorrection: CGFloat = 40

    private var sessionReady: Bool {
        if case .ready = core.plexSignIn.snapshot.state { true } else { false }
    }

    private var memory: FocusMemory { .shared }
    private var scope: FocusMemory.Scope { .init(profileID: home.profile.id.rawValue, screen: SearchFocus.screen) }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The search content already sits inside the safe area; Row adds its own 80 pt margin. Pull the rows back
            // so their titles and first cards line up with the keyboard's first key (about x 120), not x 160.
            .padding(.leading, -Self.rowInsetCorrection)
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
        .searchable(text: $text, prompt: SearchStrings.prompt)
        .onChange(of: text) { _, new in model.setQuery(new) }
        .onChange(of: focus) { _, new in
            guard let new else { return }
            memory.record(new, in: scope)
            if case .item(_, let id) = new, let item = item(id) { core.artworkTint.focus(item) }
        }
        .onAppear(perform: restorePending)
        // A search made while the app was still connecting runs again once the session is ready.
        .task(id: sessionReady) { if sessionReady { model.sessionReady() } }
        .defaultFocus($focus, memory.lastFocus(SearchFocus.self, in: scope).flatMap { isPresent($0) ? $0 : nil })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.root")
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            SearchMessage(title: SearchStrings.hintTitle, message: SearchStrings.hintMessage, identifier: "search.hint")
        case .noResults:
            SearchMessage(
                title: SearchStrings.noResultsTitle, message: SearchStrings.noResultsMessage(model.shownQuery),
                identifier: "search.noResults")
        case .failed:
            SearchMessage(title: SearchStrings.failedTitle, message: SearchStrings.failedMessage, identifier: "search.failed")
        case .results:
            let results = model.results
            if !results.films.isEmpty { row(SearchStrings.films, group: "films", items: results.films, landscape: false) }
            if !results.series.isEmpty { row(SearchStrings.series, group: "series", items: results.series, landscape: false) }
            if !results.episodes.isEmpty { row(SearchStrings.episodes, group: "episodes", items: results.episodes, landscape: true) }
            if !results.collections.isEmpty { collectionsRow(results.collections) }
        }
    }

    private func row(_ title: String, group: String, items: [MediaSummary], landscape: Bool) -> some View {
        Row(id: group, title: title) {
            ForEach(items) { item in card(item, group: group, landscape: landscape) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.row.\(group)")
        .transition(.opacity)
    }

    @ViewBuilder
    private func card(_ item: MediaSummary, group: String, landscape: Bool) -> some View {
        let caption = SearchStrings.caption(item)
        let key = SearchFocus.item(group: group, id: item.id)
        Group {
            if landscape {
                LandscapeCard(
                    title: caption.title, subtitle: caption.subtitle,
                    progress: item.isInProgress ? item.progress : nil, action: { select(item, from: key) }
                ) {
                    ArtworkImage(path: HomeView.landscapePath(item), size: .landscape)
                }
            } else {
                PosterCard(title: caption.title, subtitle: caption.subtitle, action: { select(item, from: key) }) {
                    ArtworkImage(path: item.artworkPath(for: .poster), size: .poster)
                }
            }
        }
        .focused($focus, equals: key)
        .onPlayPauseCommand { play(item, from: key) }
        .contextMenu {
            if item.kind == .episode, let page = TitleRoute.page(for: item) {
                Button(TitleStrings.goToSeries) { open(page, from: key) }
            }
        }
        .accessibilityIdentifier("search.item.\(item.id)")
    }

    private func collectionsRow(_ collections: [PlexSearchCollection]) -> some View {
        Row(id: "collections", title: SearchStrings.collections) {
            ForEach(collections) { collection in
                let key = SearchFocus.item(group: "collections", id: collection.id)
                PosterCard(
                    title: LibraryStrings.collectionTitle(collection.title),
                    subtitle: LibraryStrings.collectionCount(collection.childCount),
                    action: { open(collection, from: key) }
                ) {
                    ArtworkImage(path: collection.thumbPath, size: .poster)
                }
                .focused($focus, equals: key)
                .accessibilityIdentifier("search.collection.\(collection.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.row.collections")
    }

    // MARK: Focus

    private func item(_ id: String) -> MediaSummary? {
        let results = model.results
        return (results.films + results.series + results.episodes).first { $0.id == id }
    }

    private func isPresent(_ target: SearchFocus) -> Bool {
        guard model.phase == .results, case .item(let group, let id) = target else { return false }
        let results = model.results
        switch group {
        case "films": return results.films.contains { $0.id == id }
        case "series": return results.series.contains { $0.id == id }
        case "episodes": return results.episodes.contains { $0.id == id }
        case "collections": return results.collections.contains { $0.id == id }
        default: return false
        }
    }

    /// Back from a page (or the player): focus returns to the result it was opened from, once the stack has popped.
    private func restorePending() {
        guard let target = pendingRestore else { return }
        pendingRestore = nil
        Task {
            for delay in [300, 400] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard isPresent(target), focus != target else { return }
                focus = target
            }
        }
    }

    // MARK: Actions

    /// Select: a film or series opens its page; an episode plays (resuming when started), as on Home.
    private func select(_ item: MediaSummary, from key: SearchFocus) {
        if item.kind != .episode, let page = TitleRoute.page(for: item) {
            open(page, from: key)
        } else {
            play(item, from: key)
        }
    }

    /// Play/Pause plays at once, as on the grids: a series plays its next episode.
    private func play(_ item: MediaSummary, from key: SearchFocus) {
        pendingRestore = key
        Task { await LibraryPlayback.play(item, core: core) }
    }

    private func open(_ page: ShellRoute, from key: SearchFocus) {
        pendingRestore = key
        onOpen(page)
    }

    private func open(_ collection: PlexSearchCollection, from key: SearchFocus) {
        guard let sectionID = collection.sectionID, let kind = collection.kind else { return }
        open(
            .collection(
                LibraryCollectionRoute(
                    sectionID: sectionID, kind: kind, collectionID: collection.id,
                    title: LibraryStrings.collectionTitle(collection.title), summary: collection.summary,
                    artPath: collection.artPath, thumbPath: collection.thumbPath)),
            from: key)
    }
}

/// A quiet message where the results go (nothing typed, nothing found). Fixed sizes: container-relative frames in a
/// scroll view kept the app from going idle (WP-10). Not focusable; the keyboard keeps focus.
private struct SearchMessage: View {
    let title: String
    let message: String
    let identifier: String
    @Environment(\.perchStyle) private var style

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(PerchFont.section(style))
                .foregroundStyle(PerchColor.textPrimary)
            if !message.isEmpty {
                Text(message)
                    .font(PerchFont.body(style))
                    .foregroundStyle(PerchColor.textHelper)
                    .lineLimit(2)
            }
        }
        .multilineTextAlignment(.center)
        .frame(width: 1200, height: 240)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        .transition(.opacity)
    }
}

/// Copy for Search, in sentence case (GLOSSARY): no service names.
enum SearchStrings {
    static let prompt = "Films and series"
    static let hintTitle = "Search films and series"
    static let hintMessage = "Type or hold the Siri button to speak a title."
    static let noResultsTitle = "No matches"
    static func noResultsMessage(_ query: String) -> String { "Nothing in your library matches \u{201C}\(query)\u{201D}." }
    static let failedTitle = "Search isn\u{2019}t available right now"
    static let failedMessage = "Check the connection, then try again."
    static let films = "Films"
    static let series = "Series"
    static let episodes = "Episodes"
    static let collections = "Collections"

    /// Films and series: title and year. Episodes: the episode's title over its series and number.
    static func caption(_ item: MediaSummary) -> (title: String, subtitle: String?) {
        guard item.kind == .episode else { return LibraryStrings.caption(item) }
        let number: String? =
            switch (item.seasonNumber, item.episodeNumber) {
            case (let season?, let episode?): "S\(season) E\(episode)"
            case (nil, let episode?): "E\(episode)"
            default: nil
            }
        let subtitle = [item.seriesTitle, number].compactMap { $0 }.joined(separator: " \u{00B7} ")
        return (item.title, subtitle.isEmpty ? nil : subtitle)
    }
}
