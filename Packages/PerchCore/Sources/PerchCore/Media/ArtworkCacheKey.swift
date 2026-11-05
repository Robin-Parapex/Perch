import Foundation

/// Image cache keys (WP-08). Built from stable parts only, never from the request URL, so a change of
/// server address does not miss the cache and a token can never become part of a key.
public enum ArtworkCacheKey {
    /// `serverID|path|size` for a server image path.
    public static func server(serverID: String, path: String, size: ArtworkSize) -> String {
        "\(serverID)|\(path)|\(size.rawValue)"
    }

    /// `public|<url without query or fragment>` for a public absolute image address (plex.tv avatars).
    /// Nil for anything that is not https.
    public static func publicImage(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == "https",
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        parts.query = nil
        parts.fragment = nil
        parts.user = nil
        parts.password = nil
        guard let bare = parts.string else { return nil }
        return "public|\(bare)"
    }
}
