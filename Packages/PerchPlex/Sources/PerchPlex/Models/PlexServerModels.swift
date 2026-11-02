import Foundation

/// `GET {server}/identity`. Server calls wrap their payload in `MediaContainer`.
public struct PlexServerIdentity: Sendable, Equatable {
    public let machineIdentifier: String
    public let version: String?

    public init(machineIdentifier: String, version: String? = nil) {
        self.machineIdentifier = machineIdentifier
        self.version = version
    }

    public static func decode(from data: Data) throws -> PlexServerIdentity {
        struct Container: Decodable {
            let machineIdentifier: String
            let version: String?
        }
        struct Root: Decodable { let MediaContainer: Container }
        let container = try PlexJSON.decode(Root.self, from: data).MediaContainer
        return PlexServerIdentity(
            machineIdentifier: container.machineIdentifier, version: container.version)
    }
}

/// `GET {server}/library/sections`, reduced to a count for the "Connected, n libraries" line.
public struct PlexLibrarySummary: Sendable, Equatable {
    public let sectionCount: Int

    public init(sectionCount: Int) { self.sectionCount = sectionCount }

    public static func decode(from data: Data) throws -> PlexLibrarySummary {
        struct Section: Decodable {}
        struct Container: Decodable {
            let size: Int?
            let Directory: [Section]?
        }
        struct Root: Decodable { let MediaContainer: Container }
        let container = try PlexJSON.decode(Root.self, from: data).MediaContainer
        return PlexLibrarySummary(sectionCount: container.Directory?.count ?? container.size ?? 0)
    }
}

/// `GET {server}/library/recentlyAdded`, reduced to the unique `art` paths (backdrops).
public enum PlexArtList {
    public static func decode(from data: Data, limit: Int) throws -> [String] {
        struct Item: Decodable { let art: String? }
        struct Container: Decodable { let Metadata: [Item]? }
        struct Root: Decodable { let MediaContainer: Container }
        let items = try PlexJSON.decode(Root.self, from: data).MediaContainer.Metadata ?? []
        var seen = Set<String>()
        var paths: [String] = []
        for case let art? in items.map(\.art) where !art.isEmpty && seen.insert(art).inserted {
            paths.append(art)
            if paths.count >= limit { break }
        }
        return paths
    }
}
