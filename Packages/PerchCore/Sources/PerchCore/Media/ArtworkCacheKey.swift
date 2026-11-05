import Foundation

/// Image cache keys (WP-08). Built from stable parts only, never from the request URL, so a change of
/// server address does not miss the cache and a token can never become part of a key.
public enum ArtworkCacheKey {
    /// `serverID|path|size` for a server image path.
    public static func server(serverID: String, path: String, size: ArtworkSize) -> String {
        "\(serverID)|\(path)|\(size.rawValue)"
    }

    /// `public|<url>` for a public absolute image address (plex.tv avatars). Only the `c` cache-buster is
    /// kept from the query (plex.tv changes it when the picture changes, so a new picture gets a new key);
    /// every other query item, the fragment and any credentials are dropped. Nil for anything not https.
    public static func publicImage(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == "https",
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let buster = parts.queryItems?.first { $0.name == "c" && !($0.value ?? "").isEmpty }
        parts.queryItems = buster.map { [$0] }
        parts.fragment = nil
        parts.user = nil
        parts.password = nil
        guard let bare = parts.string else { return nil }
        return "public|\(bare)"
    }
}

/// When the artwork caches must be emptied, and which server the cached images belong to (WP-08 review).
/// Pure: the app feeds it session states and acts on the answers.
///
/// - The server ID survives `connecting` and `serverUnreachable`, so cached art shows at launch, during a
///   profile switch and offline. It is persisted by the caller and cleared only by a sign-out.
/// - A sign-out clears, except the first state seen at launch (`resume()` has not run yet).
/// - The first ready server that differs from the one the cache was built for clears (a revoked token that
///   starts signed out, then a sign-in to another server).
public struct ArtworkCachePolicy: Sendable, Equatable {
    public enum SessionState: Sendable, Equatable {
        case signedOut
        case connecting
        case ready(serverID: String)
    }

    public private(set) var serverID: String?
    private var lastWasSignedOut: Bool?

    public init(savedServerID: String?) {
        serverID = savedServerID
    }

    /// Feeds one session state; true when the caches must be cleared now.
    public mutating func observe(_ state: SessionState) -> Bool {
        defer { lastWasSignedOut = state == .signedOut }
        switch state {
        case .signedOut:
            guard lastWasSignedOut == false else { return false }
            serverID = nil
            return true
        case .connecting:
            return false
        case .ready(let id):
            let changed = serverID != nil && serverID != id
            serverID = id
            return changed
        }
    }

    /// An explicit sign-out from the app: always clears.
    public mutating func signedOut() {
        serverID = nil
        lastWasSignedOut = true
    }
}
