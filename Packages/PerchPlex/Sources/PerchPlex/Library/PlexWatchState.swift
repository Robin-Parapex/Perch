import Foundation

/// Sends watched, unwatched and resume-point changes, and keeps a revision per item so a late read
/// cannot undo a newer toggle (approach from Swiftfin, MPL-2.0).
actor PlexWatchState {
    private let transport: any PlexTransport
    private let endpoints: PlexEndpoints
    private var revisionByItem: [String: Int] = [:]

    init(transport: any PlexTransport, endpoints: PlexEndpoints) {
        self.transport = transport
        self.endpoints = endpoints
    }

    /// Bumps the item's revision before anything is sent, so a read that started earlier is stale.
    func setWatched(_ watched: Bool, itemID: String, context: PlexServerContext) async throws {
        revisionByItem[itemID, default: 0] += 1
        let request =
            watched
            ? endpoints.scrobble(base: context.baseURL, token: context.token, ratingKey: itemID)
            : endpoints.unscrobble(base: context.baseURL, token: context.token, ratingKey: itemID)
        _ = try await transport.perform(request, host: .server)
    }

    /// Puts the resume point back without a timeline session (used by the live check).
    func restoreProgress(itemID: String, positionMs: Int, context: PlexServerContext) async throws {
        let request = endpoints.progress(
            base: context.baseURL, token: context.token, ratingKey: itemID, timeMs: positionMs)
        _ = try await transport.perform(request, host: .server)
    }

    /// 0 when the item has never been changed.
    func revision(of itemID: String) -> Int { revisionByItem[itemID] ?? 0 }

    func revisions() -> [String: Int] { revisionByItem }
}
