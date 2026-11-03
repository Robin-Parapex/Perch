import PerchCore

/// One of the three Home rows Plex contributes. All three read the same snapshot and share one fetch
/// (`PlexLibrary.homeRows()`), so three providers asking at once make one round of requests.
struct PlexHomeRowProvider: RowProvider {
    let id: String
    let title: String
    let placement: RowPlacement
    let library: PlexLibrary

    func cachedRow(in context: RowContext) -> MediaRow? {
        library.cachedHomeRows(profileID: context.profileID)?.row(id: id)
    }

    func refreshRow(in context: RowContext) async throws -> MediaRow {
        let owned = try await library.ownedHomeRows()
        // A switch mid-flight: these are another profile's rows.
        guard owned.profileID == context.profileID else { throw CancellationError() }
        guard let row = owned.rows.row(id: id) else { throw PlexError.decoding }
        return row
    }
}
