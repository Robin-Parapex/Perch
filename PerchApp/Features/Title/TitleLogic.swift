import Foundation
import PerchCore
import PerchDesign

/// Where a title or series page opens from (WP-11): the title's id and what the opener already knows, so the first
/// frame shows its name and art before the detail arrives. A season card names its season.
struct TitleRoute: Hashable {
    let id: String
    let seed: MediaSummary?
    var seasonID: String?

    init(_ item: MediaSummary, seasonID: String? = nil) {
        id = item.id
        seed = item
        self.seasonID = seasonID
    }

    init(id: String, seed: MediaSummary? = nil, seasonID: String? = nil) {
        self.id = id
        self.seed = seed
        self.seasonID = seasonID
    }

    /// The page a Home card or grid poster opens: a film's title page, a series' page (a season opens its series on
    /// that season, an episode opens its series). Nil for anything else.
    static func page(for item: MediaSummary) -> ShellRoute? {
        switch item.kind {
        case .film: return .title(TitleRoute(item))
        case .series: return .series(TitleRoute(item))
        case .season:
            guard let series = item.seriesID else { return nil }
            return .series(TitleRoute(id: series, seed: nil, seasonID: item.id))
        case .episode:
            guard let series = item.seriesID else { return nil }
            return .series(TitleRoute(id: series, seed: nil, seasonID: item.seasonID))
        default: return nil
        }
    }
}

/// The film page's primary button (SPEC 5): Play when not started, Resume with the time left when started,
/// Play again when watched.
enum FilmPrimaryAction: Equatable {
    case play
    case resume(remainingMs: Int?)
    case playAgain

    init(_ item: MediaSummary) {
        if item.isInProgress {
            self = .resume(remainingMs: item.remainingMs)
        } else if item.isWatched {
            self = .playAgain
        } else {
            self = .play
        }
    }

    var title: String {
        switch self {
        case .play: TitleStrings.play
        case .resume: TitleStrings.resume
        case .playAgain: TitleStrings.playAgain
        }
    }

    var detail: String? {
        if case .resume(let remaining?) = self { return HomeStrings.timeLeft(ms: remaining) }
        return nil
    }

    /// Nil resumes from the saved point; 0 starts over.
    var startMs: Int? {
        if case .resume = self { return nil }
        return 0
    }
}

/// The series page's primary button (SPEC 4 "Play next always does the right thing"): the episode it plays and how.
struct SeriesNext: Equatable {
    enum Mode: Equatable {
        /// Nothing watched yet: the first episode.
        case start
        /// The episode after the last one watched.
        case next
        /// An episode left part way, watched more recently than anything finished.
        case resume
        /// Everything watched: from the first episode again.
        case playAgain
    }

    let episode: MediaSummary
    let mode: Mode

    var title: String {
        switch mode {
        case .start: TitleStrings.play
        case .next: TitleStrings.playNext
        case .resume: TitleStrings.resume
        case .playAgain: TitleStrings.playAgain
        }
    }

    var detail: String? { HomeStrings.episodeCode(episode) }

    /// Nil resumes from the saved point; 0 starts over.
    var startMs: Int? { mode == .resume ? nil : 0 }

    /// Order: season then episode. Specials (season 0) never count unless the series has nothing else (as
    /// `PlexLibrary.nextEpisode`, after Dusk, MIT). The latest viewing decides between an episode in progress and the
    /// one after the last finished (Plex's On deck rule).
    static func choose(in episodes: [MediaSummary]) -> SeriesNext? {
        let all = episodes.filter { $0.kind == .episode }
        let regular = all.filter { ($0.seasonNumber ?? 1) > 0 }
        let pool = (regular.isEmpty ? all : regular).sorted { order($0) < order($1) }
        guard let first = pool.first else { return nil }
        func latest(_ items: [MediaSummary]) -> MediaSummary? {
            items.max { lhs, rhs in
                let l = lhs.lastViewedAt ?? .distantPast
                let r = rhs.lastViewedAt ?? .distantPast
                return l == r ? order(lhs) < order(rhs) : l < r
            }
        }
        let inProgress = latest(pool.filter(\.isInProgress))
        let lastWatched = latest(pool.filter(\.isWatched))
        if let inProgress {
            let started = inProgress.lastViewedAt ?? .distantPast
            if lastWatched == nil || started >= (lastWatched?.lastViewedAt ?? .distantPast) {
                return SeriesNext(episode: inProgress, mode: .resume)
            }
        }
        guard let lastWatched, let index = pool.firstIndex(of: lastWatched) else {
            return SeriesNext(episode: first, mode: .start)
        }
        let candidate = pool[(index + 1)...].first { !$0.isWatched } ?? pool.first { !$0.isWatched }
        guard let candidate else { return SeriesNext(episode: first, mode: .playAgain) }
        return SeriesNext(episode: candidate, mode: candidate.isInProgress ? .resume : .next)
    }

    private static func order(_ item: MediaSummary) -> (Int, Int) {
        (item.seasonNumber ?? 1, item.episodeNumber ?? 0)
    }
}

/// Theme tunes on title pages (SPEC 5): soft, faded in and out, never for a kid's profile (no setting yet; WP-18
/// adds one). The token is only ever in the asset's headers.
enum ThemeMusicPolicy {
    static let volume: Float = 0.25
    static let fade: Duration = .seconds(1)

    static func plays(themePath: String?, isKid: Bool, switchedOff: Bool = false) -> Bool {
        guard let themePath, !themePath.isEmpty else { return false }
        return !isKid && !switchedOff
    }
}

/// What the hero's line and badges say: year, certificate, runtime or seasons, genre; 4K/HD and the dynamic range.
enum TitleFacts {
    static func metadata(_ detail: MediaDetail?, seed: MediaSummary) -> String {
        let summary = detail?.summary ?? seed
        let genre = detail?.genres.first
        switch summary.kind {
        case .series:
            let seasons = detail?.childCount.map(TitleStrings.seasonCount)
            return HomeStrings.joined([summary.year.map(String.init), summary.certificate, seasons, genre])
        default:
            return HomeStrings.joined([
                summary.year.map(String.init), summary.certificate, summary.durationMs.map(HomeStrings.duration), genre,
            ])
        }
    }

    static func badges(_ detail: MediaDetail?) -> [Pill.Kind] {
        guard let version = detail?.versions.first else { return [] }
        var badges: [Pill.Kind] = []
        switch version.videoResolution?.lowercased() {
        case "4k": badges.append(.format("4K"))
        case "1080", "720", "1080p", "720p": badges.append(.format("HD"))
        default: break
        }
        let video = version.parts.first?.streams.first { $0.kind == .video }
        if video?.dolbyVisionPresent == true || video?.dolbyVisionProfile != nil {
            badges.append(.format("Dolby Vision"))
        } else if video?.colourTransfer == "smpte2084" {
            badges.append(.format("HDR10"))
        } else if video?.colourTransfer == "arib-std-b67" {
            badges.append(.format("HLG"))
        }
        return badges
    }
}

/// Every string the title and series pages show, in sentence case (GLOSSARY).
enum TitleStrings {
    static let play = "Play"
    static let resume = "Resume"
    static let playAgain = "Play again"
    static let playNext = "Play next"
    static let fromStart = "Play from the start"
    static let markWatched = "Mark watched"
    static let markUnwatched = "Mark unwatched"
    static let more = "More"
    static let cast = "Cast"
    static let episodes = "Episodes"
    static let specials = "Specials"
    static let goToSeries = "Go to series"
    static let details = "Details"
    static let unavailableTitle = "Not available on this profile"
    static let unavailableMessage = "Ask a parent if you'd like to watch this."
    static let failedTitle = "Couldn't open this title"
    static let failedMessage = "Check your media server is on, then try again."
    static let tryAgain = "Try again"
    static let noEpisodes = "No episodes yet"

    static func seasonTitle(_ number: Int) -> String { number == 0 ? specials : "Season \(number)" }
    static func seasonCount(_ count: Int) -> String { count == 1 ? "1 season" : "\(count) seasons" }

    /// "3. Salt and Signal".
    static func episodeTitle(_ episode: MediaSummary) -> String {
        episode.episodeNumber.map { "\($0). \(episode.title)" } ?? episode.title
    }

    /// "40 min left" when started, else the runtime.
    static func episodeSubtitle(_ episode: MediaSummary) -> String? {
        if episode.isInProgress, let left = episode.remainingMs { return HomeStrings.timeLeft(ms: left) }
        return episode.durationMs.map(HomeStrings.duration)
    }
}
