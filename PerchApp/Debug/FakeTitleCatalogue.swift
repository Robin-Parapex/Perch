#if DEBUG
import Foundation

/// DEBUG-only title and series detail for the fake household (WP-11): a detail per catalogue title with cast and,
/// for "The Lantern Keepers" (2000) and "9 Lives of Oscar" (1004), a theme; every series' episodes. Series 2000 has
/// two seasons: S1 E1 and E2 watched, E3 (2101) part watched and the latest viewing, E4 to E6 (2102, 2104, 2105, the
/// player's chain), and S2 E1 to E4 unwatched. Other series have one season of three episodes ("<series>1" to "3").
/// Every playable detail carries the same 4K Dolby Vision file, markers and chapters the player tests rely on.
enum FakeTitleCatalogue {
    struct Episode {
        let id: String
        let season: Int
        let number: Int
        let title: String
        let summary: String
        var viewCount = 0
        var viewOffset: Int?
        var lastViewedAt: Int?
    }

    static let lanternSeasons = ["2100": 1, "2200": 2]

    static let lanternEpisodes: [Episode] = [
        Episode(id: "2110", season: 1, number: 1, title: "Lamp Oil", summary: "Three strangers arrive on the island to keep the old light burning through one winter.", viewCount: 1, lastViewedAt: 1_789_000_000),
        Episode(id: "2111", season: 1, number: 2, title: "The Keeper's Log", summary: "An unfinished entry in the logbook hints at why the last keepers left in a hurry.", viewCount: 1, lastViewedAt: 1_789_500_000),
        Episode(id: "2101", season: 1, number: 3, title: "Salt and Signal", summary: "A storm cuts the island off from the mainland on the keepers' third night. Mara has to decide whether to trust the stranger who rowed in with the tide.", viewOffset: 20000, lastViewedAt: 1_790_000_500),
        Episode(id: "2102", season: 1, number: 4, title: "The Long Watch", summary: "Supplies run low and tempers run shorter as the fog settles in. A signal lamp starts flashing from a rock nobody has ever landed on."),
        Episode(id: "2104", season: 1, number: 5, title: "Slack Water", summary: "For one quiet hour the tide stands still and the keepers finally compare notes. What they find in the logbook changes how they see the lighthouse."),
        Episode(id: "2105", season: 1, number: 6, title: "First Light", summary: "At dawn the keepers row out to the rock and find it is not empty. The season finale asks what they owe the people the lamp was built to guide home."),
        Episode(id: "2121", season: 2, number: 1, title: "Spring Tide", summary: "A year on, a supply boat brings a letter none of the keepers expected to read."),
        Episode(id: "2122", season: 2, number: 2, title: "Fog Bell", summary: "The bell rings by itself at midnight, and Mara starts counting the seconds between."),
        Episode(id: "2123", season: 2, number: 3, title: "Driftwood", summary: "Wreckage on the shingle carries a name the island has tried hard to forget."),
        Episode(id: "2124", season: 2, number: 4, title: "The Return", summary: "The mainland finally sends someone across, and the keepers must decide what to tell them."),
    ]

    private static let people = [
        "Mara Quill", "Ted Rowe", "Ada Fenn", "Jonah Pike", "Iris Calder", "Owen Marsh", "Lena Hart", "Felix Dunn",
    ]
    private static let parts = ["The keeper", "The stranger", "The captain", "The botanist", "The child", "The narrator"]

    // MARK: Answers

    /// Nil when the key is not a catalogue title or a known episode.
    static func detail(ratingKey: String, ratingU: Bool) -> [String: Any]? {
        if let title = FakeLibraryCatalogue.titles.first(where: { String($0.id) == ratingKey }) {
            return container([title.section == 1 ? film(title) : show(title)])
        }
        guard let (series, episode) = episode(ratingKey) else { return nil }
        return container([episodeDetail(episode, series: series, ratingU: ratingU)])
    }

    /// `/library/metadata/<series>/allLeaves`; nil for anything that is not a series.
    static func allLeaves(seriesID: String) -> [String: Any]? {
        guard let series = FakeLibraryCatalogue.titles.first(where: { String($0.id) == seriesID && $0.section == 2 })
        else { return nil }
        let rows = episodes(of: series).map { leaf($0, series: series) }
        return ["MediaContainer": ["size": rows.count, "Metadata": rows]]
    }

    static func episodes(of series: FakeLibraryCatalogue.Title) -> [Episode] {
        if series.id == 2000 { return lanternEpisodes }
        return (1...3).map { number in
            Episode(
                id: "\(series.id)\(number)", season: 1, number: number, title: "Chapter \(number)",
                summary: "Episode \(number) of \(series.title), an invented series.",
                viewCount: series.watched ? 1 : 0)
        }
    }

    private static func episode(_ key: String) -> (FakeLibraryCatalogue.Title, Episode)? {
        for series in FakeLibraryCatalogue.titles where series.section == 2 {
            if let match = episodes(of: series).first(where: { $0.id == key }) { return (series, match) }
        }
        return nil
    }

    // MARK: Builders

    private static func seasonID(_ episode: Episode, series: FakeLibraryCatalogue.Title) -> String {
        series.id == 2000 ? (episode.season == 1 ? "2100" : "2200") : "\(series.id)0"
    }

    static func leaf(_ episode: Episode, series: FakeLibraryCatalogue.Title) -> [String: Any] {
        var row: [String: Any] = [
            "ratingKey": episode.id, "key": "/library/metadata/\(episode.id)", "type": "episode",
            "title": episode.title, "summary": episode.summary, "grandparentRatingKey": String(series.id),
            "grandparentTitle": series.title, "grandparentThumb": "/library/metadata/\(series.id)/thumb/1",
            "parentRatingKey": seasonID(episode, series: series), "parentIndex": episode.season,
            "parentTitle": "Season \(episode.season)", "index": episode.number, "duration": 60000,
            "viewCount": episode.viewCount, "thumb": "/library/metadata/\(episode.id)/thumb/1",
            "addedAt": 1_700_000_000 + Int(episode.id)! % 1000 * 100,
        ]
        if let rating = series.rating { row["contentRating"] = rating }
        if let offset = episode.viewOffset { row["viewOffset"] = offset }
        if let viewed = episode.lastViewedAt { row["lastViewedAt"] = viewed }
        return row
    }

    private static func episodeDetail(_ episode: Episode, series: FakeLibraryCatalogue.Title, ratingU: Bool) -> [String: Any] {
        var row = leaf(episode, series: series)
        // `-PerchFakeRatingU`: the episode is rated U, so a kid profile may play it (player UI tests).
        if series.id == 2000 { row["contentRating"] = ratingU ? "U" : "TV-14" }
        row["year"] = series.year
        return playable(row)
    }

    private static func film(_ title: FakeLibraryCatalogue.Title) -> [String: Any] {
        var row: [String: Any] = [
            "ratingKey": String(title.id), "key": "/library/metadata/\(title.id)", "type": "movie", "title": title.title,
            "year": title.year, "thumb": "/library/metadata/\(title.id)/thumb/1",
            "art": "/library/metadata/\(title.id)/art/1", "duration": 6_000_000, "viewCount": title.watched ? 1 : 0,
            "summary": synopsis(title), "studio": "Invented Pictures",
            "Genre": title.genres.compactMap { id in FakeLibraryCatalogue.genres.first { $0.0 == id }.map { ["tag": $0.1] } },
            "Role": roles(title.id),
        ]
        if let rating = title.rating { row["contentRating"] = rating }
        if title.id == 1001 {
            row["duration"] = 7_200_000
            row["viewOffset"] = 2_400_000
            row["lastViewedAt"] = 1_790_000_000
            row["Image"] = [["alt": "Harbour Lights", "type": "clearLogo", "url": "/library/metadata/1001/clearLogo/1"]]
        }
        if title.id == 1004 { row["theme"] = "/library/metadata/1004/theme/1700000000" }
        return playable(row, resolution: title.resolution, durationMs: row["duration"] as? Int)
    }

    private static func show(_ title: FakeLibraryCatalogue.Title) -> [String: Any] {
        let list = episodes(of: title)
        var row: [String: Any] = [
            "ratingKey": String(title.id), "key": "/library/metadata/\(title.id)/children", "type": "show",
            "title": title.title, "year": title.year, "thumb": "/library/metadata/\(title.id)/thumb/1",
            "art": "/library/metadata/\(title.id)/art/1", "summary": synopsis(title),
            "childCount": Set(list.map(\.season)).count, "leafCount": list.count,
            "viewedLeafCount": list.filter { $0.viewCount > 0 }.count,
            "Genre": title.genres.compactMap { id in FakeLibraryCatalogue.genres.first { $0.0 == id }.map { ["tag": $0.1] } },
            "Role": roles(title.id),
        ]
        if let rating = title.rating { row["contentRating"] = rating }
        if title.id == 2000 { row["theme"] = "/library/metadata/2000/theme/1700000000" }
        return row
    }

    private static func synopsis(_ title: FakeLibraryCatalogue.Title) -> String {
        switch title.id {
        case 1001:
            "A retired ferry captain returns to his home port for one last crossing. Along the way he reunites a divided town and a daughter who stopped writing years ago, and learns that the harbour he left has been waiting for him all along."
        case 2000:
            "Three strangers take on the old lighthouse on a storm-bound island for one winter. As the fog closes in and the lamp starts to fail, they learn the island keeps its own records, and that the last keepers never really left. A slow, wind-blown mystery about duty and the people we guide home."
        default:
            "\(title.title) is an invented title for the fake household. It stands in for a real synopsis of two sentences."
        }
    }

    /// Six people, rotated by the title; the first four have a portrait (a server path), the last two show initials.
    private static func roles(_ id: Int) -> [[String: Any]] {
        (0..<6).map { index in
            var role: [String: Any] = [
                "id": id * 10 + index, "tag": people[(id + index) % people.count], "role": parts[index],
            ]
            if index < 4 { role["thumb"] = "/library/metadata/\(id * 10 + index)/role/1" }
            return role
        }
    }

    /// The file, markers, chapters and trailer every playable fake title carries (the player plays the bundled clip).
    /// A film's file runs its full length; an episode's is the 60 s the player tests expect.
    private static func playable(_ row: [String: Any], resolution: String = "4k", durationMs: Int? = nil) -> [String: Any] {
        var row = row
        let uhd = resolution == "4k"
        var video: [String: Any] = [
            "id": 9001, "streamType": 1, "codec": "hevc", "bitDepth": 10, "frameRate": 23.976,
            "width": uhd ? 3840 : 1920, "height": uhd ? 2160 : 1080, "default": true, "selected": true,
        ]
        if uhd {
            video["colorTrc"] = "smpte2084"
            video["DOVIProfile"] = 8
            video["DOVIPresent"] = true
        }
        row["Media"] = [
            [
                "id": 7001, "duration": durationMs ?? 60000, "width": video["width"]!, "height": video["height"]!,
                "videoResolution": resolution, "container": "mkv", "videoCodec": "hevc", "audioCodec": "eac3",
                "Part": [
                    [
                        "id": 8001, "key": "/library/parts/8001/1/file.mkv", "duration": durationMs ?? 59500, "size": 4_123_456_789,
                        "container": "mkv", "accessible": true,
                        "Stream": [
                            video,
                            ["id": 9002, "streamType": 2, "codec": "eac3", "channels": 6, "languageCode": "eng", "default": true, "selected": true],
                            ["id": 9003, "streamType": 3, "codec": "srt", "format": "srt", "key": "/library/streams/9003", "languageCode": "eng", "title": "SDH"],
                        ],
                    ]
                ],
            ]
        ]
        row["Marker"] = [
            ["id": 501, "type": "intro", "startTimeOffset": 5000, "endTimeOffset": 15000],
            ["id": 503, "type": "credits", "startTimeOffset": 45000, "endTimeOffset": 60000, "final": true],
        ]
        row["Chapter"] = [
            ["id": 601, "index": 1, "startTimeOffset": 0, "endTimeOffset": 900_000, "tag": "Cold open"],
            ["id": 602, "index": 2, "startTimeOffset": 900_000, "endTimeOffset": 1_800_000, "tag": "The Signal"],
            ["id": 603, "index": 3, "startTimeOffset": 1_800_000, "endTimeOffset": 2_700_000, "tag": "Dawn"],
        ]
        row["Extras"] = ["size": 1, "Metadata": [["ratingKey": "2901", "type": "clip", "subtype": "trailer", "title": "Season 1 Trailer", "duration": 90000]]]
        return row
    }

    private static func container(_ rows: [[String: Any]]) -> [String: Any] {
        ["MediaContainer": ["size": rows.count, "Metadata": rows]]
    }
}
#endif
