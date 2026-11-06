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

/// A `/hubs/search` reply in the live server's shape: one hub per type, collections as `Directory` rows, plus hubs
/// Search ignores (people, music).
private let searchJSON = #"""
    {"MediaContainer": {"size": 6, "Hub": [
      {"type": "movie", "hubIdentifier": "movie", "title": "Movies", "size": 2, "Metadata": [
        {"ratingKey": "11", "type": "movie", "title": "Harbour Lights", "year": 2019, "contentRating": "gb/PG", "thumb": "/t/11"},
        {"ratingKey": "12", "type": "movie", "title": "Harbour Nights", "contentRating": "18"},
        {"ratingKey": "11", "type": "movie", "title": "Harbour Lights (again)"}
      ]},
      {"type": "show", "hubIdentifier": "show", "title": "Shows", "size": 1, "Metadata": [
        {"ratingKey": "20", "type": "show", "title": "Harbour Files", "contentRating": "TV-14"},
        {"ratingKey": "99", "type": "movie", "title": "Wrong type in the show hub"}
      ]},
      {"type": "episode", "hubIdentifier": "episode", "title": "Episodes", "size": 1, "Metadata": [
        {"ratingKey": "21", "type": "episode", "title": "Pilot", "grandparentRatingKey": "20", "grandparentTitle": "Harbour Files", "parentIndex": 1, "index": 1}
      ]},
      {"type": "collection", "hubIdentifier": "collection", "title": "Collections", "size": 1, "Directory": [
        {"ratingKey": "30", "type": "collection", "subtype": "movie", "title": "Harbour stories", "librarySectionID": 1, "childCount": 5, "thumb": "/t/30"}
      ]},
      {"type": "actor", "hubIdentifier": "actor", "title": "People", "size": 1, "Directory": [
        {"id": "7", "tag": "Someone", "type": "tag"}
      ]},
      {"type": "artist", "hubIdentifier": "artist", "title": "Artists", "size": 1, "Metadata": [
        {"ratingKey": "40", "type": "artist", "title": "Harbour Band"}
      ]},
      {"type": "album", "hubIdentifier": "album", "title": "Albums", "size": 0}
    ]}}
    """#

@Suite("Library search", .timeLimit(.minutes(1)))
struct PlexSearchTests {
    let endpoints = testEndpoints

    // MARK: URL building

    @Test func searchURLCarriesQueryLimitAndTokenOnlyInHeader() {
        let request = endpoints.search(base: base, token: token, query: "the lantern", limit: 20)
        #expect(request.url?.path == "/hubs/search")
        let q = items(request)
        #expect(q["query"] == "the lantern")
        #expect(q["limit"] == "20")
        #expect(q["includeCollections"] == "1")
        #expect(q["contentRating"] == nil)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == token)
        #expect(request.url?.absoluteString.contains(token) == false)
        #expect(request.httpMethod == "GET")
    }

    @Test func searchURLEncodesPlusAndAmpersand() {
        let request = endpoints.search(base: base, token: token, query: "a+b & c", limit: 5)
        let raw = request.url?.absoluteString ?? ""
        #expect(raw.contains("query=a%2Bb%20%26%20c"))
        #expect(items(request)["query"] == "a+b & c")
    }

    @Test func searchURLSendsSortedRatingFilter() {
        let request = endpoints.search(
            base: base, token: token, query: "x", limit: 0, contentRatings: ["U", "gb/PG", "PG"])
        let q = items(request)
        #expect(q["contentRating"] == "PG,U,gb/PG")
        #expect(q["limit"] == "1")
    }

    // MARK: Decoding and grouping

    @Test func groupsByHubTypeAndIgnoresOtherHubs() throws {
        let container = try PlexWireContainer.decode(from: Data(searchJSON.utf8))
        let results = PlexLibraryMapping.searchResults(container.hubs)
        #expect(results.films.map(\.id) == ["11", "12"])  // the duplicate is dropped
        #expect(results.films.first?.certificate == "gb/PG")
        #expect(results.films.first?.thumbPath == "/t/11")
        #expect(results.series.map(\.id) == ["20"])  // the movie in the show hub is not a series
        #expect(results.episodes.map(\.id) == ["21"])
        #expect(results.episodes.first?.seriesID == "20")
        #expect(results.episodes.first?.seasonNumber == 1)
        #expect(results.collections == [
            PlexSearchCollection(
                id: "30", title: "Harbour stories", thumbPath: "/t/30", childCount: 5, sectionID: "1", kind: .film)
        ])
        #expect(results.count == 5)
    }

    @Test func emptyReplyIsEmpty() throws {
        let container = try PlexWireContainer.decode(from: Data(#"{"MediaContainer": {"size": 0}}"#.utf8))
        #expect(PlexLibraryMapping.searchResults(container.hubs).isEmpty)
    }

    // MARK: Library

    @Test func searchFetchesAndGroups() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: "/hubs/search", json: searchJSON)
        let results = try await rig.library.search(query: "  harbour ", contentRatings: ["PG"])
        #expect(results.films.count == 2)
        let requests = await rig.transport.requests(forPath: "/hubs/search")
        #expect(requests.count == 1)
        let q = items(requests[0])
        #expect(q["query"] == "harbour")
        #expect(q["contentRating"] == "PG")
        #expect(requests[0].url?.absoluteString.contains("TOKEN") == false)
    }

    @Test func blankQueryAndEmptyRatingSetRequestNothing() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: "/hubs/search", json: searchJSON)
        #expect(try await rig.library.search(query: "   ").isEmpty)
        #expect(try await rig.library.search(query: "harbour", contentRatings: []).isEmpty)
        #expect(await rig.transport.requests(forPath: "/hubs/search").isEmpty)
    }
}
