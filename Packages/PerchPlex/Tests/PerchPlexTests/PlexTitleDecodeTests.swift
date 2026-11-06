import Foundation
import PerchCore
import Testing

@testable import PerchPlex

/// WP-11: what the title and series pages read from the server (cast, theme, seasons and episodes).
@Suite("Title page decoding")
struct PlexTitleDecodeTests {
    private func container(_ json: String) throws -> PlexWireContainer {
        try PlexWireContainer.decode(from: Data(json.utf8))
    }

    private let showJSON = """
        {"MediaContainer": {"size": 1, "Metadata": [
          {"ratingKey": "2000", "type": "show", "title": "The Lantern Keepers", "year": 2024, "contentRating": "TV-14",
           "childCount": 2, "leafCount": 10, "viewedLeafCount": 2, "theme": "/library/metadata/2000/theme/1700000000",
           "Role": [
             {"id": 71, "tag": "Mara Quill", "role": "Mara", "thumb": "https://metadata-static.plex.tv/people/1.jpg"},
             {"id": "72", "tag": "Ted Rowe", "role": "", "thumb": ""},
             {"tag": "  ", "role": "Nobody"},
             {"tag": "Ada Fenn", "thumb": "/library/metadata/2000/role/3"}
           ]}
        ]}}
        """

    @Test func castKeepsOrderNamesAndRoles() throws {
        let item = try #require(try container(showJSON).metadata?.first)
        let detail = try #require(PlexLibraryMapping.detail(item))
        #expect(detail.cast.map(\.name) == ["Mara Quill", "Ted Rowe", "Ada Fenn"])
        #expect(detail.cast.map(\.role) == ["Mara", nil, nil])
        #expect(detail.cast[0].id == "71")
        #expect(detail.cast[1].id == "72")
        #expect(detail.cast[2].id == "role-3")
        #expect(detail.cast[0].thumbPath == "https://metadata-static.plex.tv/people/1.jpg")
        #expect(detail.cast[1].thumbPath == nil)
        #expect(detail.cast[2].thumbPath == "/library/metadata/2000/role/3")
    }

    @Test func themePathAndSeriesCounts() throws {
        let item = try #require(try container(showJSON).metadata?.first)
        let detail = try #require(PlexLibraryMapping.detail(item))
        #expect(detail.themePath == "/library/metadata/2000/theme/1700000000")
        #expect(detail.summary.kind == .series)
        #expect(detail.childCount == 2)
        #expect(detail.leafCount == 10)
        #expect(detail.viewedLeafCount == 2)
    }

    @Test func noRolesOrThemeDecodesEmpty() throws {
        let c = try container(#"{"MediaContainer":{"Metadata":[{"ratingKey":"1","type":"movie","title":"A"}]}}"#)
        let item = try #require(c.metadata?.first)
        let detail = try #require(PlexLibraryMapping.detail(item))
        #expect(detail.cast.isEmpty)
        #expect(detail.themePath == nil)
    }

    @Test func themePathMustBeAPlainServerPath() {
        #expect(PlexLibraryMapping.themePath("/library/metadata/1/theme/2") == "/library/metadata/1/theme/2")
        #expect(PlexLibraryMapping.themePath("https://evil.example/theme") == nil)
        #expect(PlexLibraryMapping.themePath("//evil.example/theme") == nil)
        #expect(PlexLibraryMapping.themePath("/library/metadata/1/theme?X-Plex-Token=abc") == nil)
        #expect(PlexLibraryMapping.themePath("/library/../theme") == nil)
        #expect(PlexLibraryMapping.themePath(nil) == nil)
    }

    @Test func allLeavesGiveSeasonAndEpisodeNumbers() throws {
        let c = try container("""
            {"MediaContainer": {"size": 3, "Metadata": [
              {"ratingKey": "2110", "type": "episode", "title": "One", "grandparentRatingKey": "2000", "parentRatingKey": "2100", "parentIndex": 1, "index": 1, "viewCount": 1, "duration": 60000},
              {"ratingKey": "2101", "type": "episode", "title": "Three", "grandparentRatingKey": "2000", "parentRatingKey": "2100", "parentIndex": "1", "index": "3", "viewOffset": 20000, "duration": 60000},
              {"ratingKey": "2120", "type": "episode", "title": "Two one", "grandparentRatingKey": "2000", "parentRatingKey": "2200", "parentIndex": 2, "index": 1}
            ]}}
            """)
        let episodes = PlexLibraryMapping.summaries(c.items)
        #expect(episodes.map(\.seasonNumber) == [1, 1, 2])
        #expect(episodes.map(\.episodeNumber) == [1, 3, 1])
        #expect(episodes.map(\.seasonID) == ["2100", "2100", "2200"])
        #expect(episodes.map(\.seriesID) == ["2000", "2000", "2000"])
        #expect(episodes[0].isWatched)
        #expect(episodes[1].isInProgress)
    }

    @Test func themeHeadersCarryTheTokenAndTheURLDoesNot() throws {
        let endpoints = testEndpoints
        let headers = endpoints.themeHeaders(token: "SECRET-TOKEN-123")
        #expect(headers["X-Plex-Token"] == "SECRET-TOKEN-123")
        #expect(headers["Accept"] == nil)
        let url = try #require(
            endpoints.directPlayURL(base: URL(string: "http://192.0.2.10:32400")!, partKey: "/library/metadata/2000/theme/17"))
        #expect(url.absoluteString == "http://192.0.2.10:32400/library/metadata/2000/theme/17")
        #expect(!url.absoluteString.contains("SECRET"))
    }
}
