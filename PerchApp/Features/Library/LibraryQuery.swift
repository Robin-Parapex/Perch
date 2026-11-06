import Foundation
import PerchCore
import PerchPlex

/// The four sorts a library grid offers (SPEC 4). "Unwatched" is a filter chip, not a sort.
enum LibrarySort: String, CaseIterable, Hashable {
    case recentlyAdded, title, year, rating

    var plex: PlexSectionSort {
        switch self {
        case .recentlyAdded: .recentlyAdded
        case .title: .title
        case .year: .year
        case .rating: .rating
        }
    }
}

/// One value of a filter menu (a genre, a decade, a resolution, a collection).
struct LibraryFilterChoice: Hashable, Identifiable {
    let key: String
    let title: String
    var id: String { key }

    init(key: String, title: String) {
        self.key = key
        self.title = title
    }

    init(_ value: PlexFilterValue) { self.init(key: value.key, title: value.title) }
}

/// The filters a grid has set. One value per menu, so a chip shows its value.
struct LibraryFilters: Hashable {
    var genre: LibraryFilterChoice?
    var decade: LibraryFilterChoice?
    var resolution: LibraryFilterChoice?
    var unwatched = false
    var collection: LibraryFilterChoice?

    var activeCount: Int {
        [genre != nil, decade != nil, resolution != nil, unwatched, collection != nil].filter { $0 }.count
    }

    var isEmpty: Bool { activeCount == 0 }

    /// Stable text for focus memory keys.
    var signature: String {
        [genre?.key ?? "-", decade?.key ?? "-", resolution?.key ?? "-", unwatched ? "u" : "-", collection?.key ?? "-"]
            .joined(separator: ",")
    }
}

/// Builds the section query and applies the rating ceiling (PERMISSIONS 39 and 70, enforced in code).
enum LibraryQueryBuilder {
    /// Perch's ceiling is below the one the server already enforces for this profile (an Admin lowered it).
    /// Only then does Perch filter by content rating; otherwise the server's own restriction stands and no
    /// rating filter is sent, so unrated titles are not hidden from adults.
    static func isCeilingLowered(_ context: RowContext) -> Bool { context.ceiling < context.serviceCeiling }

    /// The content ratings to send: nil when the ceiling is not lowered; else what `load` reports the ceiling
    /// admits. A failed load fails closed (an empty set admits nothing).
    static func admittedRatings(
        for context: RowContext, load: @Sendable () async throws -> Set<String>
    ) async -> Set<String>? {
        guard isCeilingLowered(context) else { return nil }
        return (try? await load()) ?? []
    }

    static func query(
        sectionID: String, kind: PlexLibrarySection.Kind, sort: LibrarySort, filters: LibraryFilters,
        admittedRatings: Set<String>?, startOffset: Int = 0
    ) -> PlexSectionQuery {
        PlexSectionQuery(
            sectionID: sectionID, kind: kind, sort: sort.plex,
            genreIDs: filters.genre.map { [$0.key] } ?? [],
            decade: filters.decade.flatMap { Int($0.key) },
            resolution: filters.resolution?.key,
            unwatched: filters.unwatched,
            collectionID: filters.collection?.key,
            contentRatings: admittedRatings,
            startOffset: startOffset)
    }

    /// The final guard on every page: `RowContext.admits` (filters only when the ceiling is lowered; an unrated
    /// title counts as 15 and fails closed), then duplicates of items already shown are dropped.
    static func guardPage(_ page: [MediaSummary], context: RowContext, existing: Set<String>) -> [MediaSummary] {
        var seen = existing
        return page.filter { item in
            guard context.admits(item), !seen.contains(item.id) else { return false }
            seen.insert(item.id)
            return true
        }
    }

    /// Where a letter starts in the full (filtered) list, from the server's letter buckets.
    static func letterOffset(_ letter: String, in buckets: [PlexLetterBucket]) -> Int? {
        letterOffsets(buckets)[letter]
    }

    /// The letter an absolute position falls in (the last bucket starting at or before it).
    static func letter(atOffset offset: Int, in buckets: [PlexLetterBucket]) -> String? {
        var running = 0
        var current: String?
        for bucket in buckets {
            if running > offset { break }
            current = bucket.title
            running += max(0, bucket.size)
        }
        return current
    }
}

/// What can hold focus on a library grid.
enum LibraryFocus: Hashable {
    case item(String)
    case collection(String)
    case control(String)
    case letter(String)
}

/// A collection pushed on a tab's stack.
struct LibraryCollectionRoute: Hashable {
    let sectionID: String
    let kind: PlexLibrarySection.Kind
    let collectionID: String
    let title: String
}
