import Foundation

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
}
