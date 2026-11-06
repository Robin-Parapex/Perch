import Foundation
import PerchCore

/// Library browsing for the Films and Series grids. Approach from Swiftfin and python-plexapi;
/// each path is to be confirmed on the live server.
extension PlexLibrary {
    /// A pager over the query, from its `startOffset`, bound to the generation current now.
    public func pager(query: PlexSectionQuery) async -> PlexSectionPager {
        PlexSectionPager(
            query: query, generation: await contextSource.currentGeneration(),
            contextSource: contextSource, transport: transport, endpoints: endpoints)
    }

    /// Letter buckets in server order. Nothing is requested when the rating filter admits nothing.
    public func firstCharacters(query: PlexSectionQuery) async throws -> [PlexLetterBucket] {
        guard !query.admitsNothing else { return [] }
        let context = try await current()
        let container = try await fetch(
            context, endpoints.firstCharacter(base: context.baseURL, token: context.token, query: query))
        return PlexLibraryMapping.letterBuckets(container.directory ?? [])
    }

    public func filterValues(sectionID: String, kind: PlexFilterKind) async throws -> [PlexFilterValue] {
        let context = try await current()
        let container = try await fetch(
            context,
            endpoints.filterValues(
                base: context.baseURL, token: context.token, sectionID: sectionID, kind: kind))
        return PlexLibraryMapping.filterValues(container.directory ?? [])
    }

    public func collections(query: PlexSectionQuery) async throws -> [PlexCollection] {
        guard !query.admitsNothing else { return [] }
        let context = try await current()
        let container = try await fetch(
            context,
            endpoints.sectionCollections(base: context.baseURL, token: context.token, query: query))
        return PlexLibraryMapping.collections(container.metadata ?? [])
    }

    /// The collection's members, every page (200 a request). The server may ignore a content-rating filter on this
    /// endpoint, so the set is applied here as well, by exact match on the item's certificate (decoded forms).
    public func collectionItems(
        collectionID: String, query: PlexSectionQuery
    ) async throws -> [MediaSummary] {
        guard !query.admitsNothing else { return [] }
        let context = try await current()
        var items: [MediaSummary] = []
        var start = query.startOffset
        // A bound so a server that misreports its total cannot loop forever (50 x 200 titles).
        for _ in 0..<50 {
            let container = try await fetch(
                context,
                endpoints.collectionChildren(
                    base: context.baseURL, token: context.token, collectionID: collectionID,
                    start: start, size: Self.collectionPageSize))
            let returned = container.rowCount
            items += PlexLibraryMapping.summaries(container.items)
            start += returned
            if returned < Self.collectionPageSize { break }
            if let total = container.totalCount, start >= total { break }
        }
        guard let allowed = query.contentRatings.map({ Set($0.map(Self.decodedRating)) }) else { return items }
        return items.filter { item in item.certificate.map { allowed.contains(Self.decodedRating($0)) } ?? false }
    }

    static let collectionPageSize = 200

    /// The server's total for a query, asking for one row. `extraItems` adds raw query items, so a live check
    /// can try syntax the query type does not model (for example `contentRating!=` exclusion). Diagnostics only.
    public func sectionTotal(query: PlexSectionQuery, extraItems: [URLQueryItem] = []) async throws -> Int? {
        guard !query.admitsNothing else { return 0 }
        let context = try await current()
        var request = endpoints.sectionItems(
            base: context.baseURL, token: context.token, query: query, start: 0, size: 1)
        if !extraItems.isEmpty, let url = request.url,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        {
            components.queryItems = (components.queryItems ?? []) + extraItems
            request.url = components.url
        }
        let container = try await fetch(context, request)
        return container.totalCount
    }

    /// How many children a collection returns from the server, with or without a content-rating filter on the
    /// request and before any filtering here. Diagnostics only (does the endpoint honour the filter?).
    public func collectionChildCount(collectionID: String, contentRatings: Set<String>?) async throws -> Int {
        let context = try await current()
        var request = endpoints.collectionChildren(
            base: context.baseURL, token: context.token, collectionID: collectionID, start: 0, size: 500)
        if let contentRatings, !contentRatings.isEmpty, let url = request.url,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        {
            components.queryItems =
                (components.queryItems ?? [])
                + [.init(name: "contentRating", value: contentRatings.sorted().joined(separator: ","))]
            request.url = components.url
        }
        let container = try await fetch(context, request)
        return container.totalCount ?? container.rowCount
    }

    /// The section's content-rating values that the ceiling admits, decoded (see `admittedContentRatings(values:)`).
    public func admittedContentRatings(
        sectionID: String, ceiling: RatingCeiling
    ) async throws -> Set<String> {
        let values = try await filterValues(sectionID: sectionID, kind: .contentRating)
        return Self.admittedContentRatings(values: values, ceiling: ceiling)
    }

    /// Pure part. The live server lists prefixed ratings with a percent-encoded key (`gb%2FPG`, title `gb/PG`), so
    /// each key is decoded before it is classified and before it is sent (the query item encodes it once). A key
    /// that still does not parse is classified by its title. Unknown and NR values count as 15
    /// (`RatingCeiling.forTitle`), so a ceiling below 15 never admits them.
    public static func admittedContentRatings(
        values: [PlexFilterValue], ceiling: RatingCeiling
    ) -> Set<String> {
        Set(
            values.compactMap { value in
                let key = decodedRating(value.key)
                let rating = RatingCeiling(certificate: key)
                    ?? RatingCeiling(certificate: decodedRating(value.title))
                    ?? RatingCeiling.forTitle(certificate: nil)
                return ceiling.allows(rating) ? key : nil
            })
    }

    /// The same for bare rating strings (each is its own title).
    public static func admittedContentRatings(
        _ ratings: [String], ceiling: RatingCeiling
    ) -> Set<String> {
        admittedContentRatings(values: ratings.map { PlexFilterValue(key: $0, title: $0) }, ceiling: ceiling)
    }

    /// A rating label with any percent-encoding removed (`gb%2FPG` to `gb/PG`); the input when it does not decode.
    public static func decodedRating(_ raw: String) -> String {
        raw.removingPercentEncoding ?? raw
    }
}

extension PlexLibraryMapping {
    static func letterBuckets(_ directories: [PlexWireDirectory]) -> [PlexLetterBucket] {
        directories.compactMap { directory in
            guard let raw = directory.title ?? directory.key, !raw.isEmpty else { return nil }
            let isLetter = raw.count == 1 && raw.first!.isLetter
            return PlexLetterBucket(
                title: isLetter ? raw.uppercased() : "#", size: max(0, directory.size ?? 0))
        }
    }

    static func filterValues(_ directories: [PlexWireDirectory]) -> [PlexFilterValue] {
        directories.compactMap { directory in
            guard let key = directory.key, !key.isEmpty else { return nil }
            return PlexFilterValue(key: key, title: directory.title ?? key)
        }
    }

    static func collections(_ items: [PlexWireMetadata]) -> [PlexCollection] {
        items.compactMap { item in
            // Only collection rows: a server that answers with titles must not turn them into collections.
            guard let id = item.ratingKey, !id.isEmpty, item.type.map({ $0 == "collection" }) ?? true else { return nil }
            return PlexCollection(
                id: id, title: item.title ?? "", thumbPath: item.thumb, childCount: item.childCount,
                summary: item.summary.flatMap { $0.isEmpty ? nil : $0 }, artPath: item.art)
        }
    }
}
