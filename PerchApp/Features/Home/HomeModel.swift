import Foundation
import Observation
import PerchCore

/// Home's rows and state (docs/design/wp-09-home.md sections 4, 6 and 8). Cached rows are read synchronously
/// in `init`, so the first frame already has them; `refresh()` then replaces each row in place as it lands.
/// Knows nothing of Plex or the app shell: rows come from injected sources so tests need no server.
@MainActor @Observable
final class HomeModel {
    /// The spec section 6 states. `content` covers warm launch, offline with rows, kid and partial.
    enum State: Equatable {
        case content, firstLaunch, emptyLibrary, offlineNoCache
    }

    /// One home row: its cached copy (synchronous, never touches the network) and a fresh fetch.
    struct Source {
        let id: String
        let cached: @MainActor () -> MediaRow?
        let refresh: @Sendable () async throws -> MediaRow
    }

    static let firstLaunchTimeout = Duration.seconds(20)

    /// Non-empty rows only, in source order.
    var rows: [MediaRow] {
        sourceIDs.compactMap { rowsByID[$0] }.filter { !$0.items.isEmpty }
    }

    var state: State {
        if !rows.isEmpty { return .content }
        return resolved ?? .firstLaunch
    }

    /// Raised once when a refresh fails while rows are shown; the view clears it when the notice goes.
    var offlineNotice = false

    /// Spec 4: the first Continue watching item, else the newest Recently added film or series, else nil.
    var heroItem: MediaSummary? {
        Self.hero(continueWatching: rowsByID[HomeRowID.continueWatching], recentlyAdded: rowsByID[HomeRowID.recentlyAdded])
    }

    /// True for the hero's Continue watching pick (button Resume), false for a Recently added pick (Play).
    var heroResumes: Bool {
        guard let first = rowsByID[HomeRowID.continueWatching]?.items.first else { return false }
        return heroItem?.id == first.id
    }

    @ObservationIgnored private let sources: [Source]
    @ObservationIgnored private let sourceIDs: [String]
    @ObservationIgnored private let isServerUnreachable: @MainActor () -> Bool
    private var rowsByID: [String: MediaRow] = [:]
    /// What an empty Home shows once it knows: the library is empty, or the server cannot be reached.
    private var resolved: State?
    /// Set by a failed refresh, cleared by a successful one, so the notice shows once per failure.
    @ObservationIgnored private var noticeRaisedForFailure = false
    @ObservationIgnored private(set) var isRefreshing = false

    init(sources: [Source], isServerUnreachable: @escaping @MainActor () -> Bool = { false }) {
        self.sources = sources
        self.sourceIDs = sources.map(\.id)
        self.isServerUnreachable = isServerUnreachable
        var cached: [String: MediaRow] = [:]
        for source in sources {
            if let row = source.cached() { cached[source.id] = row }
        }
        rowsByID = cached
        // Every row came from the snapshot and all are empty: the library is empty, say so straight away.
        if !sources.isEmpty, cached.count == sources.count, cached.values.allSatisfy(\.items.isEmpty) {
            resolved = .emptyLibrary
        } else if sources.isEmpty || (cached.isEmpty && isServerUnreachable()) {
            resolved = isServerUnreachable() ? .offlineNoCache : nil
        }
    }

    static func hero(continueWatching: MediaRow?, recentlyAdded: MediaRow?) -> MediaSummary? {
        if let first = continueWatching?.items.first { return first }
        let candidates = (recentlyAdded?.items ?? []).filter { $0.kind == .film || $0.kind == .series }
        // Newest by date added; the row order breaks ties and stands in for a missing date.
        return candidates.enumerated().min { a, b in
            switch (a.element.addedAt, b.element.addedAt) {
            case (let x?, let y?) where x != y: x > y
            case (.some, nil): true
            case (nil, .some): false
            default: a.offset < b.offset
            }
        }?.element
    }

    /// Fetches every row at once and applies each as it lands. A failure keeps the row that was there.
    func refresh() async {
        guard !isRefreshing, !sources.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        var failed = false
        var emptyCount = 0
        await withTaskGroup(of: (String, Result<MediaRow, any Error>).self) { group in
            for source in sources {
                let id = source.id
                let refresh = source.refresh
                group.addTask {
                    do { return (id, .success(try await refresh())) } catch { return (id, .failure(error)) }
                }
            }
            for await (id, result) in group {
                switch result {
                case .success(let row):
                    apply(row, for: id)
                    if row.items.isEmpty { emptyCount += 1 }
                case .failure(let error):
                    // The Plex provider throws CancellationError when the fetched rows belong to another profile
                    // (a switch landed mid-flight; nothing cancels this refresh). That is not the server being away.
                    if !(error is CancellationError) { failed = true }
                }
            }
        }
        if failed {
            if rows.isEmpty {
                resolved = .offlineNoCache
            } else if !noticeRaisedForFailure {
                offlineNotice = true
            }
            noticeRaisedForFailure = true
        } else {
            noticeRaisedForFailure = false
            if rows.isEmpty, emptyCount == sources.count { resolved = .emptyLibrary }
        }
    }

    /// First launch with nothing arrived after the timeout: the server state decides (spec 6).
    func firstLaunchTimedOut() {
        guard state == .firstLaunch else { return }
        resolved = isServerUnreachable() ? .offlineNoCache : .emptyLibrary
    }

    /// The server state changed; unreachable with nothing to show ends the first-launch wait at once.
    func serverStateChanged(unreachable: Bool) {
        if unreachable, state == .firstLaunch { resolved = .offlineNoCache }
    }

    /// Same row id, same item ids where unchanged: SwiftUI keeps identity and animates in place.
    private func apply(_ row: MediaRow, for id: String) {
        if rowsByID[id] != row { rowsByID[id] = row }
    }
}
