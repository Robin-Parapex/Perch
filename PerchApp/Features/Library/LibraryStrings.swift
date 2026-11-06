import Foundation
import PerchCore
import PerchPlex

/// Copy for the Films and Series grids, in sentence case (GLOSSARY). No service names, no backend words.
enum LibraryStrings {
    static let sort = "Sort"
    static let genre = "Genre"
    static let decade = "Decade"
    static let resolution = "Resolution"
    static let unwatched = "Unwatched"
    static let collections = "Collections"
    static let any = "Any"
    static let markWatched = "Mark as watched"
    static let markUnwatched = "Mark as unwatched"
    static let tryAgain = "Try again"
    static let clearFilters = "Clear filters"
    static let noMatchesTitle = "Nothing matches these filters"
    static let noMatchesMessage = "Try fewer filters, or clear them to see everything."
    static let failedTitle = "Couldn't reach your library"
    static let failedMessage = "Check that the server is on, then try again."
    static let collectionEmpty = "Nothing in this collection yet"

    static func clearFilters(count: Int) -> String { "Clear filters (\(count))" }

    static func emptyTitle(_ kind: PlexLibrarySection.Kind) -> String {
        kind == .film ? "No films yet" : "No series yet"
    }

    static func emptyMessage(_ kind: PlexLibrarySection.Kind) -> String {
        kind == .film ? "Films you add will show up here." : "Series you add will show up here."
    }

    static func sortTitle(_ sort: LibrarySort) -> String {
        switch sort {
        case .recentlyAdded: "Recently added"
        case .title: "Title"
        case .year: "Year"
        case .rating: "Rating"
        }
    }

    /// Grid caption: the title, then the year. Watched shows as a tick on the poster.
    static func caption(_ item: MediaSummary) -> (title: String, subtitle: String?) {
        (item.title, item.year.map(String.init))
    }

    /// A collection's name without a trailing " Collection" ("Toy Story Collection" reads "Toy Story").
    static func collectionTitle(_ title: String) -> String {
        let suffix = " Collection"
        guard title.count > suffix.count, title.lowercased().hasSuffix(suffix.lowercased()) else { return title }
        return String(title.dropLast(suffix.count))
    }

    static func collectionCount(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        return count == 1 ? "1 title" : "\(count) titles"
    }
}
