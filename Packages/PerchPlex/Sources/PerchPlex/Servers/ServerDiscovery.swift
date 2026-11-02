import Foundation

/// A Plex server the account can reach, reduced to what Perch needs.
public struct PlexServer: Sendable, Equatable, Identifiable {
    public let name: String
    public let machineID: String
    public let owned: Bool
    public let connections: [PlexConnection]
    /// Per-server access token from plex.tv. Internal: only `PlexSession` holds tokens.
    let accessToken: String?

    public var id: String { machineID }

    public init(
        name: String, machineID: String, owned: Bool, connections: [PlexConnection],
        accessToken: String? = nil
    ) {
        self.name = name
        self.machineID = machineID
        self.owned = owned
        self.connections = connections
        self.accessToken = accessToken
    }

    init(resource: PlexResource) {
        self.init(
            name: resource.name, machineID: resource.clientIdentifier, owned: resource.owned,
            connections: resource.sortedConnections, accessToken: resource.accessToken)
    }

    /// True when a connection is on the home network ("This home" rather than "Away").
    public var hasLocalConnection: Bool { connections.contains { $0.tier == .local } }
}

/// plex.tv resources -> servers. Only resources that provide "server" are kept.
public struct ServerDiscovery: Sendable {
    private let transport: any PlexTransport
    private let endpoints: PlexEndpoints

    public init(transport: any PlexTransport, endpoints: PlexEndpoints) {
        self.transport = transport
        self.endpoints = endpoints
    }

    /// Owned servers first, then by name.
    public func servers(token: String) async throws -> [PlexServer] {
        let data = try await transport.perform(endpoints.resources(token: token), host: .plexTV)
        return try PlexResource.servers(from: data).map(PlexServer.init(resource:)).sorted {
            if $0.owned != $1.owned { return $0.owned }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
