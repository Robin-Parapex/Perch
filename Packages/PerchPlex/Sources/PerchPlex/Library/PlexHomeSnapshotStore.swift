import Foundation
import OSLog
import Synchronization

/// One JSON file per profile holding the last good Home rows, so Home can draw with no spinner at
/// launch. The directory is purgeable (the app passes the App Group Caches directory), so every read
/// error means "no snapshot", never a crash. Light fields only, at most `maxItemsPerRow` per row.
///
/// A profile only ever reads its own file: the file name comes from the profile id and the id is
/// stored inside and checked on read. Top Shelf (WP-17) never reads these files.
public final class PlexHomeSnapshotStore: Sendable {
    public static let maxItemsPerRow = 40

    private struct Stored: Codable {
        var profileID: String
        var machineID: String
        var written: Date
        var rows: PlexHomeRows
    }

    private let directory: URL
    private let cache = Mutex<[String: Stored]>([:])
    private static let log = Logger(subsystem: "com.robrolabs.perch", category: "plex")

    public init(directory: URL) {
        self.directory = directory
    }

    /// The rows last written for this profile, or nil. Synchronous; memory first, then the file.
    public func read(profileID: String) -> PlexHomeRows? {
        stored(profileID: profileID)?.rows
    }

    /// The server the snapshot was taken from, for callers that want to ignore another server's rows.
    func machineID(profileID: String) -> String? {
        stored(profileID: profileID)?.machineID
    }

    public func write(_ rows: PlexHomeRows, profileID: String, machineID: String) {
        let entry = Stored(
            profileID: profileID, machineID: machineID, written: Date(),
            rows: rows.capped(to: Self.maxItemsPerRow))
        let url = fileURL(profileID: profileID)
        cache.withLock { cache in
            cache[profileID] = entry
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Self.encoder().encode(entry).write(to: url, options: .atomic)
            } catch {
                Self.log.error("Home snapshot write failed")
            }
        }
    }

    /// Removes every profile's snapshot (sign-out).
    public func deleteAll() {
        cache.withLock { cache in
            cache.removeAll()
            let files =
                (try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where Self.isSnapshotFile(file) { try? FileManager.default.removeItem(at: file) }
        }
    }

    // MARK: internals

    private func stored(profileID: String) -> Stored? {
        let url = fileURL(profileID: profileID)
        return cache.withLock { cache in
            if let hit = cache[profileID] { return hit }
            guard let data = try? Data(contentsOf: url),
                let entry = try? Self.decoder().decode(Stored.self, from: data),
                entry.profileID == profileID
            else { return nil }
            cache[profileID] = entry
            return entry
        }
    }

    private func fileURL(profileID: String) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let safe = String(
            profileID.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return directory.appending(path: "home-\(safe).json", directoryHint: .notDirectory)
    }

    private static func isSnapshotFile(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix("home-") && url.pathExtension == "json"
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
