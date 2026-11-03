import Foundation

/// How good a route to a server is. Connection tiers after Dusk ServerProbe (MIT).
public enum PlexConnectionTier: Int, Comparable, Sendable {
    case local = 0, remote, relay

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct PlexConnection: Decodable, Sendable, Equatable {
    public let `protocol`: String
    public let address: String
    public let port: Int
    public let uri: String
    public let local: Bool
    public let relay: Bool
    public let isIPv6: Bool

    public init(
        protocol proto: String, address: String, port: Int, uri: String,
        local: Bool, relay: Bool, isIPv6: Bool = false
    ) {
        self.protocol = proto
        self.address = address
        self.port = port
        self.uri = uri
        self.local = local
        self.relay = relay
        self.isIPv6 = isIPv6
    }

    enum CodingKeys: String, CodingKey {
        case `protocol`, address, port, uri, local, relay
        case isIPv6 = "IPv6"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        `protocol` = try c.decodeIfPresent(String.self, forKey: .protocol) ?? "http"
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 32400
        uri = try c.decode(String.self, forKey: .uri)
        local = try c.decodeIfPresent(Bool.self, forKey: .local) ?? false
        relay = try c.decodeIfPresent(Bool.self, forKey: .relay) ?? false
        isIPv6 = try c.decodeIfPresent(Bool.self, forKey: .isIPv6) ?? false
    }

    public var tier: PlexConnectionTier {
        if relay { return .relay }
        return local ? .local : .remote
    }

    public var url: URL? { URL(string: uri) }
}

/// An entry of `/api/v2/resources`. Only resources that provide "server" matter to Perch.
public struct PlexResource: Decodable, Sendable, Equatable, Identifiable {
    public let name: String
    public let clientIdentifier: String
    public let provides: String
    public let accessToken: String?
    public let owned: Bool
    public let connections: [PlexConnection]

    public var id: String { clientIdentifier }

    public init(
        name: String, clientIdentifier: String, provides: String, accessToken: String? = nil,
        owned: Bool = false, connections: [PlexConnection] = []
    ) {
        self.name = name
        self.clientIdentifier = clientIdentifier
        self.provides = provides
        self.accessToken = accessToken
        self.owned = owned
        self.connections = connections
    }

    enum CodingKeys: String, CodingKey {
        case name, clientIdentifier, provides, accessToken, owned, connections
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        clientIdentifier = try c.decode(String.self, forKey: .clientIdentifier)
        provides = try c.decodeIfPresent(String.self, forKey: .provides) ?? ""
        accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken)
        owned = try c.decodeIfPresent(Bool.self, forKey: .owned) ?? false
        connections = try c.decodeIfPresent([PlexConnection].self, forKey: .connections) ?? []
    }

    public var isServer: Bool {
        provides.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == "server" }
    }

    /// Connections best first: local, then remote, then relay; IPv4 before IPv6 within a tier,
    /// otherwise the order Plex gave.
    public var sortedConnections: [PlexConnection] {
        connections.enumerated().sorted { a, b in
            if a.element.tier != b.element.tier { return a.element.tier < b.element.tier }
            if a.element.isIPv6 != b.element.isIPv6 { return !a.element.isIPv6 }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Decodes the resources response and keeps only servers.
    public static func servers(from data: Data) throws -> [PlexResource] {
        try PlexJSON.decode([PlexResource].self, from: data).filter(\.isServer)
    }
}
