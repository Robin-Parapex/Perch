import Foundation
import Observation
import OSLog
import PerchCore
import PerchPlex

/// What a library grid needs from the library (PlexLibrary in the app, a fake in tests).
protocol LibraryBrowsing: Sendable {
    func sections() async throws -> [PlexLibrarySection]
    func makePager(query: PlexSectionQuery) async -> any LibraryPaging
    func firstCharacters(query: PlexSectionQuery) async throws -> [PlexLetterBucket]
    func filterValues(sectionID: String, kind: PlexFilterKind) async throws -> [PlexFilterValue]
    func collections(query: PlexSectionQuery) async throws -> [PlexCollection]
    func collectionItems(collectionID: String, query: PlexSectionQuery) async throws -> [MediaSummary]
    func admittedContentRatings(sectionID: String, ceiling: RatingCeiling) async throws -> Set<String>
    func setWatched(_ watched: Bool, itemID: String) async throws
}

protocol LibraryPaging: Sendable {
    func nextPage() async throws -> [MediaSummary]
    var isFinished: Bool { get async }
}

extension PlexSectionPager: LibraryPaging {}

extension PlexLibrary: LibraryBrowsing {
    func makePager(query: PlexSectionQuery) async -> any LibraryPaging { await pager(query: query) }

    func setWatched(_ watched: Bool, itemID: String) async throws {
        if watched { try await markWatched(itemID) } else { try await markUnwatched(itemID) }
    }
}

/// One Films or Series grid (WP-10): the sections of that kind, the chosen sort and filters, the items paged in
/// from the server with the rating ceiling applied, the letter buckets when sorted by title, and the section's
/// collections. A letter jump reloads from that letter's offset (`startOffset`), so the first item is the
/// letter's first title and focus can land on it.
@MainActor @Observable
final class LibraryGridModel {
    enum Phase: Equatable { case starting, content, empty, failed }

    let kind: PlexLibrarySection.Kind
    let context: RowContext
    @ObservationIgnored private let browser: any LibraryBrowsing

    private(set) var sections: [PlexLibrarySection] = []
    private(set) var section: PlexLibrarySection?
    private(set) var sort: LibrarySort = .recentlyAdded
    private(set) var filters = LibraryFilters()
    private(set) var genres: [LibraryFilterChoice] = []
    private(set) var decades: [LibraryFilterChoice] = []
    private(set) var resolutions: [LibraryFilterChoice] = []
    private(set) var collections: [PlexCollection] = []
    private(set) var items: [MediaSummary] = []
    private(set) var letters: [PlexLetterBucket] = []
    /// The position of `items[0]` in the full filtered list (non-zero after a letter jump).
    private(set) var startOffset = 0
    private(set) var phase: Phase = .starting
    private(set) var hasMore = false
    /// Bumped with a target when the view should move focus (after a sort, filter or letter change).
    private(set) var focusRequest: (target: LibraryFocus?, token: Int) = (nil, 0)

    @ObservationIgnored private var pager: (any LibraryPaging)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loadingPage = false
    @ObservationIgnored private var admitted: Set<String>?
    @ObservationIgnored private var started = false

    static let log = Logger(subsystem: "com.robrolabs.perch", category: "library")
    /// Rows of look-ahead: the next page is asked for when focus is within this many items of the end.
    static let pageAhead = 18

    init(kind: PlexLibrarySection.Kind, context: RowContext, browser: any LibraryBrowsing) {
        self.kind = kind
        self.context = context
        self.browser = browser
    }

    /// The query for the current state, from `offset`.
    func query(startOffset offset: Int = 0) -> PlexSectionQuery? {
        guard let section else { return nil }
        return LibraryQueryBuilder.query(
            sectionID: section.id, kind: kind, sort: sort, filters: filters, admittedRatings: admitted,
            startOffset: offset)
    }

    /// Focus memory screen id: section, sort and filters, so a different query starts at its first item.
    var memoryScreen: String {
        "library.\(section?.id ?? kind.rawValue).\(sort.rawValue).\(filters.signature)"
    }

    var showsLetters: Bool { sort == .title && letters.count > 1 }

    // MARK: Loading

    func start() async {
        guard !started else { return }
        started = true
        do {
            let all = try await browser.sections().filter { $0.kind == kind && !$0.isOtherVideos }
            sections = all
            guard let first = all.first else {
                phase = .empty
                return
            }
            await select(section: first)
        } catch {
            started = false
            phase = .failed
            Self.log.notice("Library: sections failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// First load, or a retry when the last attempt failed (the session became ready again).
    func startOrRetry() async {
        if !started {
            await start()
        } else if phase == .failed {
            await retry()
        }
    }

    /// Retry after a failure.
    func retry() async {
        if section == nil {
            await start()
        } else {
            await reload(focusFirst: true)
        }
    }

    func select(section: PlexLibrarySection) async {
        self.section = section
        filters = LibraryFilters()
        genres = []
        decades = []
        resolutions = []
        collections = []
        let browser = browser
        let id = section.id
        let ceiling = context.ceiling
        admitted = await LibraryQueryBuilder.admittedRatings(for: context) {
            try await browser.admittedContentRatings(sectionID: id, ceiling: ceiling)
        }
        guard self.section?.id == id else { return }
        async let genreValues = (try? browser.filterValues(sectionID: id, kind: .genre)) ?? []
        async let decadeValues = (try? browser.filterValues(sectionID: id, kind: .decade)) ?? []
        async let resolutionValues = (try? browser.filterValues(sectionID: id, kind: .resolution)) ?? []
        await reload(focusFirst: false)
        let (g, d, r) = await (genreValues, decadeValues, resolutionValues)
        guard self.section?.id == id else { return }
        genres = g.map(LibraryFilterChoice.init)
        decades = d.map(LibraryFilterChoice.init)
        resolutions = r.map(LibraryFilterChoice.init)
        await loadCollections()
    }

    /// With a lowered ceiling the server cannot filter collections (live, 6 Nov 2026: a content-rating filter
    /// returned none, and collection children ignore it), so the row and chip are hidden, failing closed.
    private func loadCollections() async {
        guard admitted == nil else {
            collections = []
            return
        }
        guard let query = query() else { return }
        let id = query.sectionID
        let found = (try? await browser.collections(query: query)) ?? []
        guard section?.id == id else { return }
        collections = found
    }

    /// A fresh pager from `offset`; the first page, and the letter buckets when sorted by title.
    func reload(from offset: Int = 0, focusFirst: Bool) async {
        guard let query = query(startOffset: offset) else { return }
        generation += 1
        let current = generation
        pager = await browser.makePager(query: query)
        guard current == generation else { return }
        items = []
        startOffset = offset
        hasMore = true
        loadingPage = false
        if phase != .content { phase = .starting }
        if sort == .title {
            let base = self.query(startOffset: 0) ?? query
            let buckets = (try? await browser.firstCharacters(query: base)) ?? []
            guard current == generation else { return }
            letters = buckets
        } else {
            letters = []
        }
        await loadNextPage(generation: current)
        guard current == generation else { return }
        if focusFirst { requestFocus(items.first.map { .item($0.id) }) }
    }

    /// The next page when focus nears the end of what is loaded.
    func focusMoved(to itemID: String) async {
        guard hasMore, !loadingPage, let index = items.firstIndex(where: { $0.id == itemID }),
            index >= items.count - Self.pageAhead
        else { return }
        await loadNextPage(generation: generation)
    }

    /// Pages until something admitted arrives or the server is done (a page the guard empties entirely must not
    /// stop the grid).
    private func loadNextPage(generation current: Int) async {
        guard let pager, !loadingPage else { return }
        loadingPage = true
        defer { if current == generation { loadingPage = false } }
        var attempts = 0
        while attempts < 5 {
            attempts += 1
            do {
                let page = try await pager.nextPage()
                let finished = await pager.isFinished
                guard current == generation else { return }
                let admittedPage = LibraryQueryBuilder.guardPage(page, context: context, existing: Set(items.map(\.id)))
                items += admittedPage
                hasMore = !finished
                if !admittedPage.isEmpty || finished { break }
            } catch {
                guard current == generation else { return }
                hasMore = false
                if items.isEmpty {
                    phase = .failed
                    return
                }
                break
            }
        }
        phase = items.isEmpty ? .empty : .content
    }

    // MARK: Changes from the header

    func setSort(_ sort: LibrarySort) async {
        guard sort != self.sort else { return }
        self.sort = sort
        await reload(focusFirst: true)
    }

    func setFilters(_ filters: LibraryFilters) async {
        guard filters != self.filters else { return }
        self.filters = filters
        await reload(focusFirst: true)
    }

    func clearFilters() async {
        await setFilters(LibraryFilters())
    }

    /// Reloads from the letter's first title and asks for focus on it.
    func jump(to letter: String) async {
        guard let offset = LibraryQueryBuilder.letterOffset(letter, in: letters) else { return }
        await reload(from: offset, focusFirst: true)
    }

    /// The letter of the item, for the rail's current mark.
    func letter(of itemID: String?) -> String? {
        guard showsLetters, let itemID, let index = items.firstIndex(where: { $0.id == itemID }) else { return nil }
        return LibraryQueryBuilder.letter(atOffset: startOffset + index, in: letters)
    }

    func setWatched(_ watched: Bool, item: MediaSummary) async {
        do {
            try await browser.setWatched(watched, itemID: item.id)
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            items[index].viewCount = watched ? max(1, items[index].viewCount) : 0
            items[index].viewOffsetMs = nil
        } catch {
            Self.log.notice("Library: watch state not changed: \(String(describing: error), privacy: .public)")
        }
    }

    private func requestFocus(_ target: LibraryFocus?) {
        focusRequest = (target, focusRequest.token + 1)
    }
}
