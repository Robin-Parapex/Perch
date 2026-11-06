import Foundation
import PerchCore
import PerchPlex
import Synchronization
import Testing

@testable import PerchApp

/// WP-12: the search model's debounce and cancellation, the rating guard (kids' certificate check, a lowered
/// ceiling), and the per-profile store.
@MainActor @Suite("Search model")
struct SearchModelTests {
    /// Records each query; a query in `held` waits until `release()`.
    actor Server {
        private(set) var queries: [String] = []
        private(set) var ratings: [Set<String>?] = []
        private var held: Set<String>
        private var waiting: [CheckedContinuation<Void, Never>] = []
        let answer: @Sendable (String) -> PlexSearchResults

        init(held: Set<String> = [], answer: @escaping @Sendable (String) -> PlexSearchResults) {
            self.held = held
            self.answer = answer
        }

        func search(_ query: String, _ ratings: Set<String>?) async -> PlexSearchResults {
            queries.append(query)
            self.ratings.append(ratings)
            if held.contains(query) { await withCheckedContinuation { waiting.append($0) } }
            return answer(query)
        }

        func release() {
            held = []
            waiting.forEach { $0.resume() }
            waiting = []
        }
    }

    nonisolated static func film(_ id: String, _ certificate: String?) -> MediaSummary {
        MediaSummary(id: id, kind: .film, title: "Film \(id)", certificate: certificate)
    }

    /// One film per certificate, a series, an episode and a collection; titles carry the query.
    nonisolated static func mixed(_ query: String) -> PlexSearchResults {
        PlexSearchResults(
            films: [
                film("u-\(query)", "U"), film("pg-\(query)", "gb/PG"), film("15-\(query)", "15"),
                film("18-\(query)", "18"), film("nr-\(query)", nil),
            ],
            series: [MediaSummary(id: "s15-\(query)", kind: .series, title: "S", certificate: "TV-MA")],
            episodes: [MediaSummary(id: "e-u-\(query)", kind: .episode, title: "E", certificate: "TV-Y")],
            collections: [PlexSearchCollection(id: "c", title: "C", sectionID: "1", kind: .film)])
    }

    static let adult = RowContext(profileID: "1001", serviceCeiling: .eighteen, ceiling: .eighteen)
    static let lowered = RowContext(profileID: "1002", serviceCeiling: .eighteen, ceiling: .pg)
    static let kid = RowContext(profileID: "1003", serviceCeiling: .u, ceiling: .u)

    func model(_ server: Server, context: RowContext = adult, isKid: Bool = false, sendsFilter: Bool = false)
        -> SearchModel
    {
        SearchModel(
            context: context, isKid: isKid, debounce: .milliseconds(60), sendsRatingFilter: sendsFilter,
            search: { query, ratings in await server.search(query, ratings) },
            admittedRatings: { ["U", "PG"] })
    }

    // MARK: Debounce and cancel

    @Test func typingQuicklySendsOnlyTheLastQuery() async throws {
        let server = Server(answer: Self.mixed)
        let model = model(server)
        for text in ["h", "ha", "har", "harb"] {
            model.setQuery(text)
            try await Task.sleep(for: .milliseconds(10))
        }
        await model.settle()
        #expect(await server.queries == ["harb"])
        #expect(model.phase == .results)
        #expect(model.shownQuery == "harb")
    }

    @Test func staleAnswerNeverReplacesNewerResults() async throws {
        let server = Server(held: ["old"], answer: Self.mixed)
        let model = model(server)
        model.setQuery("old")
        try await Task.sleep(for: .milliseconds(150))  // past the debounce: "old" is in flight, held
        #expect(await server.queries == ["old"])
        model.setQuery("new")
        await model.settle()
        #expect(model.results.films.first?.id == "u-new")
        await server.release()  // the stale answer arrives after the newer one
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.shownQuery == "new")
        #expect(model.results.films.first?.id == "u-new")
    }

    @Test func previousResultsStayWhileTheNextQueryLoads() async throws {
        let server = Server(held: ["two"], answer: Self.mixed)
        let model = model(server)
        model.setQuery("one")
        await model.settle()
        model.setQuery("two")
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.phase == .results)
        #expect(model.shownQuery == "one")
        await server.release()
        await model.settle()
        #expect(model.shownQuery == "two")
    }

    @Test func blankQueryClearsAtOnceAndRequestsNothing() async throws {
        let server = Server(answer: Self.mixed)
        let model = model(server)
        model.setQuery("one")
        await model.settle()
        model.setQuery("   ")
        #expect(model.phase == .idle)
        #expect(model.results.isEmpty)
        await model.settle()
        #expect(await server.queries == ["one"])
    }

    @Test func noMatchIsNoResults() async {
        let server = Server(answer: { _ in .empty })
        let model = model(server)
        model.setQuery("zzqx")
        await model.settle()
        #expect(model.phase == .noResults)
    }

    /// Live finding: a query restored at launch ran before the session was ready and stayed failed.
    @Test func failedSearchRunsAgainWhenTheSessionIsReady() async {
        let ready = Mutex(false)
        let model = SearchModel(
            context: Self.adult, isKid: false, debounce: .milliseconds(10), sendsRatingFilter: false,
            search: { query, _ in
                guard ready.withLock({ $0 }) else { throw URLError(.notConnectedToInternet) }
                return Self.mixed(query)
            },
            admittedRatings: { [] })
        model.setQuery("the")
        await model.settle()
        #expect(model.phase == .failed)
        ready.withLock { $0 = true }
        model.sessionReady()
        await model.settle()
        #expect(model.phase == .results)
        #expect(model.shownQuery == "the")
        model.sessionReady()  // nothing failed now: no new request
        #expect(model.requestCount == 2)
    }

    /// Review finding: a reconnect cancels the request with the library's own `CancellationError` (the task itself
    /// runs on). That is a failure, and the query runs again once the session is ready.
    @Test func libraryCancellationIsAFailureAndRunsAgainWhenReady() async {
        let ready = Mutex(false)
        let model = SearchModel(
            context: Self.adult, isKid: false, debounce: .milliseconds(10), sendsRatingFilter: false,
            search: { query, _ in
                guard ready.withLock({ $0 }) else { throw CancellationError() }
                return Self.mixed(query)
            },
            admittedRatings: { [] })
        model.setQuery("the")
        await model.settle()
        #expect(model.phase == .failed)
        ready.withLock { $0 = true }
        model.sessionReady()
        await model.settle()
        #expect(model.phase == .results)
        #expect(model.shownQuery == "the")
    }

    /// Review finding: results for "lantern" are shown, the query becomes "lanterns" while the app reconnects (that
    /// search fails, the old results stay); ready runs the edited query rather than leaving stale results up.
    @Test func editedQueryWhileConnectingRunsWhenReady() async {
        let ready = Mutex(true)
        let model = SearchModel(
            context: Self.adult, isKid: false, debounce: .milliseconds(10), sendsRatingFilter: false,
            search: { query, _ in
                guard ready.withLock({ $0 }) else { throw URLError(.networkConnectionLost) }
                return Self.mixed(query)
            },
            admittedRatings: { [] })
        model.setQuery("lantern")
        await model.settle()
        #expect(model.shownQuery == "lantern")
        ready.withLock { $0 = false }
        model.setQuery("lanterns")
        await model.settle()
        #expect(model.phase == .results)  // the failure keeps what is shown
        #expect(model.shownQuery == "lantern")
        ready.withLock { $0 = true }
        model.sessionReady()
        await model.settle()
        #expect(model.shownQuery == "lanterns")
        #expect(model.results.films.first?.id == "u-lanterns")
        #expect(model.requestCount == 3)
    }

    /// Review finding: a transport failure that lands after the reconnect (session already ready) gets one retry.
    @Test func failureWhileReadyRetriesOnce() async {
        let calls = Mutex(0)
        let model = SearchModel(
            context: Self.adult, isKid: false, debounce: .milliseconds(10), sendsRatingFilter: false,
            retryDelay: .milliseconds(20), isSessionReady: { true },
            search: { query, _ in
                let call = calls.withLock { $0 += 1; return $0 }
                guard call > 1 else { throw URLError(.networkConnectionLost) }
                return Self.mixed(query)
            },
            admittedRatings: { [] })
        model.setQuery("the")
        await model.settle()
        #expect(model.phase == .results)
        #expect(model.requestCount == 2)

        // A failure that persists: one retry only, then the message.
        let failing = SearchModel(
            context: Self.adult, isKid: false, debounce: .milliseconds(10), sendsRatingFilter: false,
            retryDelay: .milliseconds(20), isSessionReady: { true },
            search: { _, _ in throw URLError(.timedOut) },
            admittedRatings: { [] })
        failing.setQuery("the")
        await failing.settle()
        #expect(failing.phase == .failed)
        #expect(failing.requestCount == 2)
    }

    // MARK: Rating guard

    @Test func kidSeesOnlyTitlesWithinTheCeilingEvenWhenTheServerLeaks() async {
        let server = Server(answer: Self.mixed)
        let model = model(server, context: Self.kid, isKid: true, sendsFilter: true)
        model.setQuery("x")
        await model.settle()
        #expect(model.results.films.map(\.id) == ["u-x"])  // PG, 15, 18 and unrated are gone
        #expect(model.results.series.isEmpty)
        #expect(model.results.episodes.map(\.id) == ["e-u-x"])
        #expect(model.results.collections.isEmpty)
        // Kid's ceiling is the server's own: no filter is sent; the client check is what holds.
        #expect(await server.ratings == [nil])
    }

    @Test func loweredCeilingSendsTheFilterWhenHonouredAndAlwaysGuards() async {
        let server = Server(answer: Self.mixed)
        let model = model(server, context: Self.lowered, sendsFilter: true)
        model.setQuery("x")
        await model.settle()
        #expect(await server.ratings == [["U", "PG"]])
        #expect(Set(model.results.films.map(\.id)) == ["u-x", "pg-x"])
        #expect(model.results.collections.isEmpty)

        let unhonoured = Server(answer: Self.mixed)
        let plain = self.model(unhonoured, context: Self.lowered, sendsFilter: false)
        plain.setQuery("x")
        await plain.settle()
        #expect(await unhonoured.ratings == [nil])
        #expect(Set(plain.results.films.map(\.id)) == ["u-x", "pg-x"])
    }

    @Test func adultSeesEverything() async {
        let server = Server(answer: Self.mixed)
        let model = model(server)
        model.setQuery("x")
        await model.settle()
        #expect(model.results.films.count == 5)
        #expect(model.results.collections.count == 1)
    }

    /// Live rows may leave out a collection's section and type: an adult still sees it; a kid and a lowered ceiling
    /// see no collections at all.
    @Test func adultKeepsCollectionsWithoutSectionOrType() {
        let raw = PlexSearchResults(collections: [
            PlexSearchCollection(id: "c1", title: "Known", sectionID: "1", kind: .film),
            PlexSearchCollection(id: "c2", title: "Bare"),
        ])
        #expect(SearchModel.guardResults(raw, context: Self.adult, isKid: false).collections.map(\.id) == ["c1", "c2"])
        #expect(SearchModel.guardResults(raw, context: Self.kid, isKid: true).collections.isEmpty)
        #expect(SearchModel.guardResults(raw, context: Self.lowered, isKid: false).collections.isEmpty)
    }

    // MARK: Store

    @Test func storeKeepsTheQueryPerProfileAndClearsOnSwitch() async {
        let store = SearchStore()
        let server = Server(answer: Self.mixed)
        let first = store.model(context: Self.adult, isKid: false) { model(server) }
        first.setQuery("harbour")
        await first.settle()
        let again = store.model(context: Self.adult, isKid: false) { model(server) }
        #expect(again === first)
        #expect(again.query == "harbour")
        #expect(again.phase == .results)

        let kid = store.model(context: Self.kid, isKid: true) { model(server, context: Self.kid, isKid: true) }
        #expect(kid !== first)
        #expect(kid.query.isEmpty)
        #expect(kid.results.isEmpty)
        // Back to the adult: the switch cleared the old search too.
        let back = store.model(context: Self.adult, isKid: false) { model(server) }
        #expect(back !== first)
        #expect(back.query.isEmpty)
    }
}
