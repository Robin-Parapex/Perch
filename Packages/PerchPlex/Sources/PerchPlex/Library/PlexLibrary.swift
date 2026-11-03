import Foundation
import PerchCore

/// What `PlexLibrary` asks of the permission engine. `Authoriser` conforms; tests swap in a stub.
public protocol PlexActionAuthorising: Sendable {
    func authorise(_ action: CoreAction, context: PermissionContext, entity: String?) async -> Decision
}

extension Authoriser: PlexActionAuthorising {}

/// The three Home rows Plex contributes.
public struct PlexHomeRows: Codable, Sendable, Equatable {
    public static let continueWatchingID = "plex.continueWatching"
    public static let upNextID = "plex.upNext"
    public static let recentlyAddedID = "plex.recentlyAdded"

    public var continueWatching: MediaRow
    public var upNext: MediaRow
    public var recentlyAdded: MediaRow

    public init(continueWatching: MediaRow, upNext: MediaRow, recentlyAdded: MediaRow) {
        self.continueWatching = continueWatching
        self.upNext = upNext
        self.recentlyAdded = recentlyAdded
    }

    public init(
        continueWatching: [MediaSummary] = [], upNext: [MediaSummary] = [],
        recentlyAdded: [MediaSummary] = []
    ) {
        self.init(
            continueWatching: MediaRow(
                id: Self.continueWatchingID, title: "Continue watching", items: continueWatching),
            upNext: MediaRow(id: Self.upNextID, title: "Up next in your series", items: upNext),
            recentlyAdded: MediaRow(
                id: Self.recentlyAddedID, title: "Recently added", items: recentlyAdded))
    }

    public func row(id: String) -> MediaRow? {
        switch id {
        case Self.continueWatchingID: continueWatching
        case Self.upNextID: upNext
        case Self.recentlyAddedID: recentlyAdded
        default: nil
        }
    }

    func capped(to limit: Int) -> PlexHomeRows {
        var copy = self
        copy.continueWatching.items = Array(copy.continueWatching.items.prefix(limit))
        copy.upNext.items = Array(copy.upNext.items.prefix(limit))
        copy.recentlyAdded.items = Array(copy.recentlyAdded.items.prefix(limit))
        return copy
    }

    /// Applies a watched or unwatched change to every copy of the item. Watched drops it from
    /// Continue watching and Up next, since neither row holds a finished title.
    mutating func apply(watched: Bool, itemID: String) {
        func update(_ row: inout MediaRow) {
            for index in row.items.indices where row.items[index].id == itemID {
                if watched {
                    row.items[index].viewCount = max(1, row.items[index].viewCount)
                    row.items[index].viewOffsetMs = nil
                } else {
                    row.items[index].viewCount = 0
                }
            }
        }
        update(&continueWatching)
        update(&upNext)
        update(&recentlyAdded)
        if watched {
            continueWatching.items.removeAll { $0.id == itemID }
            upNext.items.removeAll { $0.id == itemID }
        }
    }
}

/// One hub from `/hubs`, kept whole for later screens.
public struct PlexHub: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let type: String?
    public let items: [MediaSummary]
}

/// Library reads and watch-state changes for the active profile on the active server.
///
/// Every call takes a `PlexServerContext` and compares its generation with the session's before it
/// applies or returns anything. A stale result (the profile or server changed mid-request) is
/// dropped by throwing `CancellationError`; nothing is cached or returned from it.
public actor PlexLibrary: PlexWatchStateSink {
    public static let homeRowLimit = 40
    private static let hubCount = 20

    private struct RowsKey: Hashable {
        var profileID: String
        var machineID: String
        init(profileID: String, machineID: String) {
            self.profileID = profileID
            self.machineID = machineID
        }
        init(_ context: PlexServerContext) {
            profileID = context.profileID
            machineID = context.machineID
        }
    }

    private struct Flight {
        var id: UUID
        var generation: UInt64
        var task: Task<PlexHomeRows, Error>
    }

    private let contextSource: any PlexServerContextProviding
    private let transport: any PlexTransport
    private let endpoints: PlexEndpoints
    private let settings: SettingsStore
    private let authoriser: any PlexActionAuthorising
    private let snapshots: PlexHomeSnapshotStore
    private let watchState: PlexWatchState

    private var rows: [RowsKey: PlexHomeRows] = [:]
    private var flight: Flight?
    /// Local watched toggles, so a refresh that started earlier cannot undo them. Counts are bumped
    /// before the optimistic change; `PlexWatchState` revisions cover changes made through it.
    private var toggleCounts: [String: Int] = [:]
    private var localWatched: [String: Bool] = [:]
    private var playbackItems: [String: MediaSummary] = [:]
    private var activeKey: RowsKey?
    private var activeGeneration: UInt64?
    private var refreshTask: Task<Void, Never>?
    private var observeTask: Task<Void, Never>?
    private var lastReadyKey: RowsKey?
    /// Nil until the first state is seen; then whether the latest one was signed out.
    private var lastWasSignedOut: Bool?

    init(
        contextSource: any PlexServerContextProviding, transport: any PlexTransport,
        endpoints: PlexEndpoints, settings: SettingsStore, authoriser: any PlexActionAuthorising,
        snapshots: PlexHomeSnapshotStore
    ) {
        self.contextSource = contextSource
        self.transport = transport
        self.endpoints = endpoints
        self.settings = settings
        self.authoriser = authoriser
        self.snapshots = snapshots
        self.watchState = PlexWatchState(transport: transport, endpoints: endpoints)
    }

    /// How the app builds the library: the session supplies the server and token, the snapshots go to
    /// `snapshotsDirectory` (a purgeable Caches folder).
    public static func make(
        session: PlexSession, transport: any PlexTransport, identity: PlexClientIdentity,
        settings: SettingsStore, authoriser: Authoriser, snapshotsDirectory: URL
    ) -> PlexLibrary {
        PlexLibrary(
            contextSource: session, transport: transport, endpoints: PlexEndpoints(identity: identity),
            settings: settings, authoriser: authoriser,
            snapshots: PlexHomeSnapshotStore(directory: snapshotsDirectory))
    }

    // MARK: sections

    public func sections() async throws -> [PlexLibrarySection] {
        let context = try await current()
        let container = try await fetch(
            context, endpoints.librarySections(base: context.baseURL, token: context.token))
        return PlexLibraryMapping.sections(container.directory ?? [])
    }

    /// Pages `/library/sections/{id}/all`. `sort` is one Plex sort such as "titleSort" or "addedAt:desc".
    /// The pager is bound to the generation current now: after a profile or server change it returns
    /// nothing from the old one.
    public func pager(sectionID: String, sort: String?) async -> PlexSectionPager {
        PlexSectionPager(
            sectionID: sectionID, sort: sort, generation: await contextSource.currentGeneration(),
            contextSource: contextSource, transport: transport, endpoints: endpoints)
    }

    public func count(sectionID: String) async throws -> Int {
        let context = try await current()
        let container = try await fetch(
            context,
            endpoints.sectionCount(base: context.baseURL, token: context.token, sectionID: sectionID))
        return container.totalCount ?? container.rowCount
    }

    // MARK: Home rows

    /// The snapshot written for this profile, read synchronously (memory first, then the file). It is
    /// not ceiling-filtered: `ModuleRegistry` applies `RowContext.admit`.
    public nonisolated func cachedHomeRows(profileID: String) -> PlexHomeRows? {
        snapshots.read(profileID: profileID)
    }

    /// Fetches the three rows. Callers that arrive while a fetch is running share it (three row
    /// providers ask at once). On success the rows are kept in memory and written as a snapshot; on
    /// failure this throws and the last good rows stay.
    public func homeRows() async throws -> PlexHomeRows {
        try await ownedHomeRows().rows
    }

    /// `homeRows()` with the profile the rows belong to, so a caller serving another profile can drop them.
    func ownedHomeRows() async throws -> (profileID: String, rows: PlexHomeRows) {
        let context = try await current()
        if let flight, flight.generation == context.generation {
            return (context.profileID, try await flight.task.value)
        }
        return (context.profileID, try await startFetch(context))
    }

    private func startFetch(_ context: PlexServerContext) async throws -> PlexHomeRows {
        let id = UUID()
        let task = Task { try await self.fetchHomeRows(context) }
        flight = Flight(id: id, generation: context.generation, task: task)
        defer { if flight?.id == id { flight = nil } }
        return try await task.value
    }

    private func fetchHomeRows(_ context: PlexServerContext) async throws -> PlexHomeRows {
        let revisionsBefore = await watchState.revisions()
        let togglesBefore = toggleCounts

        let (inProgress, nextUp) = try await continueWatchingItems(context)
        var upNext = nextUp
        if upNext.isEmpty {
            // Fallback: the server's own on-deck list. Optional, so a failure here is not a failed fetch.
            let seriesInProgress = Set(inProgress.compactMap(\.seriesID))
            if let container = try? await fetch(
                context, endpoints.onDeck(base: context.baseURL, token: context.token))
            {
                upNext = Self.upNextItems(
                    PlexLibraryMapping.summaries(container.items), excludingSeries: seriesInProgress)
            }
        }
        let recent = try await recentlyAdded(context)

        let revisionsAfter = await watchState.revisions()
        try await ensureCurrent(context)
        // No suspension from here to the return: the merge and the store are one step.
        var fresh = PlexHomeRows(
            continueWatching: Array(inProgress.prefix(Self.homeRowLimit)),
            upNext: Array(upNext.prefix(Self.homeRowLimit)),
            recentlyAdded: Array(recent.prefix(Self.homeRowLimit)))
        var changed = Set(revisionsAfter.filter { revisionsBefore[$0.key] != $0.value }.keys)
        changed.formUnion(toggleCounts.filter { togglesBefore[$0.key] != $0.value }.keys)
        // Keep the local value for anything toggled while this was in flight (approach from Swiftfin).
        for itemID in changed {
            if let watched = localWatched[itemID] { fresh.apply(watched: watched, itemID: itemID) }
        }
        let key = RowsKey(context)
        rows[key] = fresh
        snapshots.write(fresh, profileID: context.profileID, machineID: context.machineID)
        return fresh
    }

    /// Items with an offset go to Continue watching; episodes with none go to Up next.
    private func continueWatchingItems(
        _ context: PlexServerContext
    ) async throws -> (inProgress: [MediaSummary], upNext: [MediaSummary]) {
        let container = try await fetch(
            context, endpoints.continueWatching(base: context.baseURL, token: context.token))
        var wire = container.metadata ?? []
        for hub in container.hubs {
            if let inline = hub.metadata, !inline.isEmpty {
                wire += inline
            } else if (hub.size ?? 1) > 0, let key = hub.key,
                let request = endpoints.hubItems(
                    base: context.baseURL, token: context.token, path: key, start: 0,
                    size: Self.homeRowLimit)
            {
                wire += try await fetch(context, request).items
            }
        }
        let summaries = PlexLibraryMapping.summaries(wire)
        var seen = Set<String>()
        let inProgress = summaries.filter { $0.isInProgress && seen.insert($0.id).inserted }
        let upNext = Self.upNextItems(
            summaries, excludingSeries: Set(inProgress.compactMap(\.seriesID)))
        return (inProgress, upNext)
    }

    /// Episodes with no offset, one per series, skipping series already in Continue watching.
    private static func upNextItems(
        _ items: [MediaSummary], excludingSeries: Set<String>
    ) -> [MediaSummary] {
        var seenSeries = excludingSeries
        var seenIDs = Set<String>()
        var result: [MediaSummary] = []
        for item in items where item.kind == .episode && !item.isInProgress {
            guard seenIDs.insert(item.id).inserted else { continue }
            if let series = item.seriesID, !seenSeries.insert(series).inserted { continue }
            result.append(item)
        }
        return result
    }

    private func recentlyAdded(_ context: PlexServerContext) async throws -> [MediaSummary] {
        let hubs = try await loadHubs(context)
        let wanted: Set<String> = ["movie", "show", "season", "episode"]
        var seen = Set<String>()
        let merged = hubs
            .filter { hub in
                guard let type = hub.type, wanted.contains(type) else { return false }
                return hub.id.localizedCaseInsensitiveContains("recent")
            }
            .flatMap(\.items)
            .filter { seen.insert($0.id).inserted }
        if merged.isEmpty {
            let container = try await fetch(
                context,
                endpoints.recentlyAdded(
                    base: context.baseURL, token: context.token, limit: Self.homeRowLimit))
            let kinds: Set<MediaKind> = [.film, .series, .season, .episode]
            return PlexLibraryMapping.summaries(container.items).filter { kinds.contains($0.kind) }
        }
        let sorted = merged.enumerated().sorted { lhs, rhs in
            switch (lhs.element.addedAt, rhs.element.addedAt) {
            case (let a?, let b?) where a != b: return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.offset < rhs.offset
            }
        }
        return sorted.map(\.element)
    }

    // MARK: hubs

    public func hubs() async throws -> [PlexHub] {
        let context = try await current()
        return try await loadHubs(context)
    }

    private func loadHubs(_ context: PlexServerContext) async throws -> [PlexHub] {
        let container = try await fetch(
            context, endpoints.hubs(base: context.baseURL, token: context.token, count: Self.hubCount))
        return container.hubs.map { hub in
            PlexHub(
                id: hub.hubIdentifier ?? hub.key ?? hub.title ?? "", title: hub.title ?? "",
                type: hub.type, items: PlexLibraryMapping.summaries(hub.metadata ?? []))
        }
    }

    // MARK: metadata

    public func detail(ratingKey: String) async throws -> MediaDetail {
        try await loadDetail(ratingKey, forPlayback: false)
    }

    /// Like `detail`, with `checkFiles=1` so the server confirms each file is reachable. Only the
    /// player calls this, just before play.
    public func detailForPlayback(ratingKey: String) async throws -> MediaDetail {
        try await loadDetail(ratingKey, forPlayback: true)
    }

    private func loadDetail(_ ratingKey: String, forPlayback: Bool) async throws -> MediaDetail {
        let context = try await current()
        let container = try await fetch(
            context,
            endpoints.metadata(
                base: context.baseURL, token: context.token, ratingKey: ratingKey,
                forPlayback: forPlayback))
        guard let item = container.metadata?.first, var detail = PlexLibraryMapping.detail(item) else {
            throw PlexError.decoding
        }
        if item.extras == nil {
            // No inline extras: ask the extras endpoint. Optional, so a failure leaves them empty.
            if let extras = try? await fetch(
                context,
                endpoints.extras(base: context.baseURL, token: context.token, ratingKey: ratingKey))
            {
                detail.extras = PlexLibraryMapping.extras(extras.items)
            }
        }
        try await ensureCurrent(context)
        return detail
    }

    /// Seasons of a series, or episodes of a season.
    public func children(of ratingKey: String) async throws -> [MediaSummary] {
        let context = try await current()
        let container = try await fetch(
            context, endpoints.children(base: context.baseURL, token: context.token, ratingKey: ratingKey))
        return PlexLibraryMapping.summaries(container.items)
    }

    public func allEpisodes(ofSeries seriesID: String) async throws -> [MediaSummary] {
        let context = try await current()
        let container = try await fetch(
            context, endpoints.allLeaves(base: context.baseURL, token: context.token, ratingKey: seriesID))
        return PlexLibraryMapping.summaries(container.items).filter { $0.kind == .episode }
    }

    /// The episode after `item` by season then episode number. Specials (season 0) are never a
    /// next episode for a regular season (approach from Dusk, MIT). Nil at the end of the series.
    public func nextEpisode(after item: MediaSummary) async throws -> MediaSummary? {
        guard let seriesID = item.seriesID, let season = item.seasonNumber,
            let number = item.episodeNumber
        else { return nil }
        let episodes = try await allEpisodes(ofSeries: seriesID)
        return episodes
            .compactMap { episode -> (episode: MediaSummary, season: Int, number: Int)? in
                guard let s = episode.seasonNumber, let n = episode.episodeNumber else { return nil }
                return (episode, s, n)
            }
            .filter { season == 0 || $0.season > 0 }
            .filter { ($0.season, $0.number) > (season, number) }
            .min { ($0.season, $0.number) < ($1.season, $1.number) }?
            .episode
    }

    // MARK: watched state

    public func markWatched(_ itemID: String) async throws {
        try await setWatched(true, itemID: itemID)
    }

    public func markUnwatched(_ itemID: String) async throws {
        try await setWatched(false, itemID: itemID)
    }

    private func setWatched(_ watched: Bool, itemID: String) async throws {
        let context = try await current()
        try await authorisePlay(context, entity: itemID)
        recordToggle(watched, itemID: itemID, key: RowsKey(context))
        do {
            try await watchState.setWatched(watched, itemID: itemID, context: context)
        } catch {
            refreshInBackground()
            throw error
        }
        refreshInBackground()
    }

    /// Puts the resume point back (the live check restores an item after a simulated playback).
    /// Authorised like playback.
    public func restoreProgress(itemID: String, positionMs: Int) async throws {
        let context = try await current()
        try await authorisePlay(context, entity: itemID)
        try await watchState.restoreProgress(itemID: itemID, positionMs: positionMs, context: context)
    }

    private func recordToggle(_ watched: Bool, itemID: String, key: RowsKey) {
        toggleCounts[itemID, default: 0] += 1
        localWatched[itemID] = watched
        if var changed = rows[key] ?? snapshots.read(profileID: key.profileID, machineID: key.machineID) {
            changed.apply(watched: watched, itemID: itemID)
            store(changed, for: key, keepInMemory: rows[key] != nil)
        }
    }

    /// Writes changed rows through to the snapshot, so a cached read agrees with memory at once.
    private func store(_ changed: PlexHomeRows, for key: RowsKey, keepInMemory: Bool) {
        if keepInMemory { rows[key] = changed }
        snapshots.write(changed, profileID: key.profileID, machineID: key.machineID)
    }

    /// Reconciles with the server after a toggle. A fetch already running started before the toggle,
    /// so wait for it and start a new one.
    private func refreshInBackground() {
        let previous = refreshTask
        refreshTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await self.refreshAfterToggle()
        }
    }

    private func refreshAfterToggle() async {
        if let running = flight?.task { _ = try? await running.value }
        guard let context = try? await current() else { return }
        _ = try? await startFetch(context)
    }

    /// The in-memory rows for the active profile (for tests).
    func currentRows() -> PlexHomeRows? { activeKey.flatMap { rows[$0] } }

    /// Returns when the background refresh after the latest toggle has finished (for tests).
    func settle() async {
        while let task = refreshTask {
            await task.value
            if refreshTask == task { break }
        }
    }

    // MARK: playback

    public func startPlayback(item: MediaSummary, sessionID: String?) async throws
        -> PlexPlaybackReporter
    {
        let context = try await current()
        try await authorisePlay(context, entity: item.id)
        playbackItems[item.id] = item
        return PlexPlaybackReporter(
            itemID: item.id, durationMs: item.durationMs, sessionID: sessionID, context: context,
            contextSource: contextSource, transport: transport, endpoints: endpoints,
            watchState: watchState, sink: self)
    }

    // MARK: PlexWatchStateSink

    func playbackProgressed(_ progress: PlaybackProgress, generation: UInt64) async {
        guard await contextSource.currentGeneration() == generation, let key = activeKey,
            activeGeneration == generation, var current = rows[key],
            progress.positionMs > 0
        else { return }
        let itemID = progress.itemID
        func setOffset(_ row: inout MediaRow) {
            for index in row.items.indices where row.items[index].id == itemID {
                row.items[index].viewOffsetMs = progress.positionMs
                if row.items[index].durationMs == nil { row.items[index].durationMs = progress.durationMs }
            }
        }
        if let index = current.continueWatching.items.firstIndex(where: { $0.id == itemID }) {
            current.continueWatching.items[index].viewOffsetMs = progress.positionMs
        } else {
            let known =
                (current.upNext.items + current.recentlyAdded.items).first { $0.id == itemID }
                ?? playbackItems[itemID]
            guard var summary = known else { return }
            summary.viewOffsetMs = progress.positionMs
            if summary.durationMs == nil { summary.durationMs = progress.durationMs }
            current.continueWatching.items.insert(summary, at: 0)
            current.continueWatching.items = Array(
                current.continueWatching.items.prefix(Self.homeRowLimit))
            // The series now has an item in progress, so it leaves Up next.
            if let series = summary.seriesID {
                current.upNext.items.removeAll { $0.seriesID == series || $0.id == itemID }
            }
        }
        setOffset(&current.recentlyAdded)
        setOffset(&current.upNext)
        store(current, for: key, keepInMemory: true)
    }

    func watchStateChanged(itemID: String, watched: Bool, generation: UInt64) async {
        guard await contextSource.currentGeneration() == generation, let key = activeKey,
            activeGeneration == generation
        else { return }
        recordToggle(watched, itemID: itemID, key: key)
    }

    // MARK: session

    /// Follows the session: sign-out deletes every snapshot and clears memory; a different profile or
    /// server clears memory only (snapshots stay, one per profile). The first state seen as signed
    /// out at launch does not delete anything, since `resume()` has not run yet.
    public func observe(_ session: PlexSession) async {
        observeTask?.cancel()
        let stream = await session.updates()
        // Read the state now, so a sign-out right after this call is still seen as one.
        sessionChanged(await session.snapshot().state)
        observeTask = Task { [weak self] in
            for await snapshot in stream {
                guard let self else { return }
                await self.sessionChanged(snapshot.state)
            }
        }
    }

    func sessionChanged(_ state: PlexSessionState) {
        defer { if case .signedOut = state { lastWasSignedOut = true } else { lastWasSignedOut = false } }
        switch state {
        case .ready(let profile, let server):
            let key = RowsKey(profileID: profile.id.rawValue, machineID: server.machineID)
            if let lastReadyKey, lastReadyKey != key { clearMemory() }
            lastReadyKey = key
            // A snapshot from another server is not shown once this one is ready.
            if let owner = snapshots.machineID(profileID: key.profileID), owner != key.machineID {
                snapshots.delete(profileID: key.profileID)
            }
        case .signedOut:
            // The first state seen at launch does not wipe: `resume()` has not run yet. Any later
            // change into signed out does, whatever state came before.
            guard lastWasSignedOut == false else { return }
            snapshots.deleteAll()
            clearMemory()
            lastReadyKey = nil
        case .connecting, .serverUnreachable:
            break
        }
    }

    private func clearMemory() {
        rows.removeAll()
        flight?.task.cancel()
        flight = nil
        toggleCounts.removeAll()
        localWatched.removeAll()
        playbackItems.removeAll()
        activeKey = nil
        activeGeneration = nil
    }

    // MARK: internals

    private func current() async throws -> PlexServerContext {
        let context = try await contextSource.libraryContext()
        activeKey = RowsKey(context)
        activeGeneration = context.generation
        return context
    }

    /// A missing profile, or any decision but allowed or limited, throws `notAllowed` before a request.
    private func authorisePlay(_ context: PlexServerContext, entity: String) async throws {
        guard
            let profile = await settings.document.profiles[PlexUserID(context.profileID)]
        else { throw PlexError.notAllowed }
        let decision = await authoriser.authorise(
            .play, context: profile.permissionContext(isPINFresh: false), entity: entity)
        guard decision == .allowed || decision == .limited else { throw PlexError.notAllowed }
    }

    private func ensureCurrent(_ context: PlexServerContext) async throws {
        guard await contextSource.currentGeneration() == context.generation else {
            throw CancellationError()
        }
    }

    /// One request with the context's token. Throws `CancellationError` when the context went stale.
    private func fetch(_ context: PlexServerContext, _ request: URLRequest) async throws
        -> PlexWireContainer
    {
        let data = try await transport.perform(request, host: .server)
        try await ensureCurrent(context)
        return try PlexWireContainer.decode(from: data)
    }
}
