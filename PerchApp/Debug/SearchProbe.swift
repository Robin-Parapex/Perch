#if DEBUG
import Foundation
import OSLog
import PerchCore
import PerchPlex

/// DEBUG-only `-PerchSearchProbe` (WP-12): once per launch, when the session is ready, asks the real server's
/// `/hubs/search` for two short queries, unfiltered, with the PG ceiling's content ratings, and with a rating no
/// title has, and logs the group counts. Counts only: no token, no address, no URL and no titles. Read-only.
@MainActor
enum SearchProbe {
    private static var ran = false
    private static let log = Logger(subsystem: "com.robrolabs.perch", category: "searchProbe")

    static func runIfAsked(library: PlexLibrary, arguments: [String] = ProcessInfo.processInfo.arguments) async {
        guard arguments.contains("-PerchSearchProbe"), !ran else { return }
        ran = true
        var admitted = Set<String>()
        for section in ((try? await library.sections()) ?? []) where !section.isOtherVideos {
            admitted.formUnion((try? await library.admittedContentRatings(sectionID: section.id, ceiling: .pg)) ?? [])
        }
        log.notice("PROBE search PG admits \(admitted.count, privacy: .public) ratings")
        for query in ["the", "a"] {
            let clock = ContinuousClock()
            let started = clock.now
            let all = await counts(library, query, nil)
            let elapsed = clock.now - started
            let pg = admitted.isEmpty ? "n/a" : await counts(library, query, admitted)
            let none = await counts(library, query, ["PerchNoSuchRating"])
            log.notice(
                "PROBE search q=\(query, privacy: .public) unfiltered=\(all, privacy: .public) (\(elapsed.components.seconds, privacy: .public)s+\(elapsed.components.attoseconds / 1_000_000_000_000_000, privacy: .public)ms) PG=\(pg, privacy: .public) impossible=\(none, privacy: .public)"
            )
        }
        await collections(library, "the")
        log.notice("PROBE search done")
    }

    /// Collections for `query`: how many lack their section or type, and how many an owner (server ceiling, not a
    /// kid) keeps after the app's guard. Counts only.
    private static func collections(_ library: PlexLibrary, _ query: String) async {
        guard let raw = try? await library.search(query: query) else {
            log.notice("PROBE search collections q=\(query, privacy: .public) error")
            return
        }
        let owner = RowContext(profileID: "probe", serviceCeiling: .eighteen, ceiling: .eighteen)
        let kept = SearchModel.guardResults(raw, context: owner, isKid: false).collections.count
        let noSection = raw.collections.filter { $0.sectionID == nil }.count
        let noKind = raw.collections.filter { $0.kind == nil }.count
        log.notice(
            "PROBE search collections q=\(query, privacy: .public) raw=\(raw.collections.count, privacy: .public) noSection=\(noSection, privacy: .public) noType=\(noKind, privacy: .public) ownerAfterGuard=\(kept, privacy: .public)"
        )
    }

    /// "films/series/episodes/collections", or the error's type.
    private static func counts(_ library: PlexLibrary, _ query: String, _ ratings: Set<String>?) async -> String {
        do {
            let results = try await library.search(query: query, contentRatings: ratings)
            return "\(results.films.count)/\(results.series.count)/\(results.episodes.count)/\(results.collections.count)"
        } catch {
            return "error \(String(describing: type(of: error)))"
        }
    }
}
#endif
