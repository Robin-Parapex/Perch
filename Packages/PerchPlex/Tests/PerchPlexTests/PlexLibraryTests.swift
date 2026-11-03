import Foundation
import PerchCore
import Testing

@testable import PerchPlex

private let partner = PlexUserID("1002")

private func ids(_ row: MediaRow) -> [String] { row.items.map(\.id) }

private func query(_ request: URLRequest, _ name: String) -> String? {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == name }?.value
}

/// Continue-watching JSON with one inline hub of the given items.
private func hub(_ items: String) -> String {
    #"{"MediaContainer":{"size":1,"Hub":[{"hubIdentifier":"home.continue","type":"mixed","Metadata":[\#(items)]}]}}"#
}

private let movieInProgress =
    #"{"ratingKey":"1001","type":"movie","title":"Harbour Lights","viewOffset":2400000,"duration":7200000}"#

@Suite("Library Home rows", .timeLimit(.minutes(1)))
struct PlexLibraryHomeTests {
    @Test func continueWatchingAndUpNextSplitAndDedupeBySeries() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.scriptHome()

        let rows = try await rig.library.homeRows()

        // 1001 and 2101 have offsets. 2102 is the same series as 2101, so it is not Up next.
        #expect(ids(rows.continueWatching) == ["1001", "2101"])
        #expect(ids(rows.upNext) == ["3102"])
        #expect(rows.continueWatching.id == "plex.continueWatching")
        #expect(rows.continueWatching.title == "Continue watching")
        #expect(rows.upNext.id == "plex.upNext")
        #expect(rows.upNext.title == "Up next in your series")
        #expect(rows.recentlyAdded.id == "plex.recentlyAdded")
        #expect(rows.recentlyAdded.title == "Recently added")
        #expect(rows.row(id: "plex.upNext") == rows.upNext)
        #expect(rows.row(id: "nope") == nil)
        // Up next had an item, so on deck was not asked.
        #expect(await rig.transport.requests(forPath: "/library/onDeck").isEmpty)
    }

    @Test func onDeckFillsUpNextOnlyWhenItIsEmpty() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: "/hubs/continueWatching", json: hub(movieInProgress))
        await rig.transport.script(path: "/library/onDeck", fixture: "lib-on-deck")
        await rig.transport.script(path: "/hubs", fixture: "lib-hubs")

        let rows = try await rig.library.homeRows()

        #expect(ids(rows.continueWatching) == ["1001"])
        #expect(ids(rows.upNext) == ["2102", "3102"])
        #expect(await rig.transport.requests(forPath: "/library/onDeck").count == 1)
    }

    @Test func onDeckSkipsSeriesAlreadyInContinueWatching() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        let inProgressEpisode = #"""
            {"ratingKey":"2101","type":"episode","title":"Salt","grandparentRatingKey":"2000",
             "parentIndex":1,"index":3,"viewOffset":600000}
            """#
        await rig.transport.script(path: "/hubs/continueWatching", json: hub(inProgressEpisode))
        await rig.transport.script(path: "/library/onDeck", fixture: "lib-on-deck")
        await rig.transport.script(path: "/hubs", fixture: "lib-hubs")

        let rows = try await rig.library.homeRows()

        #expect(ids(rows.continueWatching) == ["2101"])
        #expect(ids(rows.upNext) == ["3102"])
    }

    @Test func aHubWithoutInlineItemsIsFollowedByItsKey() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(
            path: "/hubs/continueWatching",
            json: #"{"MediaContainer":{"size":1,"Hub":[{"hubIdentifier":"home.continue","key":"/hubs/continueWatching/items","size":1}]}}"#)
        await rig.transport.script(
            path: "/hubs/continueWatching/items",
            json: #"{"MediaContainer":{"size":1,"Metadata":[\#(movieInProgress)]}}"#)
        await rig.transport.script(path: "/hubs", fixture: "lib-hubs")
        await rig.transport.script(path: "/library/onDeck", json: #"{"MediaContainer":{"size":0}}"#)

        let rows = try await rig.library.homeRows()

        #expect(ids(rows.continueWatching) == ["1001"])
        #expect(await rig.transport.requests(forPath: "/hubs/continueWatching/items").count == 1)
    }

    @Test func recentlyAddedKeepsVideoRecentHubsMergedNewestFirst() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.scriptHome()

        let rows = try await rig.library.homeRows()

        // Music, photo, video, playlist, continue, on deck and curated hubs are dropped; the films hub
        // and the "mixed" television hub (episode, season, show) merge by addedAt.
        #expect(ids(rows.recentlyAdded) == ["1003", "2104", "3100", "1002", "3000"])
        #expect(rows.recentlyAdded.items.map(\.kind) == [.film, .episode, .season, .film, .series])
        // A season carries its series title and poster for display.
        let season = rows.recentlyAdded.items[2]
        #expect(season.seriesTitle == "Cold Harbour Files")
        #expect(season.seriesThumbPath == "/library/metadata/3000/thumb/1")
        #expect(await rig.transport.requests(forPath: "/library/recentlyAdded").isEmpty)
    }

    @Test func aMixedRecentHubCountsAndItsItemsAreFilteredByKind() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        let hubs = #"""
            {"MediaContainer":{"size":2,"Hub":[
             {"hubIdentifier":"home.television.recent","type":"mixed","Metadata":[
               {"ratingKey":"10","type":"season","title":"Season 3","parentRatingKey":"9","parentTitle":"Some Show","index":3,"addedAt":5},
               {"ratingKey":"11","type":"clip","title":"A clip","addedAt":9},
               {"ratingKey":"12","type":"album","title":"An album","addedAt":8}]},
             {"hubIdentifier":"home.music.recent","type":"album","Metadata":[
               {"ratingKey":"13","type":"movie","title":"Odd","addedAt":7}]}]}}
            """#
        await rig.transport.script(path: "/hubs/continueWatching", json: hub(movieInProgress))
        await rig.transport.script(path: "/hubs", json: hubs)
        await rig.transport.script(path: "/library/onDeck", json: #"{"MediaContainer":{"size":0}}"#)

        let rows = try await rig.library.homeRows()

        #expect(ids(rows.recentlyAdded) == ["10"])
        #expect(rows.recentlyAdded.items.first?.seriesTitle == "Some Show")
    }

    @Test func recentlyAddedFallsBackToTheRecentlyAddedListWhenNoHubQualifies() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        let onlyMusic = #"""
            {"MediaContainer":{"size":1,"Hub":[{"hubIdentifier":"music.recent.added.3","type":"album",
             "Metadata":[{"ratingKey":"9001","type":"album","title":"A"}]}]}}
            """#
        await rig.transport.script(path: "/hubs/continueWatching", fixture: "lib-continue-watching")
        await rig.transport.script(path: "/hubs", json: onlyMusic)
        await rig.transport.script(path: "/library/recentlyAdded", fixture: "lib-recently-added")

        let rows = try await rig.library.homeRows()

        #expect(ids(rows.recentlyAdded) == ["1003", "2104", "3100"])
    }

    @Test func aHubIdentifierWithoutRecentIsNotRecentlyAdded() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        let hubs = #"""
            {"MediaContainer":{"size":2,"Hub":[
             {"hubIdentifier":"movie.toprated.1","type":"movie","Metadata":[{"ratingKey":"7","type":"movie","title":"Top"}]},
             {"hubIdentifier":"Movie.RecentlyAdded.1","type":"movie","Metadata":[{"ratingKey":"8","type":"movie","title":"New"}]}]}}
            """#
        await rig.transport.script(path: "/hubs/continueWatching", json: hub(movieInProgress))
        await rig.transport.script(path: "/hubs", json: hubs)
        await rig.transport.script(path: "/library/onDeck", json: #"{"MediaContainer":{"size":0}}"#)

        let rows = try await rig.library.homeRows()

        #expect(ids(rows.recentlyAdded) == ["8"])
    }

    @Test func concurrentCallersShareOneFetch() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: "/hubs/continueWatching", fixture: "lib-continue-watching", held: true)
        await rig.transport.script(path: "/library/onDeck", fixture: "lib-on-deck")
        await rig.transport.script(path: "/hubs", fixture: "lib-hubs")
        let library = rig.library

        let callers = (0..<3).map { _ in Task { try await library.homeRows() } }
        #expect(await rig.transport.waitForRequests(path: "/hubs/continueWatching", count: 1))
        // Let the other two callers reach the shared fetch before it is released.
        try await Task.sleep(for: .milliseconds(150))
        await rig.transport.release(path: "/hubs/continueWatching")
        var results: [PlexHomeRows] = []
        for caller in callers { results.append(try await caller.value) }

        #expect(results.dropFirst().allSatisfy { $0 == results[0] })
        #expect(await rig.transport.requests(forPath: "/hubs/continueWatching").count == 1)
        #expect(await rig.transport.requests(forPath: "/hubs").count == 1)
    }

    @Test func aGoodFetchIsSnapshottedAndAFailedOneKeepsTheLastGoodRows() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: "/hubs/continueWatching", fixture: "lib-continue-watching")
        await rig.transport.script(path: "/hubs/continueWatching", json: "", status: 500)
        await rig.transport.script(path: "/library/onDeck", fixture: "lib-on-deck")
        await rig.transport.script(path: "/hubs", fixture: "lib-hubs")
        #expect(rig.library.cachedHomeRows(profileID: "1001") == nil)

        let good = try await rig.library.homeRows()
        let cached = try #require(rig.library.cachedHomeRows(profileID: "1001"))
        #expect(cached == good)

        await #expect(throws: PlexError.http(500)) { try await rig.library.homeRows() }
        #expect(rig.library.cachedHomeRows(profileID: "1001") == good)
        #expect(await rig.library.currentRows() == good)
        // The snapshot reads without a request.
        let sent = await rig.transport.requests.count
        _ = rig.library.cachedHomeRows(profileID: "1001")
        #expect(await rig.transport.requests.count == sent)
    }

    @Test func aResultThatArrivesAfterAProfileSwitchIsDropped() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: "/hubs/continueWatching", fixture: "lib-continue-watching", held: true)
        await rig.transport.script(path: "/library/onDeck", fixture: "lib-on-deck")
        await rig.transport.script(path: "/hubs", fixture: "lib-hubs")
        let library = rig.library
        let fetch = Task { try await library.homeRows() }
        #expect(await rig.transport.waitForRequests(path: "/hubs/continueWatching", count: 1))

        await rig.sessionRig.transport.scriptSwitch(
            userID: "1002", .response(status: 200, body: Fixture.data("switch_ok")))
        try await rig.session.switchProfile(to: partner, pin: "1234")
        await rig.transport.release(path: "/hubs/continueWatching")

        await #expect(throws: CancellationError.self) { try await fetch.value }
        #expect(rig.library.cachedHomeRows(profileID: "1001") == nil)
        #expect(rig.library.cachedHomeRows(profileID: "1002") == nil)
        #expect(await library.currentRows() == nil)
    }

    @Test func eachProfileHasItsOwnSnapshot() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.scriptHome()
        let ownerRows = try await rig.library.homeRows()
        await rig.sessionRig.transport.scriptSwitch(
            userID: "1002", .response(status: 200, body: Fixture.data("switch_ok")))
        try await rig.session.switchProfile(to: partner, pin: "1234")

        #expect(rig.library.cachedHomeRows(profileID: "1002") == nil)
        #expect(rig.library.cachedHomeRows(profileID: "1001") == ownerRows)
        _ = try await rig.library.homeRows()
        #expect(rig.library.cachedHomeRows(profileID: "1002") != nil)
    }
}

@Suite("Library session observation", .timeLimit(.minutes(1)))
struct PlexLibraryObservationTests {
    @Test func signOutWipesEverySnapshotAndMemory() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.scriptHome()
        _ = try await rig.library.homeRows()
        let library = rig.library
        await library.observe(rig.session)
        #expect(library.cachedHomeRows(profileID: "1001") != nil)

        await rig.session.signOut()

        #expect(await eventually { library.cachedHomeRows(profileID: "1001") == nil })
        #expect(await eventually { await library.currentRows() == nil })
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: rig.snapshotDirectory.path)) ?? []).isEmpty)
    }

    @Test func aProfileSwitchClearsMemoryButKeepsTheSnapshot() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.scriptHome()
        let library = rig.library
        _ = try await library.homeRows()
        await library.observe(rig.session)
        await rig.sessionRig.transport.scriptSwitch(
            userID: "1002", .response(status: 200, body: Fixture.data("switch_ok")))

        try await rig.session.switchProfile(to: partner, pin: "1234")

        #expect(await eventually { await library.currentRows() == nil })
        #expect(library.cachedHomeRows(profileID: "1001") != nil)
    }

    @Test func aLaunchInTheSignedOutStateDeletesNothing() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.scriptHome()
        _ = try await rig.library.homeRows()
        // A relaunch: a new session that has not resumed yet reports signed out.
        let relaunched = rig.sessionRig.makeSession(transport: FakeTransport())
        let second = LibraryRig.make(
            sessionRig: rig.sessionRig, session: relaunched, directory: rig.snapshotDirectory)

        await second.library.observe(relaunched)
        try await Task.sleep(for: .milliseconds(150))

        #expect(second.library.cachedHomeRows(profileID: "1001") != nil)
    }
}

@Suite("Library sections, metadata and episodes", .timeLimit(.minutes(1)))
struct PlexLibraryMetadataTests {
    @Test func sectionsListVideoLibrariesAndCountReadsTotalSize() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: "/library/sections", fixture: "lib-sections")
        await rig.transport.script(path: "/library/sections/1/all", fixture: "lib-section-all-p1")

        let sections = try await rig.library.sections()
        let count = try await rig.library.count(sectionID: "1")

        #expect(sections.map(\.id) == ["1", "2", "4", "5"])
        #expect(sections.map(\.kind) == [.film, .series, .film, .film])
        #expect(sections.map(\.isOtherVideos) == [false, false, true, true])
        #expect(count == 137)
        let request = try #require(await rig.transport.requests(forPath: "/library/sections/1/all").first)
        #expect(query(request, "X-Plex-Container-Size") == "1")
    }

    @Test func hubsKeepEveryHubWithItsIdentifierAndType() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: "/hubs", fixture: "lib-hubs")

        let hubs = try await rig.library.hubs()

        #expect(hubs.count == 9)
        #expect(hubs[2].id == "home.movies.recent")
        #expect(hubs[2].type == "movie")
        #expect(hubs[2].items.map(\.id) == ["1003", "1002"])
        #expect(hubs[3].type == "mixed")
        #expect(hubs[4].items.isEmpty)
    }

    @Test func extrasComeFromTheExtrasEndpointWhenNotInline() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: "/library/metadata/2103", fixture: "lib-metadata-episode")
        await rig.transport.script(path: "/library/metadata/2103/extras", fixture: "lib-extras")

        let detail = try await rig.library.detail(ratingKey: "2103")

        #expect(detail.id == "2103")
        #expect(detail.extras.map(\.id).first == "5001")
        #expect(detail.extras.count == 6)
        #expect(await rig.transport.requests(forPath: "/library/metadata/2103/extras").count == 1)
        let metadata = try #require(await rig.transport.requests(forPath: "/library/metadata/2103").first)
        #expect(query(metadata, "checkFiles") == nil)
        #expect(query(metadata, "includeExtras") == "1")
    }

    @Test func inlineExtrasNeedNoSecondRequestAndPlaybackAsksToCheckFiles() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: "/library/metadata/1001", fixture: "lib-metadata-film-extras")

        let detail = try await rig.library.detailForPlayback(ratingKey: "1001")

        #expect(!detail.extras.isEmpty)
        #expect(await rig.transport.requests(forPath: "/library/metadata/1001/extras").isEmpty)
        let request = try #require(await rig.transport.requests(forPath: "/library/metadata/1001").first)
        #expect(query(request, "checkFiles") == "1")
    }

    @Test func aMissingItemThrowsDecoding() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: "/library/metadata/9", json: #"{"MediaContainer":{"size":0}}"#)
        await #expect(throws: PlexError.decoding) { try await rig.library.detail(ratingKey: "9") }
    }

    @Test func childrenAndEpisodesComeFromTheirEndpoints() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: "/library/metadata/2000/children", fixture: "lib-children-seasons")
        await rig.transport.script(path: "/library/metadata/2000/allLeaves", fixture: "lib-all-leaves")

        let seasons = try await rig.library.children(of: "2000")
        let episodes = try await rig.library.allEpisodes(ofSeries: "2000")

        #expect(seasons.map(\.id) == ["2090", "2100", "2200"])
        #expect(episodes.map(\.id) == ["2091", "2101", "2102", "2103", "2201"])
    }

    @Test func nextEpisodeGoesBySeasonThenEpisodeAndNeverBackToSpecials() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: "/library/metadata/2000/allLeaves", fixture: "lib-all-leaves")
        func episode(_ id: String, season: Int, number: Int) -> MediaSummary {
            MediaSummary(
                id: id, kind: .episode, title: id, seriesID: "2000", seasonNumber: season,
                episodeNumber: number)
        }

        let withinSeason = try await rig.library.nextEpisode(after: episode("2101", season: 1, number: 3))
        let acrossSeasons = try await rig.library.nextEpisode(after: episode("2103", season: 1, number: 5))
        let lastOfSeries = try await rig.library.nextEpisode(after: episode("2201", season: 2, number: 1))
        let special = try await rig.library.nextEpisode(after: episode("2091", season: 0, number: 1))
        let unnumbered = try await rig.library.nextEpisode(
            after: MediaSummary(id: "x", kind: .episode, title: "x", seriesID: "2000"))

        #expect(withinSeason?.id == "2102")
        #expect(acrossSeasons?.id == "2201")
        #expect(lastOfSeries == nil)
        // From a special the next is the next number in order; season 1 is only reached by number.
        #expect(special?.id == "2101")
        #expect(unnumbered == nil)
    }

    @Test func theTokenTravelsOnlyInHeaders() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.scriptHome()
        await rig.transport.script(path: "/library/sections", fixture: "lib-sections")
        await rig.transport.script(path: "/library/sections/1/all", fixture: "lib-section-all-p1")
        await rig.transport.script(path: "/library/metadata/1001", fixture: "lib-metadata-film-extras")
        await rig.transport.script(path: "/library/metadata/2000/children", fixture: "lib-children-seasons")

        _ = try await rig.library.homeRows()
        _ = try await rig.library.sections()
        _ = try await rig.library.count(sectionID: "1")
        _ = try await rig.library.detail(ratingKey: "1001")
        _ = try await rig.library.children(of: "2000")

        let requests = await rig.transport.requests
        #expect(requests.count > 5)
        for request in requests {
            #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == testServerToken)
            let url = request.url?.absoluteString ?? ""
            #expect(!url.contains(testServerToken) && !url.localizedCaseInsensitiveContains("token"))
        }
    }
}

@Suite("Library watched state and playback", .timeLimit(.minutes(1)))
struct PlexLibraryWatchedTests {
    private func scriptRest(_ rig: LibraryRig) async {
        await rig.transport.script(path: "/library/onDeck", fixture: "lib-on-deck")
        await rig.transport.script(path: "/hubs", fixture: "lib-hubs")
        await rig.transport.script(path: "/:/scrobble", json: "{}")
        await rig.transport.script(path: "/:/unscrobble", json: "{}")
    }

    @Test func markWatchedIsOptimisticAndALateRefreshCannotUndoIt() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        let after = hub(#"{"ratingKey":"3102","type":"episode","title":"F","grandparentRatingKey":"3000","parentIndex":2,"index":2}"#)
        let path = "/hubs/continueWatching"
        await rig.transport.script(path: path, fixture: "lib-continue-watching")
        // The second read was taken before the toggle: it still shows 1001 in progress.
        await rig.transport.script(path: path, fixture: "lib-continue-watching", held: true)
        await rig.transport.script(path: path, json: after)
        await scriptRest(rig)
        let library = rig.library
        let initial = try await library.homeRows()
        #expect(ids(initial.continueWatching).contains("1001"))
        let late = Task { try await library.homeRows() }
        #expect(await rig.transport.waitForRequests(path: path, count: 2))

        try await library.markWatched("1001")

        // Optimistic: gone from Continue watching at once, before any refresh finished.
        let optimistic = try #require(await library.currentRows())
        #expect(!ids(optimistic.continueWatching).contains("1001"))
        #expect(await rig.transport.requests(forPath: "/:/scrobble").count == 1)
        let scrobble = try #require(await rig.transport.requests(forPath: "/:/scrobble").first)
        #expect(query(scrobble, "key") == "1001")

        await rig.transport.release(path: path)
        let lateRows = try await late.value
        // The late read still had 1001 in progress, but the toggle is newer.
        #expect(!ids(lateRows.continueWatching).contains("1001"))
        // The snapshot never held the stale 1001 either (the follow-up refresh may already have run).
        let snapshot = try #require(rig.library.cachedHomeRows(profileID: "1001"))
        #expect(!ids(snapshot.continueWatching).contains("1001"))

        await library.settle()
        #expect(await rig.transport.requests(forPath: path).count == 3)
        let final = try #require(await library.currentRows())
        #expect(ids(final.continueWatching).isEmpty)
        #expect(ids(final.upNext) == ["3102"])
    }

    @Test func markWatchedAndUnwatchedChangeTheViewCountInMemory() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        let path = "/hubs/continueWatching"
        await rig.transport.script(path: path, fixture: "lib-continue-watching")
        // Later reads wait, so the optimistic state is what the test sees.
        await rig.transport.script(path: path, fixture: "lib-continue-watching", held: true)
        await rig.transport.script(path: path, fixture: "lib-continue-watching")
        await scriptRest(rig)
        await rig.transport.script(path: "/library/recentlyAdded", fixture: "lib-recently-added")
        let library = rig.library
        _ = try await library.homeRows()
        func viewCount() async -> Int? {
            await library.currentRows()?.recentlyAdded.items.first { $0.id == "1003" }?.viewCount
        }
        #expect(await viewCount() == 0)

        try await library.markWatched("1003")
        let watched = await viewCount()
        try await library.markUnwatched("1003")
        let unwatched = await viewCount()

        #expect((watched ?? 0) >= 1)
        #expect(unwatched == 0)
        #expect(await rig.transport.requests(forPath: "/:/unscrobble").count == 1)
        #expect(await rig.transport.waitForRequests(path: path, count: 2))
        await rig.transport.release(path: path)
        await library.settle()
    }

    @Test func aDeniedProfileSendsNothing() async throws {
        let rig = try await LibraryRig.make(decision: .denied(.role))
        defer { rig.cleanup() }
        await scriptRest(rig)
        let item = MediaSummary(id: "1001", kind: .film, title: "F")

        await #expect(throws: PlexError.notAllowed) { try await rig.library.markWatched("1001") }
        await #expect(throws: PlexError.notAllowed) { try await rig.library.markUnwatched("1001") }
        await #expect(throws: PlexError.notAllowed) {
            try await rig.library.startPlayback(item: item, sessionID: nil)
        }

        #expect(await rig.transport.requests.isEmpty)
        #expect(await rig.authoriser.actions == [.play, .play, .play])
    }

    @Test func aProfileWithNoSettingsIsNotAllowed() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        try await rig.sessionRig.settings.update { $0.profiles = [:] }
        await scriptRest(rig)

        await #expect(throws: PlexError.notAllowed) { try await rig.library.markWatched("1001") }

        #expect(await rig.transport.requests.isEmpty)
        #expect(await rig.authoriser.actions.isEmpty)
    }

    @Test func aLimitedDecisionIsAllowed() async throws {
        let rig = try await LibraryRig.make(decision: .limited)
        defer { rig.cleanup() }
        await scriptRest(rig)
        await rig.transport.script(path: "/hubs/continueWatching", fixture: "lib-continue-watching")

        try await rig.library.markWatched("1001")
        await rig.library.settle()

        #expect(await rig.transport.requests(forPath: "/:/scrobble").count == 1)
    }

    @Test func startPlaybackHandsBackAReporterWithTheCallersSessionID() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        let item = MediaSummary(id: "1001", kind: .film, title: "F", durationMs: 7_200_000)

        let reporter = try await rig.library.startPlayback(item: item, sessionID: "SESSION-1")

        #expect(reporter.sessionID == "SESSION-1")
        #expect(await rig.authoriser.actions == [.play])
        #expect(await rig.transport.requests.isEmpty)
    }

    @Test func progressUpdatesContinueWatchingAndMovesTheSeriesOutOfUpNext() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.scriptHome()
        let library = rig.library
        _ = try await library.homeRows()
        let generation = await rig.session.currentGeneration()

        // An Up next episode starts: it goes to the front of Continue watching.
        await library.playbackProgressed(
            PlaybackProgress(itemID: "3102", state: .playing, positionMs: 120_000, durationMs: 3_000_000),
            generation: generation)
        // An item already there only changes its offset.
        await library.playbackProgressed(
            PlaybackProgress(itemID: "1001", state: .playing, positionMs: 3_000_000, durationMs: 7_200_000),
            generation: generation)
        // Nothing known about this one, and zero is not progress.
        await library.playbackProgressed(
            PlaybackProgress(itemID: "nope", state: .playing, positionMs: 5_000, durationMs: nil),
            generation: generation)
        await library.playbackProgressed(
            PlaybackProgress(itemID: "2101", state: .playing, positionMs: 0, durationMs: nil),
            generation: generation)

        let rows = try #require(await library.currentRows())
        #expect(ids(rows.continueWatching) == ["3102", "1001", "2101"])
        #expect(rows.continueWatching.items[0].viewOffsetMs == 120_000)
        #expect(rows.continueWatching.items[1].viewOffsetMs == 3_000_000)
        #expect(rows.continueWatching.items[2].viewOffsetMs == 600_000)
        #expect(rows.upNext.items.isEmpty)
    }

    @Test func aWatchStateChangeFromThePlayerAppliesWithoutARequest() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.scriptHome()
        let library = rig.library
        _ = try await library.homeRows()
        let sent = await rig.transport.requests.count

        await library.watchStateChanged(
            itemID: "2101", watched: true, generation: await rig.session.currentGeneration())

        let rows = try #require(await library.currentRows())
        #expect(ids(rows.continueWatching) == ["1001"])
        #expect(await rig.transport.requests.count == sent)
    }
}

@Suite("Library review fixes", .timeLimit(.minutes(1)))
struct PlexLibraryReviewFixTests {
    private func home(_ rig: LibraryRig) async {
        await rig.scriptHome()
        await rig.transport.script(path: "/:/scrobble", json: "{}")
        await rig.transport.script(path: "/:/unscrobble", json: "{}")
    }

    // Sign-out wipe

    @Test func aSignOutAfterAnyEarlierStateWipesTheSnapshots() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        rig.snapshots.write(PlexHomeRows(), profileID: "1001", machineID: "m")
        let library = rig.library

        await library.sessionChanged(.connecting)
        await library.sessionChanged(.serverUnreachable)
        #expect(library.cachedHomeRows(profileID: "1001") != nil)
        await library.sessionChanged(.signedOut)

        #expect(library.cachedHomeRows(profileID: "1001") == nil)
    }

    @Test func aFirstObservedSignedOutWipesNothing() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        rig.snapshots.write(PlexHomeRows(), profileID: "1001", machineID: "m")

        await rig.library.sessionChanged(.signedOut)
        await rig.library.sessionChanged(.signedOut)

        #expect(rig.library.cachedHomeRows(profileID: "1001") != nil)
    }

    // Write-through

    @Test func aToggleReachesTheSnapshotEvenWhenTheRefreshFails() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await home(rig)
        await rig.transport.script(path: "/hubs/continueWatching", json: "", status: 500)
        let library = rig.library
        let initial = try await library.homeRows()
        #expect(ids(initial.continueWatching).contains("1001"))

        try await library.markWatched("1001")
        await library.settle()

        let cached = try #require(library.cachedHomeRows(profileID: "1001"))
        #expect(!ids(cached.continueWatching).contains("1001"))
    }

    @Test func playerProgressReachesTheSnapshot() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await home(rig)
        let library = rig.library
        _ = try await library.homeRows()
        let generation = await rig.session.currentGeneration()

        await library.playbackProgressed(
            PlaybackProgress(itemID: "1001", state: .playing, positionMs: 3_100_000, durationMs: 7_200_000),
            generation: generation)

        let cached = try #require(library.cachedHomeRows(profileID: "1001"))
        #expect(cached.continueWatching.items.first { $0.id == "1001" }?.viewOffsetMs == 3_100_000)
    }

    @Test func aStaleGenerationFromThePlayerIsIgnored() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await home(rig)
        let library = rig.library
        let initial = try await library.homeRows()
        let generation = await rig.session.currentGeneration()

        await library.playbackProgressed(
            PlaybackProgress(itemID: "1001", state: .playing, positionMs: 3_100_000, durationMs: 7_200_000),
            generation: generation &+ 1)
        await library.watchStateChanged(itemID: "1001", watched: true, generation: generation &+ 1)

        #expect(await library.currentRows() == initial)
        #expect(library.cachedHomeRows(profileID: "1001") == initial)
    }

    // Provider and profile

    @Test func aRefreshForAnotherProfileThrowsInsteadOfReturningTheCurrentOnesRows() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await home(rig)
        await rig.sessionRig.transport.scriptSwitch(
            userID: "1002", .response(status: 200, body: Fixture.data("switch_ok")))
        try await rig.session.switchProfile(to: partner, pin: "1234")
        let provider = PlexHomeRowProvider(
            id: PlexHomeRows.continueWatchingID, title: "Continue watching", placement: .home(order: 0),
            library: rig.library)
        let stale = RowContext(profileID: "1001", serviceCeiling: .eighteen, ceiling: .eighteen)
        let current = RowContext(profileID: "1002", serviceCeiling: .eighteen, ceiling: .eighteen)

        await #expect(throws: CancellationError.self) { try await provider.refreshRow(in: stale) }
        let row = try await provider.refreshRow(in: current)
        #expect(row.id == PlexHomeRows.continueWatchingID)
    }

    // Pager

    @Test func aPagerMadeBeforeAProfileSwitchReturnsNothingAfterIt() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(
            path: "/library/sections/1/all",
            json: #"{"MediaContainer":{"size":1,"totalSize":1,"Metadata":[{"ratingKey":"1","type":"movie","title":"T"}]}}"#)
        let pager = await rig.library.pager(sectionID: "1", sort: nil)
        await rig.sessionRig.transport.scriptSwitch(
            userID: "1002", .response(status: 200, body: Fixture.data("switch_ok")))
        try await rig.session.switchProfile(to: partner, pin: "1234")

        await #expect(throws: CancellationError.self) { try await pager.nextPage() }
        #expect(await rig.transport.requests(forPath: "/library/sections/1/all").isEmpty)
    }

    // Recently added fallback

    @Test func theRecentlyAddedFallbackKeepsOnlyFilmsAndShows() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        let onlyMusic = #"""
            {"MediaContainer":{"size":1,"Hub":[{"hubIdentifier":"music.recent.added.3","type":"album",
             "Metadata":[{"ratingKey":"9001","type":"album","title":"A"}]}]}}
            """#
        let mixed = #"""
            {"MediaContainer":{"size":4,"Metadata":[
             {"ratingKey":"1","type":"movie","title":"M"},
             {"ratingKey":"2","type":"album","title":"A"},
             {"ratingKey":"3","type":"clip","title":"C"},
             {"ratingKey":"4","type":"show","title":"S"}]}}
            """#
        await rig.transport.script(path: "/hubs/continueWatching", fixture: "lib-continue-watching")
        await rig.transport.script(path: "/hubs", json: onlyMusic)
        await rig.transport.script(path: "/library/recentlyAdded", json: mixed)
        await rig.transport.script(path: "/library/onDeck", json: #"{"MediaContainer":{"size":0}}"#)

        let rows = try await rig.library.homeRows()

        #expect(ids(rows.recentlyAdded) == ["1", "4"])
    }

    // Snapshot machine

    @Test func aSnapshotFromAnotherServerIsDroppedOnceTheSessionIsReady() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        rig.snapshots.write(PlexHomeRows(), profileID: "1001", machineID: "ANOTHER-SERVER")
        #expect(rig.library.cachedHomeRows(profileID: "1001") != nil)

        await rig.library.observe(rig.session)

        #expect(rig.library.cachedHomeRows(profileID: "1001") == nil)
    }
}
