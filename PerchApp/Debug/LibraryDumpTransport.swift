#if DEBUG
import Foundation
import OSLog
import PerchPlex

/// DEBUG-only `-PerchLibraryDump`: writes the bodies of server library answers (`/library/...`,
/// `/hubs...`) to Caches/library-dump/, one file per path, so the live checks can compare the real
/// server's shapes with the fixtures. Never writes headers or tokens, and never touches plex.tv.
struct LibraryDumpTransport: PlexTransport {
    let base: any PlexTransport
    let directory: URL

    private static let log = Logger(subsystem: "com.robrolabs.perch", category: "core")

    static func wrapping(_ base: any PlexTransport, arguments: [String] = ProcessInfo.processInfo.arguments)
        -> any PlexTransport
    {
        guard arguments.contains("-PerchLibraryDump") else { return base }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = caches.appending(path: "library-dump", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        log.notice("Library dump folder: \(directory.path(percentEncoded: false), privacy: .public)")
        return LibraryDumpTransport(base: base, directory: directory)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let result = try await base.send(request)
        if let url = request.url, Self.isLibraryPath(url), !result.0.isEmpty, (200..<300).contains(result.1.statusCode) {
            let name = Self.fileName(for: url.path(percentEncoded: false))
            try? result.0.write(to: directory.appending(path: name, directoryHint: .notDirectory), options: .atomic)
        }
        return result
    }

    private static func isLibraryPath(_ url: URL) -> Bool {
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        if host == "plex.tv" || host.hasSuffix(".plex.tv") { return false }
        let path = url.path(percentEncoded: false)
        // Images come back as bytes, not library answers.
        if path.contains("/thumb/") || path.contains("/art/") { return false }
        return path.hasPrefix("/library/") || path == "/hubs" || path.hasPrefix("/hubs/")
    }

    /// "/library/metadata/2103" becomes "library_metadata_2103.json"; the query is not part of the name.
    static func fileName(for path: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let flat = path.split(separator: "/").joined(separator: "_")
        let safe = String(flat.unicodeScalars.map { allowed.contains($0) || $0 == "_" ? Character($0) : "-" })
        return (safe.isEmpty ? "root" : safe) + ".json"
    }
}
#endif
