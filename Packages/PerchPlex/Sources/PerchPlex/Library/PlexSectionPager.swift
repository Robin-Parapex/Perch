import Foundation
import PerchCore

/// Pages one section's items with a single sort: 50 on the first page, then 100. The next offset is
/// the number of rows the server returned, not the number that decoded (so an item we drop never
/// shifts the window). Paging stops on an empty page or when the server's total is reached.
/// Approach from Dusk (MIT) and Swiftfin (MPL-2.0); nothing is copied.
///
/// The pager is bound to the session generation it was made under. If the profile or server changes
/// later, `nextPage()` throws `CancellationError` and returns nothing from the old profile.
public actor PlexSectionPager {
    static let firstPageSize = 50
    static let laterPageSize = 100

    private let sectionID: String
    private let sort: String?
    private let contextSource: any PlexServerContextProviding
    private let transport: any PlexTransport
    private let endpoints: PlexEndpoints

    /// Set for a query pager; nil for the legacy section-and-sort pager.
    private let query: PlexSectionQuery?

    /// The next row to ask for (rows the server has returned so far, plus the start offset).
    public private(set) var offset = 0
    private var total: Int?
    private var finished = false
    private let generation: UInt64

    init(
        sectionID: String, sort: String?, generation: UInt64, contextSource: any PlexServerContextProviding,
        transport: any PlexTransport, endpoints: PlexEndpoints
    ) {
        self.sectionID = sectionID
        self.sort = sort
        self.query = nil
        self.generation = generation
        self.contextSource = contextSource
        self.transport = transport
        self.endpoints = endpoints
    }

    /// Starts at `query.startOffset`. A rating filter that admits nothing finishes at once, with no request.
    init(
        query: PlexSectionQuery, generation: UInt64, contextSource: any PlexServerContextProviding,
        transport: any PlexTransport, endpoints: PlexEndpoints
    ) {
        self.sectionID = query.sectionID
        self.sort = query.sort?.value
        self.query = query
        self.generation = generation
        self.contextSource = contextSource
        self.transport = transport
        self.endpoints = endpoints
        self.offset = query.startOffset
        if query.admitsNothing {
            finished = true
            total = 0
        }
    }

    public var isFinished: Bool { finished }

    /// The server's total for the section, once a page has told us.
    public var totalCount: Int? { total }

    /// The next page, possibly empty at the end. An error leaves the position where it was.
    public func nextPage() async throws -> [MediaSummary] {
        guard !finished else { return [] }
        let context = try await contextSource.libraryContext()
        guard context.generation == generation else { throw CancellationError() }
        let start = offset
        let size = start == (query?.startOffset ?? 0) ? Self.firstPageSize : Self.laterPageSize
        let request: URLRequest
        if let query {
            request = endpoints.sectionItems(
                base: context.baseURL, token: context.token, query: query, start: start, size: size)
        } else {
            request = endpoints.sectionItems(
                base: context.baseURL, token: context.token, sectionID: sectionID, sort: sort,
                start: start, size: size)
        }
        let data = try await transport.perform(request, host: .server)
        guard await contextSource.currentGeneration() == context.generation else {
            throw CancellationError()
        }
        let container = try PlexWireContainer.decode(from: data)
        // A concurrent call may have moved on while this one waited.
        guard offset == start else { throw CancellationError() }
        let returned = container.rowCount
        if let reported = container.totalCount { total = reported }
        offset += returned
        if returned == 0 || (total.map { offset >= $0 } ?? false) { finished = true }
        return PlexLibraryMapping.summaries(container.items)
    }
}
