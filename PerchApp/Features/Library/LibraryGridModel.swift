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
    /// The absolute server position of the next page (an error leaves it where it was).
    var position: Int { get async }
}

extension PlexSectionPager: LibraryPaging {
    var position: Int { get async { offset } }
}

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

    /// The content-rating set a lowered ceiling needs. No query is built while it is pending or failed.
    enum Ratings: Equatable {
        case notNeeded, pending, failed
        case resolved(Set<String>)
    }

    let kind: PlexLibrarySection.Kind
    let context: RowContext
    /// A kid's profile: collection cards and their titles also pass the certificate check (belt and braces).
    let isKid: Bool
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
    @ObservationIgnored private(set) var ratings: Ratings = .notNeeded
    @ObservationIgnored private var started = false
    /// Paging stopped on an error part-way: placeholders stay, and the next focus move or a ready session resumes
    /// from where the pager stopped.
    @ObservationIgnored private(set) var pagingStalled = false

    static let log = Logger(subsystem: "com.robrolabs.perch", category: "library")
    /// Rows of look-ahead: the next page is asked for when focus is within this many items of the end.
    static let pageAhead = 18

    init(kind: PlexLibrarySection.Kind, context: RowContext, isKid: Bool = false, browser: any LibraryBrowsing) {
        self.kind = kind
        self.context = context
        self.isKid = isKid
        self.browser = browser
    }

    /// The query for the current state, from `offset`. Nil while a lowered ceiling's ratings are unresolved.
    func query(startOffset offset: Int = 0) -> PlexSectionQuery? {
        guard let section else { return nil }
        let admitted: Set<String>?
        switch ratings {
        case .notNeeded: admitted = nil
        case .resolved(let set): admitted = set
        case .pending, .failed: return nil
        }
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
            Self.log.notice("Library: sections failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// First load, a retry when the last attempt failed, or paging resumed when it stopped part-way (the session
    /// became ready again, for example after a reconnect).
    func startOrRetry() async {
        if !started {
            await start()
        } else if phase == .failed {
            await retry()
        } else if pagingStalled {
            await loadNextPage(generation: generation)
        }
    }

    /// Retry after a failure: the ratings again when they were what failed.
    func retry() async {
        guard let section else {
            await start()
            return
        }
        switch ratings {
        case .pending, .failed:
            guard await resolveRatings(sectionID: section.id) else { return }
            await loadSectionContent(sectionID: section.id)
        case .notNeeded, .resolved:
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
        guard await resolveRatings(sectionID: section.id) else { return }
        await loadSectionContent(sectionID: section.id)
    }

    /// A lowered ceiling's content-rating set. A failed lookup requests nothing and shows the failure with a retry
    /// (never "No films here yet"). False when the grid cannot load (failed, or the section changed meanwhile).
    private func resolveRatings(sectionID id: String) async -> Bool {
        guard LibraryQueryBuilder.isCeilingLowered(context) else {
            ratings = .notNeeded
            return true
        }
        ratings = .pending
        let browser = browser
        let ceiling = context.ceiling
        let loaded: Set<String>?
        do {
            loaded = try await browser.admittedContentRatings(sectionID: id, ceiling: ceiling)
        } catch {
            Self.log.notice("Library: ratings lookup failed: \(String(describing: type(of: error)), privacy: .public)")
            loaded = nil
        }
        guard section?.id == id else { return false }
        guard let loaded else {
            ratings = .failed
            generation += 1
            pager = nil
            items = []
            hasMore = false
            pagingStalled = false
            phase = .failed
            return false
        }
        ratings = .resolved(loaded)
        return true
    }

    /// Filter values, the first page and the collections for the selected section.
    private func loadSectionContent(sectionID id: String) async {
        let browser = browser
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

    /// The Collections row. A collection needs at least two titles. With a lowered ceiling, or for a kid, each
    /// collection's members are loaded and pass the final guard (and, for a kid, the certificate check against the
    /// profile ceiling, unrated failing closed); the card then counts only those. See wp-10-plan.md Decisions.
    private func loadCollections() async {
        collections = []
        guard let query = query() else { return }
        let lowered = query.contentRatings != nil
        let id = query.sectionID
        // With a lowered ceiling the server narrows the list (live, 6 Nov 2026: 94 to 50 under the PG set, any
        // admitted member) but ignores the filter on children (20 and 20), so members are still guarded here.
        let found = (try? await browser.collections(query: query)) ?? []
        guard section?.id == id else { return }
        guard lowered || isKid else {
            collections = found.filter { ($0.childCount ?? Self.minimumCollectionSize) >= Self.minimumCollectionSize }
            return
        }
        let guarded = await guardCollections(found, query: query)
        guard section?.id == id else { return }
        collections = guarded
    }

    /// Loads each collection's members (four at a time) and keeps those with enough admitted titles.
    private func guardCollections(_ found: [PlexCollection], query: PlexSectionQuery) async -> [PlexCollection] {
        let browser = browser
        let context = context
        let isKid = isKid
        let counts = await withTaskGroup(of: (Int, Int).self) { group -> [Int: Int] in
            var result: [Int: Int] = [:]
            var next = 0
            func add(_ index: Int) {
                let collectionID = found[index].id
                group.addTask {
                    let members = (try? await browser.collectionItems(collectionID: collectionID, query: query)) ?? []
                    return (index, LibraryQueryBuilder.guardCollectionItems(members, context: context, isKid: isKid).count)
                }
            }
            while next < min(4, found.count) {
                add(next)
                next += 1
            }
            for await (index, count) in group {
                result[index] = count
                if next < found.count {
                    add(next)
                    next += 1
                }
            }
            return result
        }
        return found.enumerated().compactMap { index, collection in
            let count = counts[index] ?? 0
            guard count >= Self.minimumCollectionSize else { return nil }
            return PlexCollection(
                id: collection.id, title: collection.title, thumbPath: collection.thumbPath, childCount: count,
                summary: collection.summary, artPath: collection.artPath)
        }
    }

    static let minimumCollectionSize = 2

    /// A fresh pager from `offset`; the first page, and the letter buckets when sorted by title.
    func reload(from offset: Int = 0, focusFirst: Bool) async {
        guard let query = query(startOffset: offset) else { return }
        generation += 1
        let current = generation
        let fresh = await browser.makePager(query: query)
        guard current == generation else { return }
        pager = fresh
        pagingStalled = false
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
        guard hasMore || pagingStalled, !loadingPage, let index = items.firstIndex(where: { $0.id == itemID }),
            index >= items.count - Self.pageAhead
        else { return }
        await loadNextPage(generation: generation)
    }

    /// Pages until something admitted arrives or the server is done (a page the guard empties entirely must not
    /// stop the grid). A pager is bound to the session it was made in, so after an error (a reconnect throws
    /// `CancellationError`) one fresh pager from the same position tries again at once; if that fails too and
    /// titles are showing, paging is marked stalled and resumes on the next focus move or when the session is
    /// ready again. It never silently stops part-way.
    private func loadNextPage(generation current: Int) async {
        guard pager != nil, !loadingPage else { return }
        loadingPage = true
        defer { if current == generation { loadingPage = false } }
        var attempts = 0
        var rebuilt = false
        while attempts < 5 {
            guard let pager else { return }
            attempts += 1
            do {
                let page = try await pager.nextPage()
                let finished = await pager.isFinished
                guard current == generation else { return }
                pagingStalled = false
                let admittedPage = LibraryQueryBuilder.guardPage(page, context: context, existing: Set(items.map(\.id)))
                items += admittedPage
                hasMore = !finished
                if !admittedPage.isEmpty || finished { break }
            } catch {
                guard current == generation else { return }
                if !rebuilt, await rebuildPager(generation: current) {
                    rebuilt = true
                    attempts -= 1
                    continue
                }
                guard current == generation else { return }
                if items.isEmpty {
                    hasMore = false
                    phase = .failed
                    return
                }
                hasMore = true
                pagingStalled = true
                Self.log.notice("Library: paging stalled: \(String(describing: type(of: error)), privacy: .public)")
                break
            }
        }
        phase = items.isEmpty ? .empty : .content
    }

    /// A fresh pager from where the current one stopped (built into a local, assigned only if still current).
    private func rebuildPager(generation current: Int) async -> Bool {
        guard let position = await pager?.position, current == generation,
            let query = query(startOffset: position)
        else { return false }
        let fresh = await browser.makePager(query: query)
        guard current == generation else { return false }
        pager = fresh
        return true
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
            Self.log.notice("Library: watch state not changed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    private func requestFocus(_ target: LibraryFocus?) {
        focusRequest = (target, focusRequest.token + 1)
    }
}
