#if DEBUG
import Foundation
import OSLog
import PerchCore
import PerchPlex

/// DEBUG-only `-PerchTitleProbe` (WP-11): once per launch, when the session is ready, reads the first film's and the
/// first series' detail and the series' episodes from the real server, and logs whether cast and a theme come back
/// and the season and episode counts. Counts and yes/no only: no token, no address, no URL, no titles. Read-only.
@MainActor
enum TitleProbe {
    private static var ran = false
    private static let log = Logger(subsystem: "com.robrolabs.perch", category: "titleProbe")

    static func runIfAsked(library: PlexLibrary, arguments: [String] = ProcessInfo.processInfo.arguments) async {
        guard arguments.contains("-PerchTitleProbe"), !ran else { return }
        ran = true
        do {
            let sections = try await library.sections()
            for kind in [PlexLibrarySection.Kind.film, .series] {
                guard let section = sections.first(where: { $0.kind == kind && !$0.isOtherVideos }) else {
                    log.notice("TPROBE \(kind.rawValue, privacy: .public): no section")
                    continue
                }
                let pager = await library.pager(query: PlexSectionQuery(sectionID: section.id, kind: kind))
                guard let first = try await pager.nextPage().first else {
                    log.notice("TPROBE \(kind.rawValue, privacy: .public): empty section")
                    continue
                }
                let detail = try await library.detail(ratingKey: first.id)
                let portraits = detail.cast.filter { $0.thumbPath != nil }.count
                let httpsPortraits = detail.cast.filter { $0.thumbPath?.hasPrefix("https://") == true }.count
                log.notice(
                    "TPROBE \(kind.rawValue, privacy: .public): cast=\(detail.cast.count, privacy: .public) portraits=\(portraits, privacy: .public) https=\(httpsPortraits, privacy: .public) roles=\(detail.cast.filter { $0.role != nil }.count, privacy: .public) theme=\(detail.themePath != nil, privacy: .public) logo=\(detail.summary.logoPath != nil, privacy: .public) genres=\(detail.genres.count, privacy: .public) versions=\(detail.versions.count, privacy: .public)"
                )
                guard kind == .series else { continue }
                let episodes = try await library.allEpisodes(ofSeries: first.id)
                let seasons = Set(episodes.compactMap(\.seasonNumber))
                let next = SeriesNext.choose(in: episodes)
                log.notice(
                    "TPROBE series: childCount=\(detail.childCount ?? -1, privacy: .public) seasons=\(seasons.count, privacy: .public) episodes=\(episodes.count, privacy: .public) watched=\(episodes.filter(\.isWatched).count, privacy: .public) inProgress=\(episodes.filter(\.isInProgress).count, privacy: .public) thumbs=\(episodes.filter { $0.thumbPath != nil }.count, privacy: .public) summaries=\(episodes.filter { $0.summary != nil }.count, privacy: .public) next=\(next.map { "\($0.mode)" } ?? "none", privacy: .public)"
                )
            }
            log.notice("TPROBE done")
        } catch {
            log.notice("TPROBE failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }
}
#endif
