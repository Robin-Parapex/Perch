import Foundation
import PerchCore
import PerchDesign
import Testing

@testable import PerchApp

/// WP-11: the title and series pages' primary button, the next-episode choice, theme gating and routing.
@Suite("Title pages")
struct TitleLogicTests {
    private func film(offset: Int? = nil, views: Int = 0, duration: Int? = 6_000_000) -> MediaSummary {
        MediaSummary(id: "1", kind: .film, title: "F", durationMs: duration, viewOffsetMs: offset, viewCount: views)
    }

    private func episode(
        _ id: String, _ season: Int, _ number: Int, views: Int = 0, offset: Int? = nil, viewedAt: Int? = nil
    ) -> MediaSummary {
        MediaSummary(
            id: id, kind: .episode, title: "E\(number)", seriesID: "S", seasonID: "s\(season)", seasonNumber: season,
            episodeNumber: number, durationMs: 60_000, viewOffsetMs: offset, viewCount: views,
            lastViewedAt: viewedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }

    // MARK: Film primary button

    @Test func filmNotStartedPlaysFromTheStart() {
        let action = FilmPrimaryAction(film())
        #expect(action == .play)
        #expect(action.title == "Play")
        #expect(action.detail == nil)
        #expect(action.startMs == 0)
    }

    @Test func filmInProgressResumesWithTimeLeft() {
        let action = FilmPrimaryAction(film(offset: 2_400_000))
        #expect(action == .resume(remainingMs: 3_600_000))
        #expect(action.title == "Resume")
        #expect(action.detail == "1 h left")
        #expect(action.startMs == nil)
    }

    @Test func filmInProgressWithoutDurationShowsNoTimeLeft() {
        let action = FilmPrimaryAction(film(offset: 10_000, duration: nil))
        #expect(action == .resume(remainingMs: nil))
        #expect(action.detail == nil)
    }

    @Test func filmWatchedPlaysAgain() {
        let action = FilmPrimaryAction(film(views: 2))
        #expect(action == .playAgain)
        #expect(action.title == "Play again")
        #expect(action.startMs == 0)
    }

    // MARK: Series primary button

    @Test func nothingWatchedPlaysTheFirstEpisode() throws {
        let next = try #require(SeriesNext.choose(in: [episode("b", 1, 2), episode("a", 1, 1), episode("z", 0, 1)]))
        #expect(next.episode.id == "a")
        #expect(next.mode == .start)
        #expect(next.title == "Play")
        #expect(next.detail == "S1 E1")
    }

    @Test func playNextIsTheEpisodeAfterTheLastWatched() throws {
        let episodes = [
            episode("1", 1, 1, views: 1, viewedAt: 100), episode("2", 1, 2, views: 1, viewedAt: 200),
            episode("3", 2, 1), episode("4", 2, 2, views: 1, viewedAt: 300), episode("5", 2, 3),
        ]
        let next = try #require(SeriesNext.choose(in: episodes))
        #expect(next.episode.id == "5")
        #expect(next.mode == .next)
        #expect(next.title == "Play next")
        #expect(next.detail == "S2 E3")
        #expect(next.startMs == 0)
    }

    @Test func resumeWhenTheEpisodeInProgressIsTheLatestViewing() throws {
        let episodes = [
            episode("1", 1, 1, views: 1, viewedAt: 100), episode("2", 2, 3, offset: 20_000, viewedAt: 500),
            episode("3", 2, 4),
        ]
        let next = try #require(SeriesNext.choose(in: episodes))
        #expect(next.episode.id == "2")
        #expect(next.mode == .resume)
        #expect(next.title == "Resume")
        #expect(next.detail == "S2 E3")
        #expect(next.startMs == nil)
    }

    @Test func aLaterFinishedEpisodeWinsOverAnOldPartWatchedOne() throws {
        let episodes = [
            episode("1", 1, 1, offset: 5_000, viewedAt: 100), episode("2", 1, 2, views: 1, viewedAt: 900),
            episode("3", 1, 3),
        ]
        let next = try #require(SeriesNext.choose(in: episodes))
        #expect(next.episode.id == "3")
        #expect(next.mode == .next)
    }

    @Test func afterTheLastEpisodeWrapsToTheFirstUnwatched() throws {
        let episodes = [episode("1", 1, 1), episode("2", 1, 2, views: 1, viewedAt: 900)]
        let next = try #require(SeriesNext.choose(in: episodes))
        #expect(next.episode.id == "1")
        #expect(next.mode == .next)
    }

    @Test func everythingWatchedPlaysAgainFromTheFirst() throws {
        let episodes = [episode("1", 1, 1, views: 1, viewedAt: 1), episode("2", 1, 2, views: 1, viewedAt: 2)]
        let next = try #require(SeriesNext.choose(in: episodes))
        #expect(next.episode.id == "1")
        #expect(next.mode == .playAgain)
        #expect(next.title == "Play again")
    }

    @Test func specialsAreSkippedUnlessThereIsNothingElse() throws {
        let withRegular = [episode("s", 0, 1, viewedAt: 999), episode("1", 1, 1)]
        #expect(SeriesNext.choose(in: withRegular)?.episode.id == "1")
        let onlySpecials = [episode("s2", 0, 2), episode("s1", 0, 1)]
        #expect(SeriesNext.choose(in: onlySpecials)?.episode.id == "s1")
        #expect(SeriesNext.choose(in: []) == nil)
    }

    // MARK: Theme music

    @Test func themePlaysOnlyForAnAdultWithATheme() {
        #expect(ThemeMusicPolicy.plays(themePath: "/library/metadata/1/theme/2", isKid: false))
        #expect(!ThemeMusicPolicy.plays(themePath: "/library/metadata/1/theme/2", isKid: true))
        #expect(!ThemeMusicPolicy.plays(themePath: nil, isKid: false))
        #expect(!ThemeMusicPolicy.plays(themePath: "", isKid: false))
        #expect(!ThemeMusicPolicy.plays(themePath: "/library/metadata/1/theme/2", isKid: false, switchedOff: true))
        #expect(ThemeMusicPolicy.volume == 0.25)
        #expect(ThemeMusicPolicy.fade == .seconds(1))
    }

    // MARK: Routing

    @Test func cardsOpenTheRightPage() {
        let filmRoute = TitleRoute.page(for: film())
        #expect(filmRoute == .title(TitleRoute(film())))
        let series = MediaSummary(id: "S", kind: .series, title: "S")
        #expect(TitleRoute.page(for: series) == .series(TitleRoute(series)))
        let season = MediaSummary(id: "s2", kind: .season, title: "Season 2", seriesID: "S", seasonNumber: 2)
        #expect(TitleRoute.page(for: season) == .series(TitleRoute(id: "S", seed: nil, seasonID: "s2")))
        #expect(TitleRoute.page(for: episode("e", 2, 3)) == .series(TitleRoute(id: "S", seed: nil, seasonID: "s2")))
        #expect(TitleRoute.page(for: MediaSummary(id: "c", kind: .clip, title: "C")) == nil)
    }

    @Test func badgesFromTheFirstVersion() {
        let video = MediaStream(id: "v", kind: .video, colourTransfer: "smpte2084", dolbyVisionProfile: 8)
        let version = MediaVersion(id: "m", videoResolution: "4k", parts: [MediaPart(id: "p", key: nil, streams: [video])])
        let detail = MediaDetail(summary: film(), versions: [version])
        #expect(TitleFacts.badges(detail) == [.format("4K"), .format("Dolby Vision")])
        let hdr = MediaStream(id: "v", kind: .video, colourTransfer: "smpte2084")
        let hd = MediaVersion(id: "m", videoResolution: "1080", parts: [MediaPart(id: "p", key: nil, streams: [hdr])])
        #expect(TitleFacts.badges(MediaDetail(summary: film(), versions: [hd])) == [.format("HD"), .format("HDR10")])
        #expect(TitleFacts.badges(nil).isEmpty)
    }
}
