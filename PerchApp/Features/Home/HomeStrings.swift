import Foundation
import PerchCore

/// Every string Home shows (docs/design/wp-09-home.md section 10). Sentence case, no backend names.
enum HomeStrings {
    static let continueWatching = "Continue watching"
    static let upNext = "Up next in your series"
    static let recentlyAdded = "Recently added"

    static let play = "Play"
    static let resume = "Resume"

    static let firstLaunch = "Getting your library ready"
    static let emptyTitle = "Nothing to watch yet"
    static let emptyMessage = "Films and series you add to your media server will show up here."
    static let checkAgain = "Check again"
    static let offlineCached = "Can't reach your media server. Showing what you had."
    static let offlineTitle = "Can't reach your media server"
    static let offlineMessage = "Check it's on and connected, then try again."
    static let tryAgain = "Try again"
    static let switchProfile = "Switch profile"
    static let runSetup = "Run setup again"
    static let askParent = "Ask a parent to change setup"

    static let series = "Series"
    static let almostDone = "Almost done"
    static let separator = " \u{00B7} "

    /// The title shown over a row; the provider's own title is used for any row Home does not know.
    static func rowTitle(_ row: MediaRow) -> String {
        switch row.id {
        case HomeRowID.continueWatching: continueWatching
        case HomeRowID.upNext: upNext
        case HomeRowID.recentlyAdded: recentlyAdded
        default: row.title
        }
    }

    /// "45 min", "1 h 52 min", "2 h". Rounded to the nearest minute.
    static func duration(ms: Int) -> String {
        let minutes = Int((Double(ms) / 60_000).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// "31 min left", "1 h 12 min left", "Almost done" under a minute.
    static func timeLeft(ms: Int) -> String {
        ms < 60_000 ? almostDone : duration(ms: ms) + " left"
    }

    /// "S2 E5", no leading zeros; nil without numbers.
    static func episodeCode(_ item: MediaSummary) -> String? {
        switch (item.seasonNumber, item.episodeNumber) {
        case (let season?, let episode?): "S\(season) E\(episode)"
        case (nil, let episode?): "E\(episode)"
        default: nil
        }
    }

    static func joined(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: separator)
    }

    // MARK: Hero

    /// Film "2024 · 1 h 52 min · 15"; series "Series · 2024 · 12"; episode "S2 E5 · Episode title · 31 min left"
    /// (the hero title already shows the series name).
    static func heroMetadata(_ item: MediaSummary) -> String {
        switch item.kind {
        case .episode:
            joined([episodeCode(item), item.title, item.remainingMs.map(timeLeft)])
        case .series:
            joined([series, item.year.map(String.init), item.certificate])
        default:
            joined([item.year.map(String.init), item.durationMs.map(duration), item.certificate])
        }
    }

    /// The text fallback for the logo: the series name for an episode.
    static func heroTitle(_ item: MediaSummary) -> String {
        item.kind == .episode ? (item.seriesTitle ?? item.title) : item.title
    }

    // MARK: Card captions (spec 3.2)

    static func caption(for item: MediaSummary, in rowID: String) -> (title: String, subtitle: String?) {
        switch rowID {
        case HomeRowID.continueWatching:
            let left = item.remainingMs.map(timeLeft)
            if item.kind == .episode {
                return (item.seriesTitle ?? item.title, joined([episodeCode(item), left]))
            }
            return (item.title, left)
        case HomeRowID.upNext:
            return (item.seriesTitle ?? item.title, episodeLine(item))
        default:
            switch item.kind {
            case .episode: return (item.seriesTitle ?? item.title, episodeLine(item))
            case .series: return (item.title, joined([series, item.year.map(String.init)]))
            default: return (item.title, item.year.map(String.init))
            }
        }
    }

    /// "S2 E5 Episode title"; the card truncates the title with an ellipsis.
    private static func episodeLine(_ item: MediaSummary) -> String {
        [episodeCode(item), item.title].compactMap { $0 }.joined(separator: " ")
    }
}

/// The three Plex row ids Home knows by name (PerchPlex `PlexHomeRows`).
enum HomeRowID {
    static let continueWatching = "plex.continueWatching"
    static let upNext = "plex.upNext"
    static let recentlyAdded = "plex.recentlyAdded"
}
