import AVFoundation
import Foundation
import OSLog
import PerchCore
import PerchPlex

/// One title or series page's data (WP-11): the detail and, for a series, every episode (one `allLeaves` call,
/// grouped by season here). The opener's summary seeds the first frame. A title above the profile's ceiling never
/// shows: the same guard as the grids (`RowContext.admits`, and the certificate check for a kid).
@MainActor
@Observable
final class TitlePageModel {
    enum Phase: Equatable { case loading, ready, unavailable, failed }

    let route: TitleRoute
    private(set) var phase: Phase = .loading
    private(set) var detail: MediaDetail?
    private(set) var episodes: [MediaSummary] = []
    var selectedSeason: Int?

    @ObservationIgnored private let library: PlexLibrary
    @ObservationIgnored private let context: RowContext
    @ObservationIgnored private let isKid: Bool
    static let log = Logger(subsystem: "com.robrolabs.perch", category: "title")

    init(route: TitleRoute, library: PlexLibrary, context: RowContext, isKid: Bool) {
        self.route = route
        self.library = library
        self.context = context
        self.isKid = isKid
    }

    /// What the page shows now: the detail's summary once it is here, else the opener's.
    var summary: MediaSummary? { detail?.summary ?? route.seed }

    var next: SeriesNext? { SeriesNext.choose(in: episodes) }

    /// Season numbers in order, Specials last (as the Apple TV app lists them).
    var seasons: [Int] {
        let numbers = Set(episodes.map(SeriesNext.season(of:)))
        return numbers.filter { $0 > 0 }.sorted() + (numbers.contains(0) ? [0] : [])
    }

    var seasonEpisodes: [MediaSummary] {
        guard let selectedSeason else { return [] }
        return episodes.filter { SeriesNext.season(of: $0) == selectedSeason }
            .sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
    }

    func load(isSeries: Bool) async {
        do {
            let loaded = try await library.detail(ratingKey: route.id)
            guard !LibraryQueryBuilder.guardCollectionItems([loaded.summary], context: context, isKid: isKid).isEmpty
            else {
                detail = nil
                phase = .unavailable
                return
            }
            detail = loaded
            if isSeries {
                episodes = try await library.allEpisodes(ofSeries: route.id)
                chooseSeasonIfNeeded()
            }
            phase = .ready
        } catch is CancellationError {
            // The page went away (or the task restarted) mid-load: not a failure to show.
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            Self.log.notice("Title: load failed: \(String(describing: type(of: error)), privacy: .public)")
            if phase != .ready { phase = .failed }
        }
    }

    /// After playback: progress and ticks change, the chosen season stays.
    func refresh(isSeries: Bool) async {
        if let loaded = try? await library.detail(ratingKey: route.id) { detail = loaded }
        if isSeries, let loaded = try? await library.allEpisodes(ofSeries: route.id) { episodes = loaded }
    }

    /// The season the page opens on: the opener's season, else the one holding the next episode, else the first.
    private func chooseSeasonIfNeeded() {
        if let selectedSeason, seasons.contains(selectedSeason) { return }
        if let seasonID = route.seasonID,
            let episode = episodes.first(where: { $0.seasonID == seasonID })
        {
            selectedSeason = SeriesNext.season(of: episode)
        } else {
            selectedSeason = next.map { SeriesNext.season(of: $0.episode) } ?? seasons.first
        }
    }

    /// Every regular episode watched: the series hero offers Mark series unwatched instead.
    var seriesWatched: Bool {
        let regular = episodes.filter { SeriesNext.season(of: $0) > 0 }
        return !regular.isEmpty && regular.allSatisfy(\.isWatched)
    }

    /// Marks the whole series (Plex marks every episode under it), then reads the episodes back.
    func setSeriesWatched(_ watched: Bool) async {
        do {
            try await library.setWatched(watched, itemID: route.id)
        } catch {
            Self.log.notice("Title: series watch state not changed: \(String(describing: type(of: error)), privacy: .public)")
            return
        }
        for index in episodes.indices {
            episodes[index].viewCount = watched ? max(1, episodes[index].viewCount) : 0
            episodes[index].viewOffsetMs = nil
        }
        await refresh(isSeries: true)
    }

    func setWatched(_ watched: Bool, itemID: String) async {
        do {
            try await library.setWatched(watched, itemID: itemID)
        } catch {
            Self.log.notice("Title: watch state not changed: \(String(describing: type(of: error)), privacy: .public)")
            return
        }
        func apply(_ item: inout MediaSummary) {
            item.viewCount = watched ? max(1, item.viewCount) : 0
            item.viewOffsetMs = nil
        }
        if let index = episodes.firstIndex(where: { $0.id == itemID }) { apply(&episodes[index]) }
        if detail?.summary.id == itemID, var updated = detail {
            apply(&updated.summary)
            detail = updated
        }
    }

    // MARK: Theme

    func themeSource() async -> PlexThemeSource? {
        guard let detail, let path = detail.themePath else { return nil }
        return try? await library.themeSource(ratingKey: detail.id, path: path)
    }
}

/// Plays a title's theme tune softly (WP-11): an `AVURLAsset` with the token in its HTTP headers (the option key
/// NativeEngine uses), 0.25 volume, 1 s fades in and out. One per page; `stop()` fades out on leaving, `stop(immediately:)`
/// cuts it when playback starts or the page is covered.
@MainActor
@Observable
final class ThemeMusicPlayer {
    enum State: String { case none, off, playing, stopped }

    private(set) var state: State = .none
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var fadeTask: Task<Void, Never>?
    @ObservationIgnored private var fadingPlayer: AVPlayer?

    func markOff() { state = .off }

    func start(_ source: PlexThemeSource) {
        guard player == nil, state != .stopped else { return }
        let asset = AVURLAsset(url: source.url, options: ["AVURLAssetHTTPHeaderFieldsKey": source.headers])
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.volume = 0
        player.play()
        self.player = player
        state = .playing
        fade(to: ThemeMusicPolicy.volume, then: nil)
    }

    /// Releases the player, fading out over 1 s on leaving the page, at once when playback starts (`immediately`).
    /// Final for this page: a stopped theme never starts again.
    func stop(immediately: Bool = false) {
        if immediately, state == .stopped, fadeTask != nil {
            // A fade-out is still running: cut it short.
            fadeTask?.cancel()
            fadeTask = nil
            fadingPlayer?.pause()
            fadingPlayer = nil
            return
        }
        guard state != .stopped else { return }
        state = .stopped
        guard let player else { return }
        self.player = nil
        if immediately {
            fadeTask?.cancel()
            fadeTask = nil
            player.pause()
        } else {
            fadingPlayer = player
            fade(from: player, to: 0) { [weak self] in
                player.pause()
                self?.fadingPlayer = nil
            }
        }
    }

    private func fade(to target: Float, then done: (() -> Void)?) {
        guard let player else { return }
        fade(from: player, to: target, then: done)
    }

    private func fade(from player: AVPlayer, to target: Float, then done: (() -> Void)?) {
        fadeTask?.cancel()
        let start = player.volume
        let steps = 20
        let step = ThemeMusicPolicy.fade / steps
        fadeTask = Task { @MainActor in
            for index in 1...steps {
                try? await Task.sleep(for: step)
                guard !Task.isCancelled else { return }
                player.volume = start + (target - start) * Float(index) / Float(steps)
            }
            done?()
        }
    }
}
