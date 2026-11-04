import Foundation
import PerchCore

/// Pure request builders. No I/O, no logging. Tokens are headers only; the one URL that carries
/// a secret is the Home switch (the documented `pin` query item), so callers must never log URLs.
/// Endpoint set after Dusk (MIT) and python-plexapi.
public struct PlexEndpoints: Sendable {
    public let identity: PlexClientIdentity

    public init(identity: PlexClientIdentity) {
        self.identity = identity
    }

    private func make(
        _ method: String, _ url: URL, token: String? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (key, value) in identity.headers(token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    private func url(_ string: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(string: string)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    // MARK: plex.tv

    public func createPin() -> URLRequest {
        make("POST", url("https://plex.tv/api/v2/pins", query: [.init(name: "strong", value: "false")]))
    }

    public func checkPin(id: Int) -> URLRequest {
        make("GET", url("https://plex.tv/api/v2/pins/\(id)"))
    }

    public func user(token: String) -> URLRequest {
        make("GET", url("https://plex.tv/api/v2/user"), token: token)
    }

    public func homeUsers(token: String) -> URLRequest {
        make("GET", url("https://plex.tv/api/v2/home/users"), token: token)
    }

    /// `pin` is a query item only when given (legacy endpoint, owner token).
    public func switchUser(id: String, pin: String?, ownerToken: String) -> URLRequest {
        var query: [URLQueryItem] = []
        if let pin, !pin.isEmpty { query.append(.init(name: "pin", value: pin)) }
        return make(
            "POST", url("https://plex.tv/api/home/users/\(id)/switch", query: query), token: ownerToken)
    }

    public func resources(token: String) -> URLRequest {
        make(
            "GET",
            url(
                "https://clients.plex.tv/api/v2/resources",
                query: [
                    .init(name: "includeHttps", value: "1"),
                    .init(name: "includeRelay", value: "1"),
                    .init(name: "includeIPv6", value: "1"),
                ]),
            token: token)
    }

    // MARK: server

    public func serverIdentity(base: URL, token: String? = nil) -> URLRequest {
        make("GET", base.appending(path: "identity"), token: token)
    }

    public func librarySections(base: URL, token: String) -> URLRequest {
        make("GET", base.appending(path: "library/sections"), token: token)
    }

    /// Newest items with their `art` paths, for backdrops. The token is a header, never a query item.
    public func recentlyAdded(base: URL, token: String, limit: Int) -> URLRequest {
        make(
            "GET",
            url(
                base.appending(path: "library/recentlyAdded").absoluteString,
                query: [
                    .init(name: "X-Plex-Container-Start", value: "0"),
                    .init(name: "X-Plex-Container-Size", value: String(max(1, limit))),
                ]),
            token: token)
    }

    /// A server image by path. Returns nil unless `path` is a plain absolute path on the server
    /// (no scheme, no host, no token in the query), so the token header can only go to `base`.
    public func image(base: URL, path: String, token: String) -> URLRequest? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("://"),
            let parts = URLComponents(string: path),
            !(parts.queryItems ?? []).contains(where: { $0.name.lowercased().contains("token") }),
            var target = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        target.path = parts.path
        target.percentEncodedQuery = parts.percentEncodedQuery
        target.fragment = nil
        guard let url = target.url else { return nil }
        var request = make("GET", url, token: token)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return request
    }

    /// A server-scaled image: `/photo/:/transcode` with the source path inside the encoded `url`
    /// value (a `?t=` version query stays inside it). Same path checks and header-only token as
    /// `image(base:path:token:)`, so nil for anything but a plain absolute server path.
    public func photoTranscode(base: URL, path: String, size: ArtworkSize, token: String) -> URLRequest? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("://"),
            let parts = URLComponents(string: path),
            !(parts.queryItems ?? []).contains(where: { $0.name.lowercased().contains("token") }),
            var target = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "?&=+#/:")
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        let pixels = size.pixelSize
        target.path = "/photo/:/transcode"
        target.percentEncodedQuery =
            "width=\(pixels.width)&height=\(pixels.height)&minSize=1&upscale=1&url=\(encoded)"
        target.fragment = nil
        guard let url = target.url else { return nil }
        var request = make("GET", url, token: token)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return request
    }
}
