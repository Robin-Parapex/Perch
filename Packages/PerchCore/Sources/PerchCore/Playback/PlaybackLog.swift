import Foundation

/// One line of the playback log, used for feedback reports (never holds secrets or URLs with queries).
public struct PlaybackLogEntry: Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable {
        case start, stop, failure
    }

    public var date: Date
    public var profileID: String?
    public var ratingKey: String
    public var title: String
    /// Nil when playback failed before a decision existed (logged as "unknown"). Older lines always carry it.
    public var method: PlaybackMethod?
    public var reasons: [String]
    public var notes: [String]
    public var engine: String
    public var outcome: Outcome
    public var positionMs: Int?
    public var startLatencyMs: Int?
    public var error: String?

    public init(
        date: Date = Date(), profileID: String? = nil, ratingKey: String, title: String,
        method: PlaybackMethod? = nil, reasons: [String] = [], notes: [String] = [],
        engine: String = "native", outcome: Outcome, positionMs: Int? = nil,
        startLatencyMs: Int? = nil, error: String? = nil
    ) {
        self.date = date
        self.profileID = profileID
        self.ratingKey = ratingKey
        self.title = title
        self.method = method
        self.reasons = reasons
        self.notes = notes
        self.engine = engine
        self.outcome = outcome
        self.positionMs = positionMs
        self.startLatencyMs = startLatencyMs
        self.error = error
    }
}

/// A JSON Lines file of recent playbacks, capped at `maxEntries` (newest kept).
public actor PlaybackLog {
    private let fileURL: URL
    private let maxEntries: Int
    private var cache: [PlaybackLogEntry]?

    public init(fileURL: URL, maxEntries: Int = 500) {
        self.fileURL = fileURL
        self.maxEntries = max(1, maxEntries)
    }

    public func append(_ entry: PlaybackLogEntry) async {
        var entry = entry
        entry.error = entry.error.map(Self.stripQueries)
        var all = load()
        all.append(entry)
        if all.count > maxEntries {
            all = Array(all.suffix(maxEntries))
        }
        cache = all
        write(all)
    }

    /// Oldest first, newest last. With a limit, the newest `limit` entries.
    public func entries(limit: Int? = nil) async -> [PlaybackLogEntry] {
        let all = load()
        guard let limit else { return all }
        return Array(all.suffix(max(0, limit)))
    }

    /// Human-readable lines for a feedback report, newest last.
    public func lastLines(_ n: Int) async -> String {
        load().suffix(max(0, n)).map(Self.line).joined(separator: "\n")
    }

    // MARK: storage

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func load() -> [PlaybackLogEntry] {
        if let cache { return cache }
        var result: [PlaybackLogEntry] = []
        if let data = try? Data(contentsOf: fileURL), let text = String(data: data, encoding: .utf8) {
            let decoder = Self.decoder()
            for line in text.split(separator: "\n") where !line.isEmpty {
                // A corrupt line is skipped, not fatal.
                if let entry = try? decoder.decode(PlaybackLogEntry.self, from: Data(line.utf8)) {
                    result.append(entry)
                }
            }
        }
        cache = result
        return result
    }

    private func write(_ all: [PlaybackLogEntry]) {
        let encoder = Self.encoder()
        var text = ""
        for entry in all {
            if let data = try? encoder.encode(entry), let line = String(data: data, encoding: .utf8) {
                text += line + "\n"
            }
        }
        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }

    // MARK: formatting

    /// Removes the query from any http(s) URL inside the text.
    static func stripQueries(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(https?://[^\s?#]*)\?[^\s]*"#, with: "$1", options: .regularExpression)
    }

    private static func line(_ e: PlaybackLogEntry) -> String {
        var parts = [
            ISO8601DateFormatter().string(from: e.date), e.outcome.rawValue, e.engine,
            e.method?.rawValue ?? "unknown", "\(e.title) (\(e.ratingKey))",
        ]
        if let p = e.profileID { parts.append("profile \(p)") }
        if let ms = e.positionMs { parts.append("at \(ms) ms") }
        if let ms = e.startLatencyMs { parts.append("started in \(ms) ms") }
        if !e.reasons.isEmpty { parts.append("because " + e.reasons.joined(separator: "; ")) }
        if !e.notes.isEmpty { parts.append("notes " + e.notes.joined(separator: "; ")) }
        if let err = e.error { parts.append("error " + err) }
        return parts.joined(separator: " | ")
    }
}
