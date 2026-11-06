#if DEBUG
import Foundation
import OSLog
import PerchCore
import PerchPlex

/// DEBUG-only `-PerchLibraryProbe` (WP-10): once per launch, when the session is ready, asks the real server how
/// its browse endpoints treat a content-rating filter, for the first film and the first series section. Logs one
/// `PROBE` line per check (counts and yes/no only: no token, no address). Read-only.
@MainActor
enum LibraryProbe {
    private static var ran = false
    private static let log = Logger(subsystem: "com.robrolabs.perch", category: "libraryProbe")

    static func runIfAsked(library: PlexLibrary, arguments: [String] = ProcessInfo.processInfo.arguments) async {
        guard arguments.contains("-PerchLibraryProbe"), !ran else { return }
        ran = true
        do {
            let sections = try await library.sections()
            for kind in [PlexLibrarySection.Kind.film, .series] {
                guard let section = sections.first(where: { $0.kind == kind && !$0.isOtherVideos }) else {
                    log.notice("PROBE \(kind.rawValue, privacy: .public): no section")
                    continue
                }
                await probe(section, library: library)
            }
            log.notice("PROBE done")
        } catch {
            log.notice("PROBE failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func probe(_ section: PlexLibrarySection, library: PlexLibrary) async {
        let tag = "\(section.kind.rawValue) section \(section.id)"
        let base = PlexSectionQuery(sectionID: section.id, kind: section.kind)
        let ratings = ((try? await library.filterValues(sectionID: section.id, kind: .contentRating)) ?? []).map(\.key)
        let admitted = PlexLibrary.admittedContentRatings(ratings, ceiling: .pg)
        let excluded = Set(ratings).subtracting(admitted)
        var filtered = base
        filtered.contentRatings = admitted
        log.notice(
            "PROBE \(tag, privacy: .public) ratings: \(ratings.count, privacy: .public) values, PG admits \(admitted.sorted().joined(separator: ","), privacy: .public)"
        )

        // 1. Unfiltered total.
        let total = (try? await library.sectionTotal(query: base)) ?? nil
        log.notice("PROBE \(tag, privacy: .public) check1 totalSize unfiltered=\(total.map(String.init) ?? "nil", privacy: .public)")

        // 2. Total with the PG content-rating set.
        let pgTotal = (try? await library.sectionTotal(query: filtered)) ?? nil
        let honoured = pgTotal.flatMap { pg in total.map { pg < $0 } } ?? false
        log.notice(
            "PROBE \(tag, privacy: .public) check2 totalSize contentRating(PG set)=\(pgTotal.map(String.init) ?? "nil", privacy: .public) honoured=\(honoured, privacy: .public)"
        )

        // 3. firstCharacter sizes under the same filter.
        let lettersAll = (try? await library.firstCharacters(query: base)) ?? []
        let lettersPG = (try? await library.firstCharacters(query: filtered)) ?? []
        let sumAll = lettersAll.reduce(0) { $0 + $1.size }
        let sumPG = lettersPG.reduce(0) { $0 + $1.size }
        log.notice(
            "PROBE \(tag, privacy: .public) check3 firstCharacter sum unfiltered=\(sumAll, privacy: .public) PG=\(sumPG, privacy: .public) buckets=\(lettersAll.count, privacy: .public)/\(lettersPG.count, privacy: .public) changes=\(sumPG != sumAll, privacy: .public) matchesTotal=\(pgTotal == sumPG, privacy: .public)"
        )

        // 4. `contentRating!=` exclusion syntax.
        if excluded.isEmpty {
            log.notice("PROBE \(tag, privacy: .public) check4 exclusion: nothing to exclude")
        } else {
            let item = URLQueryItem(name: "contentRating!", value: excluded.sorted().joined(separator: ","))
            let exclusionTotal = (try? await library.sectionTotal(query: base, extraItems: [item])) ?? nil
            let honouredNot = exclusionTotal.flatMap { value in total.map { value < $0 } } ?? false
            let atLeastPG = exclusionTotal.flatMap { value in pgTotal.map { value >= $0 } } ?? false
            log.notice(
                "PROBE \(tag, privacy: .public) check4 contentRating!= excluding \(excluded.count, privacy: .public) values total=\(exclusionTotal.map(String.init) ?? "nil", privacy: .public) honoured=\(honouredNot, privacy: .public) atLeastPG=\(atLeastPG, privacy: .public)"
            )
        }

        // 5. Collections and collection children under the filter.
        let collectionsAll = (try? await library.collections(query: base)) ?? []
        let collectionsPG = (try? await library.collections(query: filtered)) ?? []
        let childAll = collectionsAll.compactMap(\.childCount).reduce(0, +)
        let childPG = collectionsPG.compactMap(\.childCount).reduce(0, +)
        var childLine = "no collections"
        if let first = collectionsAll.max(by: { ($0.childCount ?? 0) < ($1.childCount ?? 0) }) {
            let rawAll = (try? await library.collectionChildCount(collectionID: first.id, contentRatings: nil)) ?? -1
            let rawPG = (try? await library.collectionChildCount(collectionID: first.id, contentRatings: admitted)) ?? -1
            childLine = "largest collection children unfiltered=\(rawAll) PG=\(rawPG) honoured=\(rawPG >= 0 && rawPG < rawAll)"
        }
        log.notice(
            "PROBE \(tag, privacy: .public) check5 collections unfiltered=\(collectionsAll.count, privacy: .public) PG=\(collectionsPG.count, privacy: .public) childCountSum \(childAll, privacy: .public)/\(childPG, privacy: .public); \(childLine, privacy: .public)"
        )
    }
}
#endif
