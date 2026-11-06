#if DEBUG
import Foundation

/// DEBUG-only browse data for the fake household (WP-10): 28 films in section 1, 13 series in section 2, three
/// collections, and the browse endpoints a Films or Series grid calls (`/all` with sort, filters, content rating
/// and paging; `firstCharacter`; the filter value lists; collections and their children). Invented titles. A
/// restricted (little_kid) user sees only U titles everywhere, as Plex enforces for a restricted Home user.
/// Home's hubs are separate and unchanged.
enum FakeLibraryCatalogue {
    struct Title {
        let id: Int
        let section: Int
        let title: String
        let year: Int
        let rating: String?
        let genres: [Int]
        let resolution: String
        let watched: Bool
        let order: Int

        var sortTitle: String {
            for prefix in ["The ", "A "] where title.hasPrefix(prefix) { return String(title.dropFirst(prefix.count)) }
            return title
        }

        var audienceRating: Double { Double((id * 37) % 50) / 10 + 5 }
    }

    struct Collection {
        let id: Int
        let section: Int
        let title: String
        let members: [Int]
    }

    static let genres: [(Int, String)] = [
        (101, "Drama"), (102, "Comedy"), (103, "Animation"), (104, "Thriller"), (105, "Family"),
        (106, "Science fiction"), (107, "Documentary"),
    ]
    static let resolutions: [(String, String)] = [("4k", "4K"), ("1080", "1080p"), ("sd", "SD")]

    private static func film(_ id: Int, _ title: String, _ year: Int, _ rating: String?, _ genres: [Int], _ resolution: String, watched: Bool = false) -> Title {
        Title(id: id, section: 1, title: title, year: year, rating: rating, genres: genres, resolution: resolution, watched: watched, order: id)
    }

    private static func show(_ id: Int, _ title: String, _ year: Int, _ rating: String?, _ genres: [Int], _ resolution: String, watched: Bool = false) -> Title {
        Title(id: id, section: 2, title: title, year: year, rating: rating, genres: genres, resolution: resolution, watched: watched, order: id)
    }

    static let titles: [Title] = [
        film(1001, "Harbour Lights", 2019, "PG", [101, 105], "4k"),
        film(1002, "The Quiet Orchard", 2023, "PG", [101], "1080"),
        film(1003, "Paper Boats", 2024, "PG", [105, 103], "1080"),
        film(1004, "9 Lives of Oscar", 2016, "U", [103, 105], "1080"),
        film(1005, "Atlas of Small Things", 2021, "U", [107], "4k", watched: true),
        film(1006, "Brass Moon", 2018, "12", [106], "4k"),
        film(1007, "Copper Coast", 2009, "15", [104], "1080", watched: true),
        film(1008, "Dovetail", 1998, "PG", [102], "sd"),
        film(1009, "Echo Valley", 2015, "18", [104], "1080"),
        film(1010, "Fable of the Fox", 2012, "U", [103, 105], "1080", watched: true),
        film(1011, "Glasshouse", 2020, "15", [101, 104], "4k"),
        film(1012, "The Hollow Road", 2004, "12", [101], "sd"),
        film(1013, "Ink and Iron", 2022, "12", [106], "4k"),
        film(1014, "Juniper Lane", 1995, "PG", [102, 105], "sd", watched: true),
        film(1015, "Kite Season", 2017, "U", [105], "1080"),
        film(1016, "Low Tide", 2011, "15", [104], "1080"),
        film(1017, "Marigold Station", 2023, "PG", [102], "4k"),
        film(1018, "Midnight Ferry", 2001, "18", [104], "sd"),
        film(1019, "Northern Static", 2019, "12", [106, 104], "1080"),
        film(1020, "Otter Bay", 2024, "U", [103, 105], "4k"),
        film(1021, "Pebble and Pine", 2010, "PG", [105], "1080", watched: true),
        film(1022, "Quarry Lights", 1992, "15", [101], "sd"),
        film(1023, "River of Glass", 2014, nil, [107], "1080"),
        film(1024, "Salt Road", 2006, "12", [101], "1080"),
        film(1025, "Tin Soldiers", 1999, "PG", [102, 105], "sd"),
        film(1026, "Under the Pier", 2021, "18", [104], "4k"),
        film(1027, "Velvet Hour", 2013, "15", [101], "1080"),
        film(1028, "Winter Kites", 2008, "U", [105, 103], "1080"),
        show(2000, "The Lantern Keepers", 2024, "TV-14", [101], "4k"),
        show(3000, "Cold Harbour Files", 2022, "TV-14", [104], "1080"),
        show(2201, "Apple Tree Club", 2020, "U", [105, 103], "1080"),
        show(2202, "Bright Harbour", 2018, "PG", [102], "1080"),
        show(2203, "Deep Field", 2021, "12", [107], "4k"),
        show(2204, "Fogbound", 2016, "15", [104], "1080"),
        show(2205, "Gull Island", 2019, "U", [103], "1080", watched: true),
        show(2206, "Night Shift Diaries", 2015, "18", [101], "sd"),
        show(2207, "Puffin Patrol", 2023, "U", [105, 103], "4k"),
        show(2208, "24 Hours in Harbour", 2012, "12", [107], "sd"),
        show(2209, "Signal Hill", 2017, "15", [106], "1080"),
        show(2210, "Tidal", 2010, "PG", [107], "sd"),
        show(2211, "Wild Coast", 2022, "U", [107, 105], "4k"),
    ]

    static let collections: [Collection] = [
        Collection(id: 9001, section: 1, title: "Harbour stories", members: [1001, 1007, 1016, 1018, 1024]),
        Collection(id: 9002, section: 1, title: "Family nights", members: [1003, 1010, 1015, 1020, 1028, 1011]),
        Collection(id: 9003, section: 2, title: "Island life", members: [2205, 2207, 2204]),
    ]

    /// What a little_kid restriction admits (U-level certificates only; unrated hidden).
    static func kidAllows(_ rating: String?) -> Bool {
        guard let rating else { return false }
        return ["U", "G", "TV-Y", "TV-G"].contains(rating.uppercased())
    }

    // MARK: Answers

    /// Nil when the path is not a browse path.
    static func answer(path: String, items: [URLQueryItem], headers: [String: String], restricted: Bool) -> Any? {
        let parts = path.split(separator: "/").map(String.init)
        func visible(_ title: Title) -> Bool { !restricted || kidAllows(title.rating) }
        if path == "/hubs/search" { return search(items: items, restricted: restricted) }
        if parts.count == 4, parts[0] == "library", parts[1] == "sections", let section = Int(parts[2]) {
            let inSection = titles.filter { $0.section == section && visible($0) }
            switch parts[3] {
            case "all":
                let sorted = sort(filter(inSection, items), items.value("sort"))
                let start = Int(items.value("X-Plex-Container-Start") ?? headers["X-Plex-Container-Start"] ?? "") ?? 0
                let size = Int(items.value("X-Plex-Container-Size") ?? headers["X-Plex-Container-Size"] ?? "") ?? 50
                let page = Array(sorted.dropFirst(start).prefix(max(0, size)))
                return container(["size": page.count, "totalSize": sorted.count, "offset": start, "Metadata": page.map(metadata)])
            case "firstCharacter":
                let filtered = sort(filter(inSection, items), "titleSort")
                var buckets: [(String, Int)] = []
                for title in filtered {
                    let first = title.sortTitle.first.map { $0.isLetter ? String($0).uppercased() : "#" } ?? "#"
                    if let last = buckets.last, last.0 == first {
                        buckets[buckets.count - 1].1 += 1
                    } else {
                        buckets.append((first, 1))
                    }
                }
                return container(["size": buckets.count, "Directory": buckets.map { ["key": $0.0, "title": $0.0, "size": $0.1] }])
            case "genre":
                let used = Set(inSection.flatMap(\.genres))
                return directories(genres.filter { used.contains($0.0) }.map { (String($0.0), $0.1) })
            case "decade":
                let decades = Set(inSection.map { $0.year / 10 * 10 }).sorted(by: >)
                return directories(decades.map { (String($0), "\($0)s") })
            case "resolution":
                let used = Set(inSection.map(\.resolution))
                return directories(resolutions.filter { used.contains($0.0) })
            case "contentRating":
                let ratings = Set(inSection.compactMap(\.rating)).sorted()
                return directories(ratings.map { ($0, $0) })
            case "collections":
                let allowed = items.value("contentRating").map { Set($0.split(separator: ",").map(String.init)) }
                let rows = collections.filter { $0.section == section }.compactMap { collection -> [String: Any]? in
                    let members = members(of: collection, visible: visible, allowed: allowed)
                    guard !members.isEmpty else { return nil }
                    var row: [String: Any] = [
                        "ratingKey": String(collection.id), "key": "/library/collections/\(collection.id)/children",
                        "type": "collection", "title": collection.title, "childCount": members.count,
                        "thumb": "/library/metadata/\(collection.id)/thumb/1",
                    ]
                    if collection.id == 9002 { row["summary"] = "Films for the whole family, for a slow weekend night." }
                    return row
                }
                return container(["size": rows.count, "Metadata": rows])
            default: return nil
            }
        }
        if parts.count == 4, parts[0] == "library", parts[1] == "collections", parts[3] == "children",
            let id = Int(parts[2]), let collection = collections.first(where: { $0.id == id })
        {
            let allowed = items.value("contentRating").map { Set($0.split(separator: ",").map(String.init)) }
            let members = members(of: collection, visible: visible, allowed: allowed)
            return container(["size": members.count, "totalSize": members.count, "Metadata": members.map(metadata)])
        }
        return nil
    }

    /// `/hubs/search` (WP-12): case-insensitive substring match on titles (an episode by its own title), hubs for
    /// films, series, episodes and collections, honouring `contentRating=` and `limit`. A restricted user sees U
    /// titles only, unless `-PerchFakeSearchIgnoresRestriction` makes the server leak everything (so a test proves the
    /// app's own guard). Collections are hidden from a restricted user.
    static func search(items: [URLQueryItem], restricted: Bool) -> [String: Any] {
        let needle = (items.value("query") ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let limit = Int(items.value("limit") ?? "") ?? 10
        let leaks = ProcessInfo.processInfo.arguments.contains("-PerchFakeSearchIgnoresRestriction")
        let allowed = items.value("contentRating").map { Set($0.split(separator: ",").map(String.init)) }
        func admitted(_ rating: String?) -> Bool {
            if restricted && !leaks && !kidAllows(rating) { return false }
            if let allowed, !(rating.map(allowed.contains) ?? false) { return false }
            return true
        }
        func matches(_ text: String) -> Bool { !needle.isEmpty && text.lowercased().contains(needle) }
        let found = titles.filter { matches($0.title) && admitted($0.rating) }
        let films = found.filter { $0.section == 1 }.prefix(limit).map(metadata)
        let shows = found.filter { $0.section == 2 }.prefix(limit).map(metadata)
        var episodes: [[String: Any]] = []
        for series in titles where series.section == 2 && admitted(series.rating) {
            for episode in FakeTitleCatalogue.episodes(of: series) where matches(episode.title) {
                episodes.append(FakeTitleCatalogue.leaf(episode, series: series))
            }
        }
        let collectionRows: [[String: Any]] =
            restricted && !leaks
            ? []
            : collections.filter { matches($0.title) && allowed == nil }.map { collection in
                [
                    "ratingKey": String(collection.id), "key": "/library/collections/\(collection.id)/children",
                    "type": "collection", "subtype": collection.section == 1 ? "movie" : "show",
                    "librarySectionID": collection.section, "title": collection.title,
                    "childCount": collection.members.count, "thumb": "/library/metadata/\(collection.id)/thumb/1",
                ]
            }
        func hub(_ type: String, _ title: String, metadata rows: [[String: Any]], key: String = "Metadata") -> [String: Any] {
            ["type": type, "hubIdentifier": type, "title": title, "size": rows.count, key: rows]
        }
        let hubs = [
            hub("movie", "Movies", metadata: Array(films)), hub("show", "Shows", metadata: Array(shows)),
            hub("episode", "Episodes", metadata: Array(episodes.prefix(limit))),
            hub("collection", "Collections", metadata: collectionRows, key: "Directory"),
            hub("actor", "People", metadata: []),
        ]
        return container(["size": hubs.count, "Hub": hubs])
    }

    private static func members(of collection: Collection, visible: (Title) -> Bool, allowed: Set<String>?) -> [Title] {
        collection.members.compactMap { id in titles.first { $0.id == id } }
            .filter { title in visible(title) && (allowed.map { set in title.rating.map(set.contains) ?? false } ?? true) }
    }

    static func filter(_ titles: [Title], _ items: [URLQueryItem]) -> [Title] {
        func list(_ name: String) -> Set<String>? {
            items.value(name).map { Set($0.split(separator: ",").map(String.init)) }
        }
        return titles.filter { title in
            if let genres = list("genre"), !title.genres.contains(where: { genres.contains(String($0)) }) { return false }
            if let decade = items.value("decade").flatMap(Int.init), title.year / 10 * 10 != decade { return false }
            if let resolution = items.value("resolution"), title.resolution != resolution { return false }
            if items.value("unwatched") == "1", title.watched { return false }
            if let collection = items.value("collection").flatMap(Int.init),
                !(collections.first { $0.id == collection }?.members.contains(title.id) ?? false)
            {
                return false
            }
            if let ratings = list("contentRating"), !(title.rating.map(ratings.contains) ?? false) { return false }
            if let excluded = list("contentRating!"), let rating = title.rating, excluded.contains(rating) { return false }
            return true
        }
    }

    static func sort(_ titles: [Title], _ sort: String?) -> [Title] {
        switch sort {
        case "titleSort", "titleSort:asc":
            titles.sorted { $0.sortTitle.localizedCaseInsensitiveCompare($1.sortTitle) == .orderedAscending }
        case "year:desc": titles.sorted { ($0.year, $1.id) > ($1.year, $0.id) }
        case "rating:desc": titles.sorted { ($0.audienceRating, $1.id) > ($1.audienceRating, $0.id) }
        default: titles.sorted { $0.order > $1.order }  // addedAt:desc: the higher id is the newer
        }
    }

    static func metadata(_ title: Title) -> [String: Any] {
        var row: [String: Any] = [
            "ratingKey": String(title.id), "key": "/library/metadata/\(title.id)",
            "type": title.section == 1 ? "movie" : "show", "title": title.title, "titleSort": title.sortTitle,
            "year": title.year, "thumb": "/library/metadata/\(title.id)/thumb/1",
            "art": "/library/metadata/\(title.id)/art/1", "addedAt": 1_780_000_000 + title.order * 3600,
            "viewCount": title.watched ? 1 : 0, "audienceRating": title.audienceRating,
            "summary": "An invented title for the fake household.",
        ]
        if let rating = title.rating { row["contentRating"] = rating }
        if title.section == 1 {
            row["duration"] = 6_000_000
            if title.id == 1001 { row["viewOffset"] = 2_400_000; row["duration"] = 7_200_000 }
        } else {
            row["leafCount"] = 6
            row["viewedLeafCount"] = title.watched ? 6 : 0
        }
        return row
    }

    private static func container(_ body: [String: Any]) -> [String: Any] { ["MediaContainer": body] }

    private static func directories(_ values: [(String, String)]) -> [String: Any] {
        container(["size": values.count, "Directory": values.map { ["key": $0.0, "title": $0.1] }])
    }
}

extension [URLQueryItem] {
    fileprivate func value(_ name: String) -> String? { first { $0.name == name }?.value }
}
#endif
