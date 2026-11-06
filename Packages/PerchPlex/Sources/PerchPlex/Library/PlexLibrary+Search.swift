import Foundation
import PerchCore

/// A collection found by search, with what a collection page needs to open it.
public struct PlexSearchCollection: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let thumbPath: String?
    public let artPath: String?
    public let summary: String?
    public let childCount: Int?
    /// The section the collection lives in; nil when the server did not say (the page cannot open then).
    public let sectionID: String?
    public let kind: PlexLibrarySection.Kind?

    public init(
        id: String, title: String, thumbPath: String? = nil, artPath: String? = nil, summary: String? = nil,
        childCount: Int? = nil, sectionID: String? = nil, kind: PlexLibrarySection.Kind? = nil
    ) {
        self.id = id
        self.title = title
        self.thumbPath = thumbPath
        self.artPath = artPath
        self.summary = summary
        self.childCount = childCount
        self.sectionID = sectionID
        self.kind = kind
    }
}

/// One search's library results, in the groups the Search screen shows (WP-12). People, music, photos and every
/// other hub are ignored for now.
public struct PlexSearchResults: Sendable, Equatable {
    public var films: [MediaSummary]
    public var series: [MediaSummary]
    public var episodes: [MediaSummary]
    public var collections: [PlexSearchCollection]

    public init(
        films: [MediaSummary] = [], series: [MediaSummary] = [], episodes: [MediaSummary] = [],
        collections: [PlexSearchCollection] = []
    ) {
        self.films = films
        self.series = series
        self.episodes = episodes
        self.collections = collections
    }

    public static let empty = PlexSearchResults()

    public var count: Int { films.count + series.count + episodes.count + collections.count }
    public var isEmpty: Bool { count == 0 }
}

extension PlexEndpoints {
    /// `GET /hubs/search?query=&limit=` (approach from python-plexapi's `PlexServer.search`). The token is the
    /// header, never a query item. `contentRatings` adds a `contentRating=` filter, sorted, for a server that honours
    /// it on search (the client guard runs either way). A literal "+" is sent as %2B so it is not read as a space.
    public func search(
        base: URL, token: String, query: String, limit: Int, contentRatings: Set<String>? = nil
    ) -> URLRequest {
        var items: [URLQueryItem] = [
            .init(name: "query", value: query),
            .init(name: "limit", value: String(max(1, limit))),
            .init(name: "includeCollections", value: "1"),
            .init(name: "includeExternalMedia", value: "0"),
        ]
        if let contentRatings, !contentRatings.isEmpty {
            items.append(.init(name: "contentRating", value: contentRatings.sorted().joined(separator: ",")))
        }
        var request = libraryRequest(base: base, token: token, path: "/hubs/search", query: items)
        if let url = request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            request.url = components.url ?? url
        }
        return request
    }
}

extension PlexLibrary {
    /// Results a search row asks for per group.
    public static let searchLimit = 20

    /// The library's matches for `query`, grouped. A blank query asks for nothing; so does an empty rating set
    /// (it admits nothing). A non-nil set is also sent as a filter (see `PlexEndpoints.search`).
    public func search(
        query: String, limit: Int = PlexLibrary.searchLimit, contentRatings: Set<String>? = nil
    ) async throws -> PlexSearchResults {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        if let contentRatings, contentRatings.isEmpty { return .empty }
        let context = try await current()
        let container = try await fetch(
            context,
            endpoints.search(
                base: context.baseURL, token: context.token, query: trimmed, limit: limit,
                contentRatings: contentRatings))
        return PlexLibraryMapping.searchResults(container.hubs)
    }
}

extension PlexLibraryMapping {
    /// Films, series, episodes and collections from the search hubs, by hub type, each item also checked by its
    /// own type, in server order, without duplicates.
    static func searchResults(_ hubs: [PlexWireHub]) -> PlexSearchResults {
        var results = PlexSearchResults()
        var seen = Set<String>()
        func take(_ item: PlexWireMetadata, as kind: MediaKind) -> MediaSummary? {
            guard let summary = summary(item), summary.kind == kind, seen.insert("\(kind):\(summary.id)").inserted
            else { return nil }
            return summary
        }
        for hub in hubs {
            let rows = (hub.metadata ?? []) + (hub.directory ?? [])
            switch hub.type {
            case "movie": results.films += rows.compactMap { take($0, as: .film) }
            case "show": results.series += rows.compactMap { take($0, as: .series) }
            case "episode": results.episodes += rows.compactMap { take($0, as: .episode) }
            case "collection":
                results.collections += rows.compactMap { row in
                    guard let id = row.ratingKey, !id.isEmpty, row.type.map({ $0 == "collection" }) ?? true,
                        seen.insert("collection:\(id)").inserted
                    else { return nil }
                    let kind: PlexLibrarySection.Kind? =
                        switch row.subtype {
                        case "movie": .film
                        case "show": .series
                        default: nil
                        }
                    return PlexSearchCollection(
                        id: id, title: row.title ?? "", thumbPath: row.thumb, artPath: row.art,
                        summary: row.summary.flatMap { $0.isEmpty ? nil : $0 }, childCount: row.childCount,
                        sectionID: row.librarySectionID, kind: kind)
                }
            default: continue
            }
        }
        return results
    }
}
