import Foundation
import Observation
import OSLog
import PerchCore
import PerchPlex

/// What can hold focus among the search results. `group` is the row ("films", "series", "episodes", "collections").
enum SearchFocus: Hashable {
    case item(group: String, id: String)

    static let screen = "search"
}

/// The Search tab's state for one profile (WP-12): the query, the results it found, and the debounced, cancellable
/// request behind them. Every result passes the rating guard before it is shown (PERMISSIONS 70, enforced here, not
/// by hiding cards). Results stay while the next query loads, so the screen never shows a spinner.
@MainActor
@Observable
final class SearchModel {
    typealias Search = @Sendable (_ query: String, _ contentRatings: Set<String>?) async throws -> PlexSearchResults
    typealias AdmittedRatings = @Sendable () async throws -> Set<String>

    enum Phase: Equatable {
        /// Nothing typed.
        case idle
        case results
        case noResults
        /// The search could not run and nothing is shown.
        case failed
    }

    static let log = Logger(subsystem: "com.robrolabs.perch", category: "search")
    static let defaultDebounce: Duration = .milliseconds(300)
    static let defaultRetryDelay: Duration = .seconds(1)

    let context: RowContext
    let isKid: Bool
    var profileID: String { context.profileID }

    private(set) var query = ""
    private(set) var results = PlexSearchResults.empty
    private(set) var phase: Phase = .idle
    /// The trimmed query the shown results answer.
    private(set) var shownQuery = ""
    /// How many searches reached the server (tests).
    private(set) var requestCount = 0

    private let search: Search
    private let admittedRatings: AdmittedRatings
    private let debounce: Duration
    private let sendsRatingFilter: Bool
    private let retryDelay: Duration
    /// Whether the session is ready now: a search that fails while it is ready is retried once.
    private let isSessionReady: @MainActor () -> Bool
    private var cachedRatings: Set<String>?
    private var task: Task<Void, Never>?

    init(
        context: RowContext, isKid: Bool, debounce: Duration = SearchModel.defaultDebounce,
        sendsRatingFilter: Bool = SearchModel.serverHonoursRatingFilter, retryDelay: Duration = SearchModel.defaultRetryDelay,
        isSessionReady: @escaping @MainActor () -> Bool = { false },
        search: @escaping Search, admittedRatings: @escaping AdmittedRatings
    ) {
        self.context = context
        self.isKid = isKid
        self.debounce = debounce
        self.sendsRatingFilter = sendsRatingFilter
        self.retryDelay = retryDelay
        self.isSessionReady = isSessionReady
        self.search = search
        self.admittedRatings = admittedRatings
    }

    /// Whether `/hubs/search` honours `contentRating=`. `-PerchSearchProbe` on the live server (6 Nov 2026): it does
    /// not (an impossible rating returned the same counts), so nothing is sent; the client guard runs either way.
    nonisolated static let serverHonoursRatingFilter = false

    /// The text in the field changed: the request in flight (or waiting out the debounce) is cancelled and a new one
    /// starts after the debounce. A blank query clears the results at once.
    func setQuery(_ text: String) {
        guard text != query else { return }
        query = text
        task?.cancel()
        task = nil
        let trimmed = Self.trimmed(text)
        guard !trimmed.isEmpty else {
            results = .empty
            shownQuery = ""
            phase = .idle
            return
        }
        guard trimmed != shownQuery || phase == .failed else { return }  // only spacing changed
        let debounce = debounce
        task = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.run(trimmed)
        }
    }

    /// The session became (or became again) ready: a query whose results are not on screen (it failed, or was typed,
    /// dictated, edited or restored while the app was connecting) runs at once. Results for the current query stay.
    func sessionReady() {
        let trimmed = Self.trimmed(query)
        guard !trimmed.isEmpty, trimmed != shownQuery || phase == .failed else { return }
        task?.cancel()
        task = Task { [weak self] in await self?.run(trimmed) }
    }

    /// Waits for the current request, and a retry it scheduled, if any (tests).
    func settle() async {
        while let current = task {
            await current.value
            if task == current { return }
        }
    }

    private func run(_ trimmed: String, retrying: Bool = true) async {
        let ratings = await ratingFilter()
        guard !Task.isCancelled else { return }
        requestCount += 1
        do {
            let raw = try await search(trimmed, ratings)
            guard !Task.isCancelled, Self.trimmed(query) == trimmed else { return }
            let guarded = Self.guardResults(raw, context: context, isKid: isKid)
            results = guarded
            shownQuery = trimmed
            phase = guarded.isEmpty ? .noResults : .results
        } catch {
            // Only this task's own cancellation (a newer query) is quiet. A `CancellationError` thrown while the task
            // runs on is the library's (the session changed under the request, as on a reconnect): a failure.
            guard !Task.isCancelled, Self.trimmed(query) == trimmed else { return }
            Self.log.notice("Search failed: \(String(describing: type(of: error)), privacy: .public)")
            // Failed although the session is ready (a reconnect landed during the request): one more try shortly.
            if retrying, isSessionReady() {
                let delay = retryDelay
                task = Task { [weak self] in
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled else { return }
                    await self?.run(trimmed, retrying: false)
                }
                return
            }
            // Keep what is shown; only an empty screen says the search could not run.
            if results.isEmpty { phase = .failed }
        }
    }

    /// The content ratings to send: none unless Perch's ceiling is below the server's and the server honours the
    /// filter on search. A failed lookup sends none; the client guard still hides everything above the ceiling.
    private func ratingFilter() async -> Set<String>? {
        guard sendsRatingFilter, LibraryQueryBuilder.isCeilingLowered(context) else { return nil }
        if let cachedRatings { return cachedRatings }
        guard let loaded = try? await admittedRatings() else { return nil }
        cachedRatings = loaded
        return loaded
    }

    /// The guard on every result: `RowContext.admits` (when the ceiling is lowered), and for a kid the certificate
    /// check against the profile ceiling whatever the server says, unrated failing closed. Collections carry no
    /// certificate of their own, so a kid or a lowered ceiling sees none in search. An adult's collections stay even
    /// when the server left out their section or type (the collection page does not need them at the server's ceiling).
    nonisolated static func guardResults(
        _ raw: PlexSearchResults, context: RowContext, isKid: Bool
    ) -> PlexSearchResults {
        func admit(_ items: [MediaSummary]) -> [MediaSummary] {
            LibraryQueryBuilder.guardCollectionItems(items, context: context, isKid: isKid)
        }
        let collections = isKid || LibraryQueryBuilder.isCeilingLowered(context) ? [] : raw.collections
        return PlexSearchResults(
            films: admit(raw.films), series: admit(raw.series), episodes: admit(raw.episodes),
            collections: collections)
    }

    nonisolated static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The current profile's search, kept while the app runs so leaving the tab (or opening a page) and coming back
/// finds the same query and results. Another profile gets a fresh, empty search: a switch clears it.
@MainActor
final class SearchStore {
    static let shared = SearchStore()
    private var current: SearchModel?

    /// The kept search when it belongs to the same profile, ceiling and role; else `make()`'s, which replaces it.
    func model(context: RowContext, isKid: Bool, make: () -> SearchModel) -> SearchModel {
        if let current, current.context == context, current.isKid == isKid { return current }
        let model = make()
        current = model
        return model
    }

    func model(for home: HomeProfile, core: CoreServices) -> SearchModel {
        model(context: home.context, isKid: home.isKid) { Self.make(for: home, core: core) }
    }

    private static func make(for home: HomeProfile, core: CoreServices) -> SearchModel {
        let library = core.library
        let context = home.context
        let model = SearchModel(
            context: context, isKid: home.isKid,
            isSessionReady: {
                if case .ready = core.plexSignIn.snapshot.state { true } else { false }
            },
            search: { query, ratings in try await library.search(query: query, contentRatings: ratings) },
            admittedRatings: {
                let sections = try await library.sections().filter { !$0.isOtherVideos }
                var admitted = Set<String>()
                for section in sections {
                    admitted.formUnion(try await library.admittedContentRatings(sectionID: section.id, ceiling: context.ceiling))
                }
                return admitted
            })
        #if DEBUG
        if let initial = SearchStore.debugInitialQuery { model.setQuery(initial) }
        #endif
        return model
    }

    #if DEBUG
    /// `-PerchSearchQuery <text>` (DEBUG): the search starts with this query, for screenshots of a live library.
    static var debugInitialQuery: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PerchSearchQuery"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
    #endif
}
