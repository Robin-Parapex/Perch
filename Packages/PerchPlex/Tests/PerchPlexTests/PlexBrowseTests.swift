import Foundation
import PerchCore
import Testing

@testable import PerchPlex

private let base = URL(string: "http://192.0.2.10:32400")!
private let token = "SECRET-TOKEN-123"

private func items(_ request: URLRequest) -> [String: String] {
    let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(query.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}

private func names(_ request: URLRequest) -> [String] {
    (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map(\.name)
}

private func expectTokenOnlyInHeader(_ request: URLRequest) {
    #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == token)
    #expect(request.url?.absoluteString.contains(token) == false)
    #expect(request.httpMethod == "GET")
}

private func movies(_ ids: ClosedRange<Int>, total: Int) -> String {
    let body = ids.map { #"{"ratingKey":"\#($0)","type":"movie","title":"T\#($0)","contentRating":"PG"}"# }
        .joined(separator: ",")
    return #"{"MediaContainer":{"size":\#(ids.count),"totalSize":\#(total),"Metadata":[\#(body)]}}"#
}

@Suite("Library browse", .timeLimit(.minutes(1)))
struct PlexBrowseTests {
    let endpoints = testEndpoints

    // MARK: URL building

    @Test func sectionItemsCarryTypeFiltersAndSortedItems() {
        let query = PlexSectionQuery(
            sectionID: "3", kind: .series, sort: .rating, genreIDs: ["9", "12"], decade: 2010,
            resolution: "1080", unwatched: true, collectionID: "77", contentRatings: ["PG", "gb/12A"])
        let request = endpoints.sectionItems(
            base: base, token: token, query: query, start: 50, size: 100)
        #expect(request.url?.path == "/library/sections/3/all")
        let q = items(request)
        #expect(q["type"] == "2")
        #expect(q["sort"] == "rating:desc")
        #expect(q["genre"] == "12,9")
        #expect(q["decade"] == "2010")
        #expect(q["resolution"] == "1080")
        #expect(q["unwatched"] == "1")
        #expect(q["collection"] == "77")
        #expect(q["contentRating"] == "PG,gb/12A")
        #expect(q["X-Plex-Container-Start"] == "50")
        let filterNames = names(request).dropLast(2)
        #expect(Array(filterNames) == filterNames.sorted())
        expectTokenOnlyInHeader(request)
    }

    @Test func sortCases() {
        #expect(PlexSectionSort.recentlyAdded.value == "addedAt:desc")
        #expect(PlexSectionSort.title.value == "titleSort")
        #expect(PlexSectionSort.year.value == "year:desc")
        #expect(PlexSectionSort.raw("duration:asc").value == "duration:asc")
    }

    @Test func filmsUseTypeOneAndNoFilterItemsWhenUnset() {
        let query = PlexSectionQuery(sectionID: "1", kind: .film)
        let q = items(endpoints.sectionItems(base: base, token: token, query: query, start: 0, size: 50))
        #expect(q["type"] == "1")
        for name in ["genre", "decade", "resolution", "unwatched", "collection", "contentRating", "sort"] {
            #expect(q[name] == nil)
        }
    }

    @Test func firstCharacterUsesTheSameFiltersWithoutPagingOrSort() {
        let query = PlexSectionQuery(
            sectionID: "1", kind: .film, sort: .title, unwatched: true, contentRatings: ["G", "PG"])
        let request = endpoints.firstCharacter(base: base, token: token, query: query)
        #expect(request.url?.path == "/library/sections/1/firstCharacter")
        let q = items(request)
        #expect(q["type"] == "1")
        #expect(q["unwatched"] == "1")
        #expect(q["contentRating"] == "G,PG")
        #expect(q["sort"] == nil)
        #expect(q["X-Plex-Container-Start"] == nil)
        expectTokenOnlyInHeader(request)
    }

    @Test func filterValuePaths() {
        for kind in [PlexFilterKind.genre, .decade, .resolution, .contentRating] {
            let request = endpoints.filterValues(
                base: base, token: token, sectionID: "4", kind: kind)
            #expect(request.url?.path == "/library/sections/4/\(kind.rawValue)")
            expectTokenOnlyInHeader(request)
        }
    }

    @Test func collectionsAndChildrenRequests() {
        let query = PlexSectionQuery(sectionID: "1", kind: .film, contentRatings: ["PG", "U"])
        let list = endpoints.sectionCollections(base: base, token: token, query: query)
        #expect(list.url?.path == "/library/sections/1/collections")
        #expect(items(list)["contentRating"] == "PG,U")
        #expect(items(list)["type"] == "1")
        expectTokenOnlyInHeader(list)
        let children = endpoints.collectionChildren(
            base: base, token: token, collectionID: "55", start: 0, size: 200)
        #expect(children.url?.path == "/library/collections/55/children")
        expectTokenOnlyInHeader(children)
    }

    @Test func aCollectionIDCannotAddPathComponents() {
        let request = endpoints.collectionChildren(
            base: base, token: token, collectionID: "../1", start: 0, size: 10)
        // Percent-encoded: the slash stays inside one path segment.
        let raw = request.url?.absoluteString ?? ""
        #expect(raw.contains("/library/collections/..%2F1/children"))
    }

    // MARK: pager

    @Test func queryPagerStartsAtTheOffsetAndContinues() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        let path = "/library/sections/1/all"
        await rig.transport.script(path: path, json: movies(201...203, total: 300))
        await rig.transport.script(path: path, json: movies(204...205, total: 300))
        let query = PlexSectionQuery(
            sectionID: "1", kind: .film, sort: .title, contentRatings: ["PG"], startOffset: 200)
        let pager = await rig.library.pager(query: query)
        #expect(await pager.offset == 200)

        let first = try await pager.nextPage()
        let second = try await pager.nextPage()

        #expect(first.map(\.id) == ["201", "202", "203"])
        #expect(second.map(\.id) == ["204", "205"])
        #expect(await pager.offset == 205)
        let requests = await rig.transport.requests(forPath: path)
        #expect(requests.map { items($0)["X-Plex-Container-Start"] } == ["200", "203"])
        #expect(requests.map { items($0)["X-Plex-Container-Size"] } == ["50", "100"])
        #expect(requests.allSatisfy { items($0)["contentRating"] == "PG" && items($0)["type"] == "1" })
    }

    @Test func anEmptyRatingSetReturnsNothingWithoutARequest() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        let query = PlexSectionQuery(sectionID: "1", kind: .film, contentRatings: [])
        let pager = await rig.library.pager(query: query)

        #expect(try await pager.nextPage().isEmpty)
        #expect(await pager.isFinished)
        #expect(try await rig.library.firstCharacters(query: query).isEmpty)
        #expect(try await rig.library.collections(query: query).isEmpty)
        #expect(try await rig.library.collectionItems(collectionID: "5", query: query).isEmpty)
        let sent = await rig.transport.requests.filter { $0.url?.path.hasPrefix("/library") == true }
        #expect(sent.isEmpty)
    }

    @Test func theLegacyPagerStillSendsNoTypeFilter() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        let path = "/library/sections/1/all"
        await rig.transport.script(path: path, json: movies(1...2, total: 2))
        let pager = await rig.library.pager(sectionID: "1", sort: "titleSort")
        _ = try await pager.nextPage()
        let request = try #require(await rig.transport.requests(forPath: path).first)
        #expect(items(request)["type"] == nil)
        #expect(items(request)["sort"] == "titleSort")
    }

    // MARK: letters

    @Test func letterOffsetsAreCumulativeInServerOrder() {
        let buckets = [
            PlexLetterBucket(title: "#", size: 4), PlexLetterBucket(title: "A", size: 10),
            PlexLetterBucket(title: "B", size: 0), PlexLetterBucket(title: "C", size: 3),
        ]
        #expect(letterOffsets(buckets) == ["#": 0, "A": 4, "B": 14, "C": 14])
        #expect(letterOffsets([]).isEmpty)
    }

    @Test func firstCharacterDecodesAndFoldsNonLettersToHash() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        let json = #"""
            {"MediaContainer":{"size":4,"Directory":[
            {"key":"#","title":"#","size":2},{"key":"a","title":"A","size":"5"},
            {"key":"1","title":"1","size":1},{"key":"b","title":"b","size":3}]}}
            """#
        await rig.transport.script(path: "/library/sections/1/firstCharacter", json: json)
        let buckets = try await rig.library.firstCharacters(
            query: PlexSectionQuery(sectionID: "1", kind: .film))
        #expect(
            buckets == [
                PlexLetterBucket(title: "#", size: 2), PlexLetterBucket(title: "A", size: 5),
                PlexLetterBucket(title: "#", size: 1), PlexLetterBucket(title: "B", size: 3),
            ])
        #expect(letterOffsets(buckets)["A"] == 2)
        #expect(letterOffsets(buckets)["B"] == 8)
    }

    // MARK: filters and collections

    @Test func filterValuesDecode() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        let json = #"""
            {"MediaContainer":{"Directory":[{"key":"5","title":"Drama"},{"key":"7","title":"Comedy"},{"title":"no key"}]}}
            """#
        await rig.transport.script(path: "/library/sections/1/genre", json: json)
        let values = try await rig.library.filterValues(sectionID: "1", kind: .genre)
        #expect(values == [PlexFilterValue(key: "5", title: "Drama"), PlexFilterValue(key: "7", title: "Comedy")])
    }

    @Test func collectionsDecode() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        let json = #"""
            {"MediaContainer":{"size":2,"Metadata":[
            {"ratingKey":"88","type":"collection","title":"Marvel","thumb":"/library/metadata/88/thumb/1","childCount":"23"},
            {"type":"collection","title":"No key"}]}}
            """#
        await rig.transport.script(path: "/library/sections/1/collections", json: json)
        let list = try await rig.library.collections(
            query: PlexSectionQuery(sectionID: "1", kind: .film))
        #expect(
            list == [
                PlexCollection(
                    id: "88", title: "Marvel", thumbPath: "/library/metadata/88/thumb/1", childCount: 23)
            ])
    }

    @Test func collectionItemsMapAndApplyTheRatingSetAsWell() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        let json = #"""
            {"MediaContainer":{"size":3,"Metadata":[
            {"ratingKey":"1","type":"movie","title":"A","contentRating":"PG"},
            {"ratingKey":"2","type":"movie","title":"B","contentRating":"R"},
            {"ratingKey":"3","type":"movie","title":"C"}]}}
            """#
        await rig.transport.script(path: "/library/collections/9/children", json: json)
        let all = try await rig.library.collectionItems(
            collectionID: "9", query: PlexSectionQuery(sectionID: "1", kind: .film))
        #expect(all.map(\.id) == ["1", "2", "3"])
        let filtered = try await rig.library.collectionItems(
            collectionID: "9",
            query: PlexSectionQuery(sectionID: "1", kind: .film, contentRatings: ["PG"]))
        #expect(filtered.map(\.id) == ["1"])
    }

    // MARK: admitted ratings

    @Test func admittedRatingsUnderUKAndUSCeilingsFailClosedOnUnknowns() {
        let all = ["U", "PG", "gb/12A", "gb/15", "gb/18", "G", "PG-13", "R", "NC-17", "TV-Y", "NR", "Unrated", ""]
        func admitted(_ ceiling: RatingCeiling) -> Set<String> {
            PlexLibrary.admittedContentRatings(all, ceiling: ceiling)
        }
        #expect(admitted(.u) == ["U", "G", "TV-Y"])
        #expect(admitted(.pg) == ["U", "PG", "G", "TV-Y"])
        #expect(admitted(.twelveA) == ["U", "PG", "gb/12A", "G", "PG-13", "TV-Y"])
        #expect(!admitted(.twelveA).contains("NR"))
        #expect(admitted(.fifteen) == Set(all).subtracting(["gb/18", "NC-17"]))
        #expect(admitted(.fifteen).isSuperset(of: ["NR", "Unrated", "R"]))
        #expect(admitted(.eighteen) == Set(all))
    }

    @Test func admittedContentRatingsFetchesTheSectionValues() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        let json = #"""
            {"MediaContainer":{"Directory":[{"key":"gb/U","title":"U"},{"key":"gb/15","title":"15"},{"key":"NR","title":"NR"}]}}
            """#
        await rig.transport.script(path: "/library/sections/1/contentRating", json: json)
        let set = try await rig.library.admittedContentRatings(sectionID: "1", ceiling: .pg)
        #expect(set == ["gb/U"])
    }
}
