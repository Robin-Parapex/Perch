import Foundation
import PerchCore
import Testing

@testable import PerchPlex

private func container(_ fixture: String) throws -> PlexWireContainer {
    try PlexWireContainer.decode(from: Fixture.data(fixture))
}

private func container(json: String) throws -> PlexWireContainer {
    try PlexWireContainer.decode(from: Data(json.utf8))
}

@Suite("Library sections")
struct PlexLibrarySectionDecodeTests {
    @Test func keepsOnlyMovieAndShowSections() throws {
        let sections = PlexLibraryMapping.sections(try container("lib-sections").directory ?? [])
        #expect(sections.map(\.id) == ["1", "2", "4", "5"])
        #expect(sections.map(\.kind) == [.film, .series, .film, .film])
        #expect(sections.first?.title == "Films")
    }

    @Test func otherVideosBySubtypeAgentOrScanner() throws {
        let sections = PlexLibraryMapping.sections(try container("lib-sections").directory ?? [])
        #expect(sections.map(\.isOtherVideos) == [false, false, true, true])
    }

    @Test func scannerAloneMarksOtherVideos() throws {
        let c = try container(
            json: #"{"MediaContainer":{"Directory":[{"key":7,"type":"movie","title":"Clips","scanner":"Plex Video Files"}]}}"#)
        let sections = PlexLibraryMapping.sections(c.directory ?? [])
        #expect(sections.count == 1)
        #expect(sections[0].id == "7")
        #expect(sections[0].isOtherVideos)
    }

    @Test func musicAndPhotoAreDropped() throws {
        let c = try container(
            json: #"{"MediaContainer":{"Directory":[{"key":"1","type":"artist","title":"M"},{"key":"2","type":"photo","title":"P"}]}}"#)
        #expect(PlexLibraryMapping.sections(c.directory ?? []).isEmpty)
    }
}

@Suite("Library rows and hubs")
struct PlexLibraryRowDecodeTests {
    @Test func continueWatchingMapsFilmAndEpisodes() throws {
        let items = try container("lib-continue-watching").items
        let rows = PlexLibraryMapping.summaries(items)
        #expect(rows.map(\.id) == ["1001", "2101", "2102", "3102"])
        let film = rows[0]
        #expect(film.kind == .film)
        #expect(film.title == "Harbour Lights")
        #expect(film.year == 2019)
        #expect(film.certificate == "PG-13")
        #expect(film.viewOffsetMs == 2_400_000)
        #expect(film.durationMs == 7_199_000)  // the first part's duration wins
        #expect(film.isInProgress)
        #expect(film.addedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(film.lastViewedAt == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func episodeFieldsCarryTheSeries() throws {
        let rows = PlexLibraryMapping.summaries(try container("lib-continue-watching").items)
        let episode = rows[1]
        #expect(episode.kind == .episode)
        #expect(episode.seriesID == "2000")
        #expect(episode.seriesTitle == "The Lantern Keepers")
        #expect(episode.seasonID == "2100")
        #expect(episode.seasonNumber == 1)
        #expect(episode.episodeNumber == 3)
        #expect(episode.seriesThumbPath == "/library/metadata/2000/thumb/1700000000")
        #expect(episode.durationMs == 2_700_000)
        // The next episodes have no offset, so Up next can tell them from Continue watching.
        #expect(rows[2].viewOffsetMs == nil)
        #expect(rows[2].seriesID == "2000")
        #expect(rows[3].seriesID == "3000")
    }

    @Test func onDeckDecodesTopLevelMetadata() throws {
        let c = try container("lib-on-deck")
        #expect(c.hubs.isEmpty)
        #expect(PlexLibraryMapping.summaries(c.items).map(\.id) == ["2102", "3102"])
    }

    @Test func hubsKeepIdentifierTypeAndKey() throws {
        let hubs = try container("lib-hubs").hubs
        #expect(hubs.count == 9)
        #expect(hubs.map(\.hubIdentifier) == [
            "home.continue", "home.ondeck", "home.movies.recent", "home.television.recent",
            "home.music.recent", "home.photos.recent", "home.videos.recent", "movie.curated.1.1",
            "home.playlists",
        ])
        #expect(hubs.map(\.type) == [
            "mixed", "episode", "movie", "mixed", "album", "photo", "clip", "movie", "playlist",
        ])
        #expect(hubs[2].key == "/hubs/sections/1/recentlyAdded?type=1")
        #expect(hubs[2].more == true)
        #expect(hubs[2].size == 2)
        // Empty hubs arrive with a size of 0 and no Metadata.
        #expect(hubs[4].size == 0 && hubs[4].metadata == nil && hubs[4].more == false)
        let album = try container(
            json: #"{"MediaContainer":{"Metadata":[{"ratingKey":"9","type":"album","title":"A"}]}}"#)
        #expect(PlexLibraryMapping.summaries(album.items).first?.kind == .other)
    }

    @Test func mixedTelevisionHubHoldsShowSeasonAndEpisode() throws {
        let hub = try #require(try container("lib-hubs").hubs.first { $0.hubIdentifier == "home.television.recent" })
        let rows = PlexLibraryMapping.summaries(hub.metadata ?? [])
        #expect(rows.map(\.kind) == [.episode, .season, .series])
        #expect(rows[1].seriesTitle == "Cold Harbour Files")
        #expect(rows[1].seriesID == "3000")
        #expect(rows[1].seasonNumber == 2)
        #expect(rows[1].seriesThumbPath == "/library/metadata/3000/thumb/1")
    }

    @Test func continueWatchingComesAsAHubWithInlineItems() throws {
        let c = try container("lib-continue-watching")
        #expect(c.metadata == nil)
        let hub = try #require(c.hubs.first)
        #expect(hub.hubIdentifier == "continueWatching" && hub.type == "mixed")
        #expect(hub.more == true && hub.key == "/hubs/continueWatching/items")
        #expect(hub.metadata?.count == 4)
        // Real servers send librarySectionID as an int and leave viewCount out for unseen items.
        #expect(hub.metadata?.first?.librarySectionID == "1")
        #expect(PlexLibraryMapping.summaries(c.items)[2].viewCount == 0)
    }

    @Test func recentlyAddedMapsFilmEpisodeAndSeason() throws {
        let rows = PlexLibraryMapping.summaries(try container("lib-recently-added").items)
        #expect(rows.map(\.kind) == [.film, .episode, .season])
        let season = rows[2]
        #expect(season.seriesID == "3000")
        #expect(season.seriesTitle == "Cold Harbour Files")
        #expect(season.seasonNumber == 2)
    }

    @Test func sectionPageHasTotalAndRowCount() throws {
        let c = try container("lib-section-all-p1")
        #expect(c.totalCount == 137)
        #expect(c.rowCount == 3)
        #expect(c.offset == 0)
        let rows = PlexLibraryMapping.summaries(c.items)
        #expect(rows.map(\.id) == ["1001", "1002", "1003"])  // 1001 arrives as an int
        #expect(rows[1].addedAt == Date(timeIntervalSince1970: 1_790_000_100))  // a string date
        #expect(rows[0].viewCount == 1)
        #expect(rows[0].isWatched)
    }

    @Test func emptyPageStopsPaging() throws {
        let c = try container("lib-section-all-empty")
        #expect(c.rowCount == 0)
        #expect(c.items.isEmpty)
        #expect(c.totalCount == 137)
    }

    @Test func seasonsAndLeavesKeepSeasonZero() throws {
        let seasons = PlexLibraryMapping.summaries(try container("lib-children-seasons").items)
        #expect(seasons.map(\.seasonNumber) == [0, 1, 2])
        #expect(seasons.allSatisfy { $0.kind == .season && $0.seriesID == "2000" })
        let leaves = PlexLibraryMapping.summaries(try container("lib-all-leaves").items)
        #expect(leaves.count == 5)
        #expect(leaves[0].seasonNumber == 0)
        #expect(leaves[0].episodeNumber == 1)
        #expect(leaves.map(\.seasonNumber) == [0, 1, 1, 1, 2])
    }

    @Test func itemWithoutRatingKeyIsNotMapped() throws {
        let c = try container(
            json: #"{"MediaContainer":{"Metadata":[{"type":"movie","title":"No key"},{"ratingKey":"1","type":"movie","title":"Has key"}]}}"#)
        #expect(PlexLibraryMapping.summaries(c.items).map(\.id) == ["1"])
    }
}

@Suite("Library metadata")
struct PlexLibraryMetadataDecodeTests {
    private func episode() throws -> MediaDetail {
        let item = try #require(try container("lib-metadata-episode").metadata?.first)
        return try #require(PlexLibraryMapping.detail(item))
    }

    @Test func episodeDetailFields() throws {
        let detail = try episode()
        #expect(detail.id == "2103")
        #expect(detail.summary.kind == .episode)
        #expect(detail.summary.episodeNumber == 5)  // index arrives as a string
        #expect(detail.synopsis == "The keepers watch for a light that never comes.")
        #expect(detail.genres == ["Drama", "Mystery"])
        #expect(detail.studio == "Fictional Pictures")
        #expect(detail.externalIDs == ["imdb://tt0000501", "tmdb://501", "tvdb://5010"])
        #expect(detail.summary.viewOffsetMs == 120_000)
        let release = try #require(detail.releaseDate)
        let parts = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: release)
        #expect(parts.year == 2024 && parts.month == 3 && parts.day == 9)
    }

    @Test func librarySectionIDAcceptsAString() throws {
        let item = try #require(try container("lib-metadata-episode").metadata?.first)
        #expect(item.librarySectionID == "2")
        let film = try #require(try container("lib-metadata-film-extras").metadata?.first)
        #expect(film.librarySectionID == "1")  // an int in this fixture
    }

    @Test func markersCarryKindAndFinal() throws {
        let markers = try episode().markers
        #expect(markers.count == 4)
        #expect(markers[0] == MediaMarker(kind: .intro, startMs: 5000, endMs: 65000, isFinal: false))
        #expect(markers[1] == MediaMarker(kind: .credits, startMs: 1_800_000, endMs: 1_830_000, isFinal: false))
        #expect(markers[2] == MediaMarker(kind: .credits, startMs: 2_600_000, endMs: 2_700_000, isFinal: true))
        #expect(markers[3].kind == .other)
        let detail = try episode()
        #expect(detail.introMarker?.endMs == 65000)
        #expect(detail.creditsMarker?.startMs == 2_600_000)
    }

    @Test func chaptersAreMapped() throws {
        let chapters = try episode().chapters
        #expect(chapters.map(\.index) == [1, 2, 3])
        #expect(chapters.map(\.title) == ["Cold open", "The Signal", "Dawn"])
        #expect(chapters[1].startMs == 900_000)
        #expect(chapters[1].endMs == 1_800_000)
        #expect(chapters[2].thumbPath == "/library/metadata/2103/thumb/603")
    }

    @Test func streamFieldsAndDroppedElements() throws {
        let detail = try episode()
        #expect(detail.versions.count == 1)
        let version = detail.versions[0]
        #expect(version.id == "7001")
        #expect(version.videoCodec == "hevc")
        #expect(version.audioCodec == "eac3")
        #expect(version.videoResolution == "4k")
        #expect(version.container == "mkv")
        let part = try #require(version.parts.first)
        #expect(part.id == "8001")
        #expect(part.key == "/library/parts/8001/1700000000/file.mkv")
        #expect(part.sizeBytes == 4_123_456_789)
        #expect(part.durationMs == 2_699_500)
        #expect(part.isAccessible == true)
        // The odd stream (bad type) and the non-object element are dropped, the rest survive.
        #expect(part.streams.map(\.id) == ["9001", "9002", "9003", "9004"])

        let video = part.streams[0]
        #expect(video.kind == .video)
        #expect(video.codec == "hevc")
        #expect(video.dolbyVisionProfile == 8)
        #expect(video.bitDepth == 10)
        #expect(video.colourTransfer == "smpte2084")
        #expect(video.frameRate == 23.976)
        #expect(video.width == 3840 && video.height == 2160)
        #expect(video.isDefault && video.isSelected)

        let audio = part.streams[1]
        #expect(audio.kind == .audio)
        #expect(audio.channels == 6)
        #expect(audio.languageCode == "eng")
        #expect(audio.title == "English (EAC3 5.1)")

        let srt = part.streams[2]
        #expect(srt.kind == .subtitle)
        #expect(srt.format == "srt")
        #expect(srt.key == "/library/streams/9003")
        #expect(!srt.isForced)

        let pgs = part.streams[3]
        #expect(pgs.codec == "pgs")
        #expect(pgs.key == nil)  // embedded
        #expect(pgs.isForced)  // forced arrives as 1
    }

    @Test func filmExtrasInlineAndKinds() throws {
        let item = try #require(try container("lib-metadata-film-extras").metadata?.first)
        let detail = try #require(PlexLibraryMapping.detail(item))
        // The third extra has no rating key, so it is not kept.
        #expect(detail.extras.map(\.id) == ["5001", "5002"])
        #expect(detail.extras.map(\.kind) == [.trailer, .behindTheScenes])
        #expect(detail.extras[0].durationMs == 125_000)
        #expect(detail.tagline == "Some lights never go out.")
        #expect(detail.versions.first?.parts.first?.isAccessible == nil)
    }

    @Test func filmChaptersWithoutATagKeepTimesAndThumbs() throws {
        let item = try #require(try container("lib-metadata-film-extras").metadata?.first)
        let detail = try #require(PlexLibraryMapping.detail(item))
        #expect(detail.chapters.map(\.index) == [1, 2])
        #expect(detail.chapters.allSatisfy { $0.title == nil })
        #expect(detail.chapters[1].startMs == 900_000 && detail.chapters[1].endMs == 1_800_000)
        #expect(detail.chapters[0].thumbPath == "/library/metadata/1001/thumb/1700000001")
        #expect(detail.externalIDs == ["imdb://tt0000001", "tmdb://1", "tvdb://10"])
        #expect(detail.summary.durationMs == 7_199_000)
    }

    @Test func extrasEndpointKinds() throws {
        let extras = PlexLibraryMapping.extras(try container("lib-extras").items)
        #expect(extras.map(\.kind) == [.trailer, .deletedScene, .interview, .featurette, .short, .other])
    }

    @Test(arguments: [
        ("trailer", MediaExtra.Kind.trailer), ("behindTheScenes", .behindTheScenes),
        ("deletedScene", .deletedScene), ("interview", .interview), ("featurette", .featurette),
        ("short", .short), ("clip", .clip), ("unknown", .other),
    ])
    func extraKindFromSubtype(subtype: String, expected: MediaExtra.Kind) {
        #expect(PlexLibraryMapping.extraKind(extraType: nil, subtype: subtype) == expected)
    }

    @Test func extraTypeBeatsSubtype() {
        #expect(PlexLibraryMapping.extraKind(extraType: 5, subtype: "trailer") == .behindTheScenes)
        #expect(PlexLibraryMapping.extraKind(extraType: nil, subtype: nil) == .other)
    }
}

@Suite("Library leniency")
struct PlexLibraryLeniencyTests {
    @Test func idsAndNumbersAcceptIntOrString() throws {
        let c = try container(
            json: #"""
            {"MediaContainer":{"size":"1","totalSize":"9","Metadata":[
              {"ratingKey":42,"type":"movie","title":"T","year":"2020","duration":"6000","librarySectionID":3,"extraType":"1","index":"7"}
            ]}}
            """#)
        #expect(c.size == 1 && c.totalSize == 9)
        let item = try #require(c.metadata?.first)
        #expect(item.ratingKey == "42")
        #expect(item.year == 2020)
        #expect(item.duration == 6000)
        #expect(item.librarySectionID == "3")
        #expect(item.extraType == 1)
        #expect(item.index == 7)
    }

    @Test func boolsAcceptZeroOneOrTrueFalse() throws {
        let c = try container(
            json: #"""
            {"MediaContainer":{"Metadata":[{"ratingKey":"1","Media":[{"id":1,"Part":[{"id":1,"accessible":1,"exists":"false","Stream":[
              {"id":1,"streamType":3,"default":1,"selected":"1","forced":true},
              {"id":2,"streamType":3,"default":0,"selected":false,"forced":"0"}]}]}]}]}}
            """#)
        let part = try #require(c.metadata?.first?.media?.first?.part?.first)
        #expect(part.accessible == true)
        #expect(part.exists == false)
        let streams = part.stream ?? []
        #expect(streams[0].isDefault == true && streams[0].selected == true && streams[0].forced == true)
        #expect(streams[1].isDefault == false && streams[1].selected == false && streams[1].forced == false)
    }

    @Test func badElementsAreDroppedNotFatal() throws {
        let c = try container(
            json: #"""
            {"MediaContainer":{"Metadata":[
              "junk", null, 5,
              {"ratingKey":"1","type":"movie","title":"Kept",
               "Marker":["x",{"type":"intro","startTimeOffset":1,"endTimeOffset":2}],
               "Chapter":[7,{"index":1,"startTimeOffset":0,"endTimeOffset":5}],
               "Media":[false,{"id":1,"Part":[null,{"id":2,"Stream":[{"id":3,"streamType":1},[]]}]}]}
            ]}}
            """#)
        #expect(c.metadata?.count == 1)
        let item = try #require(c.metadata?.first)
        #expect(item.marker?.count == 1)
        #expect(item.chapter?.count == 1)
        #expect(item.media?.count == 1)
        #expect(item.media?.first?.part?.count == 1)
        #expect(item.media?.first?.part?.first?.stream?.count == 1)
    }

    @Test func wrongTypedFieldBecomesNilNotAFailure() throws {
        let c = try container(
            json: #"{"MediaContainer":{"Metadata":[{"ratingKey":"1","title":{"x":1},"duration":[1],"Genre":"Drama"}]}}"#)
        let item = try #require(c.metadata?.first)
        #expect(item.title == nil)
        #expect(item.duration == nil)
        #expect(item.genre == nil)
    }

    @Test func missingContainerIsEmpty() throws {
        let c = try container(json: "{}")
        #expect(c.items.isEmpty && c.hubs.isEmpty && c.rowCount == 0 && c.totalCount == nil)
    }

    @Test func notJSONThrowsDecoding() {
        #expect(throws: PlexError.decoding) {
            _ = try PlexWireContainer.decode(from: Data("<html>".utf8))
        }
    }
}
