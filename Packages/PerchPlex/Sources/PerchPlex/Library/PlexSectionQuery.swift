import Foundation
import PerchCore

/// How a section is sorted. Plex sort strings; `rating` is the audience score.
public enum PlexSectionSort: Sendable, Equatable {
    case recentlyAdded, title, year, rating
    case raw(String)

    public var value: String {
        switch self {
        case .recentlyAdded: "addedAt:desc"
        case .title: "titleSort"
        case .year: "year:desc"
        case .rating: "rating:desc"
        case .raw(let value): value
        }
    }
}

/// One browse of a section: kind, sort and filters. Value type, so a screen can keep it and a pager
/// can be rebuilt from it. Filter items are built sorted by name so URLs are stable.
public struct PlexSectionQuery: Sendable, Equatable {
    public var sectionID: String
    /// Films list movies (type 1), series list shows (type 2).
    public var kind: PlexLibrarySection.Kind
    public var sort: PlexSectionSort?
    public var genreIDs: [String]
    public var decade: Int?
    public var resolution: String?
    public var unwatched: Bool
    public var collectionID: String?
    /// Nil sends no content-rating filter. A set sends `contentRating=a,b,c`; an empty set admits
    /// nothing, so nothing is requested (fails closed).
    public var contentRatings: Set<String>?
    public var startOffset: Int

    public init(
        sectionID: String, kind: PlexLibrarySection.Kind, sort: PlexSectionSort? = nil,
        genreIDs: [String] = [], decade: Int? = nil, resolution: String? = nil,
        unwatched: Bool = false, collectionID: String? = nil, contentRatings: Set<String>? = nil,
        startOffset: Int = 0
    ) {
        self.sectionID = sectionID
        self.kind = kind
        self.sort = sort
        self.genreIDs = genreIDs
        self.decade = decade
        self.resolution = resolution
        self.unwatched = unwatched
        self.collectionID = collectionID
        self.contentRatings = contentRatings
        self.startOffset = max(0, startOffset)
    }

    /// True when the content-rating filter admits nothing.
    public var admitsNothing: Bool { contentRatings?.isEmpty == true }

    var typeValue: String { kind == .film ? "1" : "2" }

    /// The rating filter as one comma-separated item, sorted. Nil when there is no filter.
    var contentRatingItem: URLQueryItem? {
        guard let contentRatings, !contentRatings.isEmpty else { return nil }
        return .init(name: "contentRating", value: contentRatings.sorted().joined(separator: ","))
    }

    /// Type and filters, no sort and no paging (what firstCharacter shares with the item list).
    var filterItems: [URLQueryItem] {
        var items: [URLQueryItem] = [.init(name: "type", value: typeValue)]
        if !genreIDs.isEmpty { items.append(.init(name: "genre", value: genreIDs.sorted().joined(separator: ","))) }
        if let decade { items.append(.init(name: "decade", value: String(decade))) }
        if let resolution, !resolution.isEmpty { items.append(.init(name: "resolution", value: resolution)) }
        if unwatched { items.append(.init(name: "unwatched", value: "1")) }
        if let collectionID, !collectionID.isEmpty { items.append(.init(name: "collection", value: collectionID)) }
        if let contentRatingItem { items.append(contentRatingItem) }
        return items.sorted { $0.name < $1.name }
    }

    /// Filters plus sort, sorted by name.
    var itemsWithSort: [URLQueryItem] {
        var items = filterItems
        if let sort, !sort.value.isEmpty { items.append(.init(name: "sort", value: sort.value)) }
        return items.sorted { $0.name < $1.name }
    }
}

/// One first-letter bucket: "#" for titles that start with a non-letter.
public struct PlexLetterBucket: Sendable, Equatable {
    public let title: String
    public let size: Int
    public init(title: String, size: Int) {
        self.title = title
        self.size = size
    }
}

/// Offsets of each bucket's first item, in the server's order (cumulative sizes). A duplicate title
/// keeps its first offset.
public func letterOffsets(_ buckets: [PlexLetterBucket]) -> [String: Int] {
    var result: [String: Int] = [:]
    var running = 0
    for bucket in buckets {
        if result[bucket.title] == nil { result[bucket.title] = running }
        running += max(0, bucket.size)
    }
    return result
}

public enum PlexFilterKind: String, Sendable, Equatable {
    case genre, decade, resolution, contentRating
}

public struct PlexFilterValue: Sendable, Equatable {
    public let key: String
    public let title: String
    public init(key: String, title: String) {
        self.key = key
        self.title = title
    }
}

public struct PlexCollection: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let thumbPath: String?
    public let childCount: Int?
    public init(id: String, title: String, thumbPath: String?, childCount: Int?) {
        self.id = id
        self.title = title
        self.thumbPath = thumbPath
        self.childCount = childCount
    }
}

extension PlexEndpoints {
    public func sectionItems(
        base: URL, token: String, query: PlexSectionQuery, start: Int, size: Int
    ) -> URLRequest {
        libraryRequest(
            base: base, token: token, path: "/library/sections/\(segment(query.sectionID))/all",
            query: query.itemsWithSort + paging(start: start, size: size))
    }

    public func firstCharacter(base: URL, token: String, query: PlexSectionQuery) -> URLRequest {
        libraryRequest(
            base: base, token: token,
            path: "/library/sections/\(segment(query.sectionID))/firstCharacter",
            query: query.filterItems)
    }

    public func filterValues(
        base: URL, token: String, sectionID: String, kind: PlexFilterKind
    ) -> URLRequest {
        libraryRequest(
            base: base, token: token,
            path: "/library/sections/\(segment(sectionID))/\(kind.rawValue)")
    }

    /// No `type` item: on the live server (6 Nov 2026, WP-10 probe) `collections?type=1` returned the section's
    /// films instead of its collections.
    public func sectionCollections(base: URL, token: String, query: PlexSectionQuery) -> URLRequest {
        var items: [URLQueryItem] = []
        if let rating = query.contentRatingItem { items.append(rating) }
        return libraryRequest(
            base: base, token: token,
            path: "/library/sections/\(segment(query.sectionID))/collections", query: items)
    }

    public func collectionChildren(
        base: URL, token: String, collectionID: String, start: Int, size: Int
    ) -> URLRequest {
        libraryRequest(
            base: base, token: token,
            path: "/library/collections/\(segment(collectionID))/children",
            query: paging(start: start, size: size))
    }
}
