import Foundation

/// A small image cache in the app's Caches directory (WP-05 change C7), so avatars and the picker
/// backdrop still show when plex.tv or the server cannot be reached. Holds public artwork only, never tokens.
struct ImageDiskCache: Sendable {
    static let shared = ImageDiskCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "PerchImages", directoryHint: .isDirectory))

    let directory: URL

    private func file(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" ? String($0) : "_" }.joined()
        return directory.appending(path: safe + ".img")
    }

    func data(for key: String) -> Data? {
        try? Data(contentsOf: file(key))
    }

    func store(_ data: Data, for key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(key), options: .atomic)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
