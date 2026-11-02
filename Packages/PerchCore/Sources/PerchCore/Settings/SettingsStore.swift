import Foundation

/// Reads and writes the settings document (no secrets) in the App Group defaults suite.
/// tvOS only guarantees about 500 KB of persistent local storage there (DECISIONS.md).
///
/// Storage budget: settings 150 KB + audit log about 175 KB (500 entries) + two ".corrupt"
/// diagnostic copies of 32 KB each (settings and audit) stays under 500 KB.
public actor SettingsStore {
    /// Refused above this size, well inside the tvOS budget.
    public static let maxBytes = 150_000
    /// Diagnostic ".corrupt" copies keep only this many leading bytes.
    static let maxCorruptCopyBytes = 32_768

    private let store: any KeyValueStore
    private let key: String
    private var cached: SettingsDocument?
    private var isCorrupt = false

    public init(store: any KeyValueStore, key: String = "perch.settings.v1") {
        self.store = store
        self.key = key
    }

    private static func makeEncoder(pretty: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Missing value gives an empty document; an undecodable one throws `.corrupt` and is left alone.
    @discardableResult
    public func load() throws -> SettingsDocument {
        guard let data = store.data(forKey: key) else {
            let empty = SettingsDocument()
            cached = empty
            return empty
        }
        do {
            let doc = try Self.makeDecoder().decode(SettingsDocument.self, from: data)
            cached = doc
            isCorrupt = false
            return doc
        } catch {
            isCorrupt = true
            throw SettingsError.corrupt
        }
    }

    /// Cached; loads lazily. If loading fails the in-memory default is used and the stored value is not touched.
    public var document: SettingsDocument {
        if let cached { return cached }
        let doc = (try? load()) ?? SettingsDocument()
        cached = doc
        return doc
    }

    public func save(_ doc: SettingsDocument) throws {
        if cached == nil { _ = try? load() }
        if isCorrupt { throw SettingsError.corrupt }
        try doc.validate()
        let data = try Self.makeEncoder(pretty: false).encode(doc)
        guard data.count <= Self.maxBytes else { throw SettingsError.tooLarge(bytes: data.count) }
        store.set(data, forKey: key)
        cached = doc
    }

    /// Keeps the bad bytes under "<key>.corrupt" (replacing an older copy) and starts empty.
    public func discardCorruptDocument() {
        if let bad = store.data(forKey: key) {
            store.set(bad.prefix(Self.maxCorruptCopyBytes), forKey: key + ".corrupt")
        }
        store.set(nil, forKey: key)
        isCorrupt = false
        cached = SettingsDocument()
    }

    public func update(_ body: @Sendable (inout SettingsDocument) -> Void) throws {
        var doc = document
        body(&doc)
        try save(doc)
    }

    /// The validated document, for configuring a second Apple TV. Keys are never in it.
    public func exportData() throws -> Data {
        let doc = document
        try doc.validate()
        return try Self.makeEncoder(pretty: true).encode(doc)
    }
}
