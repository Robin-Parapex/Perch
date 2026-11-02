import Foundation

/// The `X-Plex-*` identity Perch presents to plex.tv and servers.
public struct PlexClientIdentity: Sendable, Equatable {
    public static let defaultsKey = "plex.clientIdentifier"

    public let clientIdentifier: String
    public let version: String

    public init(clientIdentifier: String, version: String) {
        self.clientIdentifier = clientIdentifier
        self.version = version
    }

    /// Generates the client identifier once and keeps it in `defaults` (the App Group suite in the app).
    public init(defaults: UserDefaults, bundle: Bundle = .main) {
        if let existing = defaults.string(forKey: Self.defaultsKey), !existing.isEmpty {
            clientIdentifier = existing
        } else {
            let fresh = UUID().uuidString
            defaults.set(fresh, forKey: Self.defaultsKey)
            clientIdentifier = fresh
        }
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Headers for a request. The token goes here and nowhere else, never in a URL.
    public func headers(token: String? = nil) -> [String: String] {
        var headers = [
            "Accept": "application/json",
            "X-Plex-Product": "Perch",
            "X-Plex-Platform": "tvOS",
            "X-Plex-Device": "Apple TV",
            "X-Plex-Device-Name": "Perch",
            "X-Plex-Version": version,
            "X-Plex-Client-Identifier": clientIdentifier,
        ]
        if let token, !token.isEmpty { headers["X-Plex-Token"] = token }
        return headers
    }
}
