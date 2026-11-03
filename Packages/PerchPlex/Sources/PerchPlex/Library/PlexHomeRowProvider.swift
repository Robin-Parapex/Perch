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
        let rows = try await library.homeRows()
        guard let row = rows.row(id: id) else { throw PlexError.decoding }
        return row
    }
}
