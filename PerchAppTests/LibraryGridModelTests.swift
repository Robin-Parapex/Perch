import Foundation
import PerchCore
import PerchPlex
import Synchronization
import Testing

@testable import PerchApp

/// WP-10: the library grid's query building, rating ceiling, final guard, letter jump and paging.
@MainActor @Suite("Library grid")
struct LibraryGridModelTests {
    // MARK: Fixtures

    /// 60 films, two per letter A to Z plus "#" titles, certificates cycling through U, PG, 12, 15, 18, unrated.
    nonisolated static let films: [MediaSummary] = {
        let certificates: [String?] = ["U", "PG", "12", "15", "18", nil]
        var titles = ["1st Light", "2 Rivers"]
        for scalar in UnicodeScalar("A").value...UnicodeScalar("Z").value {
            let letter = String(UnicodeScalar(scalar)!)
            titles += ["\(letter)lpha \(letter)", "\(letter)mber \(letter)"]
        }
        titles += ["Zz Late 1", "Zz Late 2", "Zz Late 3", "Zz Late 4"]
        return titles.enumerated().map { index, title in
            MediaSummary(id: String(5000 + index), kind: .film, title: title, year: 2000 + index % 20,
                certificate: certificates[index % certificates.count])
        }
    }()

    nonisolated static var buckets: [PlexLetterBucket] {
        var result: [PlexLetterBucket] = []
        for film in films {
            let first = film.title.first!.isLetter ? String(film.title.first!) : "#"
            if result.last?.title == first {
                result[result.count - 1] = PlexLetterBucket(title: first, size: result.last!.size + 1)
            } else {
                result.append(PlexLetterBucket(title: first, size: 1))
            }
        }
        return result
    }

    final class Recorder: Sendable {
        let queries = Mutex<[PlexSectionQuery]>([])
        let admittedCalls = Mutex(0)
        /// Page requests that throw next (as a reconnect does), whichever pager makes them.
        let pageFailures = Mutex(0)
        let admittedFailures = Mutex(0)
    }

    final class FakePager: LibraryPaging {
        let items: [MediaSummary]
        let state: Mutex<Int>
        let recorder: Recorder?
        init(items: [MediaSummary], start: Int, recorder: Recorder? = nil) {
            self.items = items
            state = Mutex(start)
            self.recorder = recorder
        }
        var position: Int { get async { state.withLock { $0 } } }
        func nextPage() async throws -> [MediaSummary] {
            let fail = recorder?.pageFailures.withLock { count -> Bool in
                guard count > 0 else { return false }
                count -= 1
                return true
            } ?? false
            if fail { throw CancellationError() }
            return state.withLock { offset in
                let size = 20
                let page = Array(items.dropFirst(offset).prefix(size))
                offset += page.count
                return page
            }
        }
        var isFinished: Bool { get async { state.withLock { $0 >= items.count } } }
    }

    struct FakeBrowser: LibraryBrowsing {
        let recorder: Recorder
        var admitted: Set<String> = ["U", "PG"]
        var admittedFails = false
        var members: [MediaSummary] = []

        func sections() async throws -> [PlexLibrarySection] {
            [PlexLibrarySection(id: "1", title: "Films", kind: .film), PlexLibrarySection(id: "2", title: "Shows", kind: .series)]
        }
        func makePager(query: PlexSectionQuery) async -> any LibraryPaging {
            recorder.queries.withLock { $0.append(query) }
            return FakePager(items: LibraryGridModelTests.films, start: query.startOffset, recorder: recorder)
        }
        func firstCharacters(query: PlexSectionQuery) async throws -> [PlexLetterBucket] { LibraryGridModelTests.buckets }
        func filterValues(sectionID: String, kind: PlexFilterKind) async throws -> [PlexFilterValue] {
            kind == .genre ? [PlexFilterValue(key: "101", title: "Drama")] : []
        }
        func collections(query: PlexSectionQuery) async throws -> [PlexCollection] {
            [PlexCollection(id: "9001", title: "Harbour stories", thumbPath: nil, childCount: 5)]
        }
        func collectionItems(collectionID: String, query: PlexSectionQuery) async throws -> [MediaSummary] { members }
        func admittedContentRatings(sectionID: String, ceiling: RatingCeiling) async throws -> Set<String> {
            recorder.admittedCalls.withLock { $0 += 1 }
            let failNow = recorder.admittedFailures.withLock { count -> Bool in
                guard count > 0 else { return false }
                count -= 1
                return true
            }
            if admittedFails || failNow { throw URLError(.timedOut) }
            return admitted
        }
        func setWatched(_ watched: Bool, itemID: String) async throws {}
    }

    static let adult = RowContext(profileID: "1001", serviceCeiling: .eighteen, ceiling: .eighteen)
    static let lowered = RowContext(profileID: "1002", serviceCeiling: .eighteen, ceiling: .pg)

    // MARK: Query building

    @Test func queryCarriesSortAndEachFilter() {
        var filters = LibraryFilters()
        let plain = LibraryQueryBuilder.query(sectionID: "1", kind: .film, sort: .recentlyAdded, filters: filters, admittedRatings: nil)
        #expect(plain.sort?.value == "addedAt:desc")
        #expect(plain.genreIDs.isEmpty && plain.decade == nil && plain.resolution == nil && !plain.unwatched)
        #expect(plain.collectionID == nil && plain.contentRatings == nil && plain.startOffset == 0)

        filters.genre = LibraryFilterChoice(key: "101", title: "Drama")
        filters.decade = LibraryFilterChoice(key: "1990", title: "1990s")
        filters.resolution = LibraryFilterChoice(key: "4k", title: "4K")
        filters.unwatched = true
        filters.collection = LibraryFilterChoice(key: "9001", title: "Harbour stories")
        #expect(filters.activeCount == 5)
        for (sort, value) in [(LibrarySort.title, "titleSort"), (.year, "year:desc"), (.rating, "rating:desc")] {
            let query = LibraryQueryBuilder.query(
                sectionID: "1", kind: .film, sort: sort, filters: filters, admittedRatings: ["U"], startOffset: 12)
            #expect(query.sort?.value == value)
            #expect(query.genreIDs == ["101"])
            #expect(query.decade == 1990)
            #expect(query.resolution == "4k")
            #expect(query.unwatched)
            #expect(query.collectionID == "9001")
            #expect(query.contentRatings == ["U"])
            #expect(query.startOffset == 12)
        }
    }

    // MARK: Ceiling

    @Test func ceilingNotLoweredSendsNoRatingFilter() async {
        let calls = Mutex(0)
        let result = await LibraryQueryBuilder.admittedRatings(for: Self.adult) {
            calls.withLock { $0 += 1 }
            return ["U"]
        }
        #expect(result == nil, "an unlowered ceiling sends no content-rating filter, so unrated titles stay visible")
        #expect(calls.withLock { $0 } == 0)
        // A kid whose Plex restriction already is the ceiling: the server enforces it, Perch sends nothing.
        let kid = RowContext(profileID: "1003", serviceCeiling: .u, ceiling: .u)
        #expect(await LibraryQueryBuilder.admittedRatings(for: kid) { ["U"] } == nil)
    }

    @Test func loweredCeilingUsesAdmittedSetAndFailsClosed() async {
        #expect(LibraryQueryBuilder.isCeilingLowered(Self.lowered))
        let admitted = await LibraryQueryBuilder.admittedRatings(for: Self.lowered) { ["U", "PG"] }
        #expect(admitted == ["U", "PG"])
        let failed = await LibraryQueryBuilder.admittedRatings(for: Self.lowered) { throw URLError(.timedOut) }
        #expect(failed == [], "a failed lookup admits nothing")
        let query = LibraryQueryBuilder.query(
            sectionID: "1", kind: .film, sort: .title, filters: LibraryFilters(), admittedRatings: failed)
        #expect(query.admitsNothing)
    }

    @Test func modelSendsAdmittedSetOnlyWhenLowered() async {
        let recorder = Recorder()
        let model = LibraryGridModel(kind: .film, context: Self.lowered, browser: FakeBrowser(recorder: recorder))
        await model.start()
        #expect(recorder.queries.withLock { $0.last?.contentRatings } == ["U", "PG"])

        let adultRecorder = Recorder()
        let adultModel = LibraryGridModel(kind: .film, context: Self.adult, browser: FakeBrowser(recorder: adultRecorder))
        await adultModel.start()
        #expect(adultRecorder.queries.withLock { $0.last?.contentRatings } == .some(nil))
        #expect(adultRecorder.admittedCalls.withLock { $0 } == 0)
        #expect(adultModel.items.contains { $0.certificate == nil }, "adults see unrated titles")
        #expect(adultModel.items.contains { $0.certificate == "18" })
        #expect(adultModel.collections.count == 1)
        #expect(model.collections.isEmpty, "lowered: members are guarded on the client; none admitted, no card")
    }

    // MARK: Final guard

    @Test func finalGuardDropsTitlesAboveALoweredCeiling() async {
        let page = Self.films.prefix(12).map { $0 }
        let kept = LibraryQueryBuilder.guardPage(page, context: Self.lowered, existing: [])
        #expect(kept.allSatisfy { ["U", "PG"].contains($0.certificate ?? "") }, "only U and PG pass a PG ceiling")
        #expect(!kept.contains { $0.certificate == nil }, "unrated fails closed")
        #expect(kept.count == 4)
        let all = LibraryQueryBuilder.guardPage(page, context: Self.adult, existing: [])
        #expect(all.count == 12, "an unlowered ceiling keeps everything, unrated included")
        let deduped = LibraryQueryBuilder.guardPage(page, context: Self.adult, existing: [page[0].id])
        #expect(deduped.count == 11, "an item already shown is not added twice")

        // The model applies the guard even if the server ignored the rating filter (the fake pager does).
        let model = LibraryGridModel(kind: .film, context: Self.lowered, browser: FakeBrowser(recorder: Recorder()))
        await model.start()
        #expect(!model.items.isEmpty)
        #expect(model.items.allSatisfy { ["U", "PG"].contains($0.certificate ?? "") })
    }

    // MARK: Letters

    @Test func letterJumpReloadsFromOffsetAndTargetsFirstTitle() async throws {
        let model = LibraryGridModel(kind: .film, context: Self.adult, browser: FakeBrowser(recorder: Recorder()))
        await model.start()
        #expect(!model.showsLetters, "no rail unless sorted by title")
        await model.setSort(.title)
        #expect(model.showsLetters)
        let offset = try #require(LibraryQueryBuilder.letterOffset("M", in: model.letters))
        #expect(offset == 2 + 12 * 2, "# holds 2 titles, then two per letter")
        await model.jump(to: "M")
        #expect(model.startOffset == offset)
        let first = try #require(model.items.first)
        #expect(first.title == "Mlpha M")
        #expect(model.focusRequest.target == .item(first.id))
        #expect(model.letter(of: first.id) == "M")
        #expect(LibraryQueryBuilder.letter(atOffset: 0, in: model.letters) == "#")
        #expect(LibraryQueryBuilder.letter(atOffset: 3, in: model.letters) == "A")
    }

    @Test func sortOrFilterChangeTargetsFirstItemAndNewMemoryScreen() async {
        let model = LibraryGridModel(kind: .film, context: Self.adult, browser: FakeBrowser(recorder: Recorder()))
        await model.start()
        let before = model.memoryScreen
        var filters = model.filters
        filters.unwatched = true
        await model.setFilters(filters)
        #expect(model.memoryScreen != before, "a different query keeps its own focus memory")
        #expect(model.focusRequest.target == model.items.first.map { .item($0.id) })
        #expect(model.focusRequest.token == 1)
    }

    // MARK: Paging

    @Test func focusNearTheEndLoadsTheNextPage() async throws {
        let model = LibraryGridModel(kind: .film, context: Self.adult, browser: FakeBrowser(recorder: Recorder()))
        await model.start()
        #expect(model.items.count == 20)
        #expect(model.hasMore)
        await model.focusMoved(to: model.items[1].id)
        #expect(model.items.count == 20, "focus far from the end asks for nothing")
        await model.focusMoved(to: model.items[2].id)
        #expect(model.items.count == 40, "within 18 items of the end the next page comes")
        let last = try #require(model.items.last)
        await model.focusMoved(to: last.id)
        #expect(model.items.count == Self.films.count)
        await model.focusMoved(to: model.items.last!.id)
        #expect(!model.hasMore)
        #expect(model.items.count == Self.films.count)
    }

    // MARK: Review fixes (WP-10 second pass)

    @Test func aFailedRatingsLookupRequestsNothingAndRetryLooksThemUpAgain() async {
        let recorder = Recorder()
        recorder.admittedFailures.withLock { $0 = 1 }
        let model = LibraryGridModel(kind: .film, context: Self.lowered, browser: FakeBrowser(recorder: recorder))
        await model.start()
        #expect(model.phase == .failed, "a failed lookup shows the failure, not \"No films yet\"")
        #expect(model.query() == nil, "no query while the ratings are unresolved")
        #expect(recorder.queries.withLock { $0.isEmpty }, "nothing requested")
        await model.retry()
        #expect(recorder.admittedCalls.withLock { $0 } == 2, "retry fetches the ratings again")
        #expect(model.phase == .content)
        #expect(recorder.queries.withLock { $0.last?.contentRatings } == ["U", "PG"])
    }

    @Test func aReconnectMidwayRebuildsThePagerFromWhereItStopped() async throws {
        let recorder = Recorder()
        let model = LibraryGridModel(kind: .film, context: Self.adult, browser: FakeBrowser(recorder: recorder))
        await model.start()
        #expect(model.items.count == 20)
        recorder.pageFailures.withLock { $0 = 1 }
        await model.focusMoved(to: model.items.last!.id)
        #expect(model.items.count == 40, "one fresh pager carries on at once")
        #expect(recorder.queries.withLock { $0.last?.startOffset } == 20)
        #expect(!model.pagingStalled)
    }

    @Test func pagingThatKeepsFailingStallsAndResumesWhenTheSessionIsReady() async throws {
        let recorder = Recorder()
        let model = LibraryGridModel(kind: .film, context: Self.adult, browser: FakeBrowser(recorder: recorder))
        await model.start()
        recorder.pageFailures.withLock { $0 = 2 }
        await model.focusMoved(to: model.items.last!.id)
        #expect(model.items.count == 20)
        #expect(model.pagingStalled && model.hasMore, "never a silent stop: placeholders stay and paging resumes")
        #expect(model.phase == .content)
        await model.startOrRetry()
        #expect(model.items.count == 40)
        #expect(!model.pagingStalled)
        #expect(Set(model.items.map(\.id)).count == 40, "no gaps or duplicates")
        #expect(model.items.map(\.id) == Self.films.prefix(40).map(\.id))
    }

    @Test func aKidsCollectionsPassTheCertificateCheckAndNeedTwoTitles() async {
        let kid = RowContext(profileID: "1003", serviceCeiling: .u, ceiling: .u)
        var browser = FakeBrowser(recorder: Recorder())
        browser.members = [
            MediaSummary(id: "1", kind: .film, title: "A", certificate: "U"),
            MediaSummary(id: "2", kind: .film, title: "B", certificate: "PG"),
            MediaSummary(id: "3", kind: .film, title: "C", certificate: nil),
            MediaSummary(id: "4", kind: .film, title: "D", certificate: "gb/U"),
        ]
        let model = LibraryGridModel(kind: .film, context: kid, isKid: true, browser: browser)
        await model.start()
        #expect(model.collections.map(\.id) == ["9001"])
        #expect(model.collections.first?.childCount == 2, "only U titles count; unrated fails closed")
        let items = LibraryQueryBuilder.guardCollectionItems(browser.members, context: kid, isKid: true)
        #expect(items.map(\.id) == ["1", "4"])
        #expect(LibraryQueryBuilder.guardCollectionItems(browser.members, context: kid, isKid: false).count == 4)

        browser.members = Array(browser.members.prefix(1))
        let single = LibraryGridModel(kind: .film, context: kid, isKid: true, browser: browser)
        await single.start()
        #expect(single.collections.isEmpty, "a collection with fewer than two titles is hidden")
    }

    @Test func collectionNamesDropATrailingCollection() {
        #expect(LibraryStrings.collectionTitle("Toy Story Collection") == "Toy Story")
        #expect(LibraryStrings.collectionTitle("Harbour stories") == "Harbour stories")
        #expect(LibraryStrings.collectionTitle("Collection") == "Collection")
    }

    @Test func gridLayoutSpreadsColumnsAndReservesTheRailGutter() {
        let plain = LibraryGridLayout(showsRail: false)
        #expect(plain.gap == 64)
        #expect(plain.trailingInset == 80, "six columns end at x 1840")
        let rail = LibraryGridLayout(showsRail: true)
        #expect(rail.trailingInset >= 80 + LibraryGridLayout.railWidth + LibraryGridLayout.railGap)
        #expect(rail.trailingInset - (80 + LibraryGridLayout.railWidth + LibraryGridLayout.railGap) < 5)
    }
}
