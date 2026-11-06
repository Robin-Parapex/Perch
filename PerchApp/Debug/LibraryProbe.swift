#if DEBUG
import Foundation
import OSLog
import PerchCore
import PerchPlex

/// DEBUG-only `-PerchLibraryProbe` (WP-10): once per launch, when the session is ready, asks the real server how
/// its browse endpoints treat a content-rating filter, for the first film and the first series section. Logs one
/// `PROBE` line per check (counts, yes/no and rating labels only: no token, no address, no URL). Read-only.
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
            log.notice("PROBE failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    private static func probe(_ section: PlexLibrarySection, library: PlexLibrary) async {
        let tag = "\(section.kind.rawValue) section \(section.id)"
        let base = PlexSectionQuery(sectionID: section.id, kind: section.kind)
        let values = (try? await library.filterValues(sectionID: section.id, kind: .contentRating)) ?? []
        // Rating labels only (no host, token or URL), once per section.
        let pairs = values.map { "\($0.key)=\($0.title)" }.joined(separator: " | ")
        log.notice("PROBE \(tag, privacy: .public) raw ratings (\(values.count, privacy: .public)): \(pairs, privacy: .public)")
        // Before the fix: the raw key was classified and sent as it came.
        let before = Set(values.map(\.key).filter { RatingCeiling.forTitle(certificate: $0) <= .pg })
        let admitted = PlexLibrary.admittedContentRatings(values: values, ceiling: .pg)
        let admitted12 = PlexLibrary.admittedContentRatings(values: values, ceiling: .twelveA)
        let decodedAll = Set(values.map { PlexLibrary.decodedRating($0.key) })
        let excluded = decodedAll.subtracting(admitted)
        log.notice(
            "PROBE \(tag, privacy: .public) PG admits (before) \(before.sorted().joined(separator: ","), privacy: .public)")
        log.notice("PROBE \(tag, privacy: .public) PG admits \(admitted.sorted().joined(separator: ","), privacy: .public)")
        log.notice("PROBE \(tag, privacy: .public) 12 admits \(admitted12.sorted().joined(separator: ","), privacy: .public)")
        var filtered = base
        filtered.contentRatings = admitted
        var filtered12 = base
        filtered12.contentRatings = admitted12
        var filteredBefore = base
        filteredBefore.contentRatings = before

        // 1-2. Totals: unfiltered, PG before the fix, PG and 12 after.
        let total = (try? await library.sectionTotal(query: base)) ?? nil
        let beforeTotal = before.isEmpty ? 0 : ((try? await library.sectionTotal(query: filteredBefore)) ?? nil)
        let pgTotal = (try? await library.sectionTotal(query: filtered)) ?? nil
        let twelveTotal = (try? await library.sectionTotal(query: filtered12)) ?? nil
        func text(_ value: Int?) -> String { value.map(String.init) ?? "nil" }
        log.notice(
            "PROBE \(tag, privacy: .public) totals unfiltered=\(text(total), privacy: .public) PGbefore=\(text(beforeTotal), privacy: .public) PG=\(text(pgTotal), privacy: .public) 12=\(text(twelveTotal), privacy: .public)"
        )

        // 3. firstCharacter sizes under the PG filter.
        let lettersPG = (try? await library.firstCharacters(query: filtered)) ?? []
        let sumPG = lettersPG.reduce(0) { $0 + $1.size }
        log.notice(
            "PROBE \(tag, privacy: .public) check3 firstCharacter PG sum=\(sumPG, privacy: .public) buckets=\(lettersPG.count, privacy: .public) matchesTotal=\(pgTotal == sumPG, privacy: .public)"
        )

        // 4. `contentRating!=` exclusion syntax with the decoded labels.
        if !excluded.isEmpty {
            let item = URLQueryItem(name: "contentRating!", value: excluded.sorted().joined(separator: ","))
            let exclusionTotal = (try? await library.sectionTotal(query: base, extraItems: [item])) ?? nil
            log.notice(
                "PROBE \(tag, privacy: .public) check4 contentRating!= excluding \(excluded.count, privacy: .public) total=\(text(exclusionTotal), privacy: .public)"
            )
        }

        // 5. Collections under the PG filter, children with the filter, and the cost of guarding every
        // collection on the client (load the members, keep certificates the PG ceiling allows).
        let collectionsAll = (try? await library.collections(query: base)) ?? []
        let collectionsPG = (try? await library.collections(query: filtered)) ?? []
        var childLine = "no collections"
        if let first = collectionsAll.max(by: { ($0.childCount ?? 0) < ($1.childCount ?? 0) }) {
            let rawAll = (try? await library.collectionChildCount(collectionID: first.id, contentRatings: nil)) ?? -1
            let rawPG = (try? await library.collectionChildCount(collectionID: first.id, contentRatings: admitted)) ?? -1
            childLine = "largest children unfiltered=\(rawAll) PGparam=\(rawPG) honoured=\(rawPG >= 0 && rawPG < rawAll)"
        }
        log.notice(
            "PROBE \(tag, privacy: .public) check5 collections unfiltered=\(collectionsAll.count, privacy: .public) PG=\(collectionsPG.count, privacy: .public); \(childLine, privacy: .public)"
        )
        guard !collectionsAll.isEmpty else { return }
        let clock = ContinuousClock()
        let started = clock.now
        var kept = 0
        var keptTitles = 0
        var failures = 0
        for collection in collectionsAll {
            do {
                let members = try await library.collectionItems(collectionID: collection.id, query: base)
                let safe = members.filter { RatingCeiling.forTitle(certificate: $0.certificate) <= .pg }
                if safe.count >= 2 { kept += 1 }
                keptTitles += safe.count
            } catch {
                failures += 1
            }
        }
        let elapsed = (clock.now - started).components
        let ms = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
        log.notice(
            "PROBE \(tag, privacy: .public) check6 client guard: \(collectionsAll.count, privacy: .public) collections loaded in \(ms, privacy: .public) ms, \(kept, privacy: .public) keep 2+ PG titles (\(keptTitles, privacy: .public) titles), failures=\(failures, privacy: .public)"
        )
    }
}
#endif
