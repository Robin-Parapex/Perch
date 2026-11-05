import Foundation
import PerchCore
import Testing

@testable import PerchApp

/// WP-09 Home: rows from the cache in the first frame, ordering, the hero rule, refresh in place and the states.
@MainActor @Suite("HomeModel")
struct HomeModelTests {
    private struct Offline: Error {}

    nonisolated private static func item(
        _ id: String, kind: MediaKind = .film, offset: Int? = nil, added: TimeInterval? = nil, season: Int? = nil,
        episode: Int? = nil, views: Int = 0
    ) -> MediaSummary {
        MediaSummary(
            id: id, kind: kind, title: "Title \(id)", seasonNumber: season, episodeNumber: episode, durationMs: 3_600_000,
            viewOffsetMs: offset, viewCount: views, addedAt: added.map { Date(timeIntervalSince1970: $0) })
    }

    nonisolated private static func row(_ id: String, _ items: [MediaSummary]) -> MediaRow {
        MediaRow(id: id, title: id, items: items)
    }

    /// A source whose refresh must never run before the assertions that read the cache.
    private static func source(
        _ id: String, cached: MediaRow?, refresh: @escaping @Sendable () async throws -> MediaRow = { throw Offline() }
    ) -> HomeModel.Source {
        HomeModel.Source(id: id, cached: { cached }, refresh: refresh)
    }

    nonisolated private static let cw = HomeRowID.continueWatching
    nonisolated private static let upNext = HomeRowID.upNext
    nonisolated private static let recent = HomeRowID.recentlyAdded

    @Test func cachedRowsAreThereStraightAfterConstruction() {
        let model = HomeModel(sources: [
            Self.source(Self.cw, cached: Self.row(Self.cw, [Self.item("1", offset: 60_000)])),
            Self.source(Self.recent, cached: Self.row(Self.recent, [Self.item("2")])),
        ])
        // No await: the first frame reads exactly this.
        #expect(model.rows.map(\.id) == [Self.cw, Self.recent])
        #expect(model.state == .content)
        #expect(model.heroItem?.id == "1")
        #expect(model.heroResumes)
    }

    @Test func emptyRowsAreDroppedAndOrderIsKept() {
        let model = HomeModel(sources: [
            Self.source(Self.cw, cached: Self.row(Self.cw, [Self.item("1", offset: 5)])),
            Self.source(Self.upNext, cached: Self.row(Self.upNext, [])),
            Self.source(Self.recent, cached: Self.row(Self.recent, [Self.item("3")])),
        ])
        #expect(model.rows.map(\.id) == [Self.cw, Self.recent])
    }

    @Test func heroRule() {
        let film = Self.item("f", added: 100)
        let newerSeries = Self.item("s", kind: .series, added: 200)
        let newestEpisode = Self.item("e", kind: .episode, added: 300)
        let recent = Self.row(Self.recent, [film, newestEpisode, newerSeries])
        // Continue watching first.
        #expect(HomeModel.hero(continueWatching: Self.row(Self.cw, [Self.item("c", offset: 9)]), recentlyAdded: recent)?.id == "c")
        // Else the newest Recently added film or series, never an episode.
        #expect(HomeModel.hero(continueWatching: Self.row(Self.cw, []), recentlyAdded: recent)?.id == "s")
        // Else nothing.
        #expect(HomeModel.hero(continueWatching: nil, recentlyAdded: Self.row(Self.recent, [newestEpisode])) == nil)
        #expect(HomeModel.hero(continueWatching: nil, recentlyAdded: nil) == nil)
        // A Recently added pick plays rather than resumes.
        let model = HomeModel(sources: [Self.source(Self.recent, cached: recent)])
        #expect(model.heroItem?.id == "s")
        #expect(!model.heroResumes)
    }

    @Test func failedRefreshKeepsRowsAndRaisesTheNoticeOnce() async {
        let cached = Self.row(Self.cw, [Self.item("1", offset: 5)])
        let model = HomeModel(sources: [Self.source(Self.cw, cached: cached)])
        await model.refresh()
        #expect(model.rows == [cached])
        #expect(model.offlineNotice)
        model.offlineNotice = false  // the notice went away
        await model.refresh()
        #expect(!model.offlineNotice, "a retry that fails again does not show the notice again")
        #expect(model.state == .content)
    }

    @Test func refreshReplacesAnItemInPlace() async {
        let before = Self.row(Self.cw, [Self.item("1", offset: 60_000), Self.item("2", offset: 5)])
        let after = Self.row(Self.cw, [Self.item("1", offset: 600_000), Self.item("2", offset: 5)])
        let model = HomeModel(sources: [Self.source(Self.cw, cached: before, refresh: { after })])
        await model.refresh()
        #expect(model.rows.first?.items.map(\.id) == ["1", "2"])
        #expect(model.rows.first?.items.first?.viewOffsetMs == 600_000)
        #expect(!model.offlineNotice)
    }

    @Test func firstLaunchResolvesToEmptyOrOffline() async {
        // Nothing cached: first launch until the refresh says what is there.
        let empty = HomeModel(sources: [Self.source(Self.cw, cached: nil, refresh: { Self.row(Self.cw, []) })])
        #expect(empty.state == .firstLaunch)
        await empty.refresh()
        #expect(empty.state == .emptyLibrary)

        let offline = HomeModel(sources: [Self.source(Self.cw, cached: nil)])
        await offline.refresh()
        #expect(offline.state == .offlineNoCache)
        #expect(!offline.offlineNotice, "the corner notice is for cached rows only")

        // A row arriving later turns any message into content.
        let later = HomeModel(sources: [Self.source(Self.cw, cached: nil, refresh: { Self.row(Self.cw, [Self.item("1")]) })])
        await later.refresh()
        #expect(later.state == .content)
    }

    @Test func firstLaunchTimeoutAsksTheServerState() {
        var unreachable = false
        let model = HomeModel(sources: [Self.source(Self.cw, cached: nil)], isServerUnreachable: { unreachable })
        model.firstLaunchTimedOut()
        #expect(model.state == .emptyLibrary)

        let other = HomeModel(sources: [Self.source(Self.cw, cached: nil)], isServerUnreachable: { unreachable })
        unreachable = true
        other.firstLaunchTimedOut()
        #expect(other.state == .offlineNoCache)

        let third = HomeModel(sources: [Self.source(Self.cw, cached: nil)])
        third.serverStateChanged(unreachable: true)
        #expect(third.state == .offlineNoCache)
    }

    @Test func allEmptyCacheIsAnEmptyLibraryAtOnce() {
        let model = HomeModel(sources: [
            Self.source(Self.cw, cached: Self.row(Self.cw, [])),
            Self.source(Self.recent, cached: Self.row(Self.recent, [])),
        ])
        #expect(model.state == .emptyLibrary)
    }

    @Test func seriesPlaysFirstUnwatchedElseFirstEpisode() {
        let s0 = Self.item("s0", kind: .episode, season: 0, episode: 1)
        let e11 = Self.item("e11", kind: .episode, season: 1, episode: 1, views: 1)
        let e12 = Self.item("e12", kind: .episode, season: 1, episode: 2)
        let e21 = Self.item("e21", kind: .episode, season: 2, episode: 1)
        #expect(HomeModel.episodeToPlay(in: [e21, s0, e12, e11])?.id == "e12")
        let w12 = Self.item("e12", kind: .episode, season: 1, episode: 2, views: 1)
        let w21 = Self.item("e21", kind: .episode, season: 2, episode: 1, views: 1)
        #expect(HomeModel.episodeToPlay(in: [w21, w12, e11, s0])?.id == "e11")
        #expect(HomeModel.episodeToPlay(in: []) == nil)
    }

    @Test func strings() {
        #expect(HomeStrings.timeLeft(ms: 31 * 60_000) == "31 min left")
        #expect(HomeStrings.timeLeft(ms: 72 * 60_000) == "1 h 12 min left")
        #expect(HomeStrings.timeLeft(ms: 30_000) == "Almost done")
        #expect(HomeStrings.duration(ms: 112 * 60_000) == "1 h 52 min")
        var episode = Self.item("e", kind: .episode, offset: 29 * 60_000, season: 2, episode: 5)
        episode.seriesTitle = "Severance"
        #expect(HomeStrings.heroMetadata(episode) == "S2 E5 \u{00B7} Title e \u{00B7} 31 min left")
        var unstarted = episode
        unstarted.viewOffsetMs = nil
        unstarted.durationMs = nil
        #expect(HomeStrings.heroMetadata(unstarted) == "S2 E5 \u{00B7} Title e")
        #expect(HomeStrings.caption(for: episode, in: HomeRowID.continueWatching).subtitle == "S2 E5 \u{00B7} 31 min left")
        #expect(HomeStrings.caption(for: episode, in: HomeRowID.upNext).subtitle == "S2 E5 Title e")
        var film = Self.item("f")
        film.year = 2024
        film.certificate = "15"
        #expect(HomeStrings.heroMetadata(film) == "2024 \u{00B7} 1 h \u{00B7} 15")
        var series = Self.item("s", kind: .series)
        series.year = 2024
        #expect(HomeStrings.caption(for: series, in: HomeRowID.recentlyAdded).subtitle == "Series \u{00B7} 2024")
    }
}
