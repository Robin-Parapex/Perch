import Foundation
import PerchCore

/// Response of `POST /api/v2/pins` and `GET /api/v2/pins/{id}`. `authToken` appears once linked.
public struct PlexPin: Codable, Sendable, Equatable {
    public let id: Int
    public let code: String
    public let authToken: String?
    public let expiresAt: Date?

    public init(id: Int, code: String, authToken: String? = nil, expiresAt: Date? = nil) {
        self.id = id
        self.code = code
        self.authToken = authToken
        self.expiresAt = expiresAt
    }
}

/// Response of `GET /api/v2/user`.
public struct PlexAccount: Codable, Sendable, Equatable {
    public let id: Int
    public let uuid: String
    public let username: String
    public let title: String
    public let authToken: String?
    public let hasPassword: Bool?
    public let protected: Bool?

    public init(
        id: Int, uuid: String, username: String, title: String,
        authToken: String? = nil, hasPassword: Bool? = nil, protected: Bool? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.username = username
        self.title = title
        self.authToken = authToken
        self.hasPassword = hasPassword
        self.protected = protected
    }

    enum CodingKeys: String, CodingKey {
        case id, uuid, username, title, authToken, hasPassword, protected
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try PlexLooseInt.decode(c, .id)
        uuid = try c.decode(String.self, forKey: .uuid)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? username
        authToken = try c.decodeIfPresent(String.self, forKey: .authToken)
        hasPassword = try c.decodeIfPresent(Bool.self, forKey: .hasPassword)
        protected = try c.decodeIfPresent(Bool.self, forKey: .protected)
    }
}

/// Reads a field that Plex sends as either a number or a string.
enum PlexLooseInt {
    static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> Int {
        if let value = try? c.decode(Int.self, forKey: key) { return value }
        let text = try c.decode(String.self, forKey: key)
        guard let value = Int(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Not an integer")
        }
        return value
    }
}

/// One entry of `GET /api/v2/home/users`. `id` is a number in some responses and a string in others.
public struct PlexHomeUser: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let uuid: String
    public let title: String
    public let username: String?
    public let thumb: String?
    public let admin: Bool
    public let guest: Bool
    public let restricted: Bool
    public let protected: Bool
    public let restrictionProfile: String?

    public init(
        id: String, uuid: String, title: String, username: String? = nil, thumb: String? = nil,
        admin: Bool = false, guest: Bool = false, restricted: Bool = false, protected: Bool = false,
        restrictionProfile: String? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.title = title
        self.username = username
        self.thumb = thumb
        self.admin = admin
        self.guest = guest
        self.restricted = restricted
        self.protected = protected
        self.restrictionProfile = restrictionProfile
    }

    enum CodingKeys: String, CodingKey {
        case id, uuid, title, username, thumb, admin, guest, restricted, protected, restrictionProfile
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = String(try PlexLooseInt.decode(c, .id))
        uuid = try c.decodeIfPresent(String.self, forKey: .uuid) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username)
        thumb = try c.decodeIfPresent(String.self, forKey: .thumb)
        admin = try c.decodeIfPresent(Bool.self, forKey: .admin) ?? false
        guest = try c.decodeIfPresent(Bool.self, forKey: .guest) ?? false
        restricted = try c.decodeIfPresent(Bool.self, forKey: .restricted) ?? false
        protected = try c.decodeIfPresent(Bool.self, forKey: .protected) ?? false
        let profile = try c.decodeIfPresent(String.self, forKey: .restrictionProfile)
        restrictionProfile = (profile?.isEmpty ?? true) ? nil : profile
    }

    public var displayName: String {
        for name in [title, username ?? ""] {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "Profile"
    }

    /// Plex is the source of truth; an unknown profile on a restricted user fails closed in PerchCore.
    public var restriction: PlexRestriction {
        // Fail closed: a named restriction profile means restricted even if the flag is false or missing.
        PlexRestriction(restricted: restricted || restrictionProfile != nil, restrictionProfile: restrictionProfile)
    }

    /// Accepts a bare array or an object wrapping the list under `users`.
    public static func decodeList(from data: Data) throws -> [PlexHomeUser] {
        struct Wrapper: Decodable { let users: [PlexHomeUser] }
        if let list = try? PlexJSON.decoder().decode([PlexHomeUser].self, from: data) { return list }
        return try PlexJSON.decode(Wrapper.self, from: data).users
    }
}

/// Response of the Home switch. Current plex.tv sends `authToken`; the legacy shape `authenticationToken`.
public struct PlexSwitchResult: Decodable, Sendable, Equatable {
    public let authToken: String

    enum CodingKeys: String, CodingKey { case authToken, authenticationToken }

    public init(authToken: String) { self.authToken = authToken }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let token = try c.decodeIfPresent(String.self, forKey: .authToken), !token.isEmpty {
            authToken = token
        } else if let token = try c.decodeIfPresent(String.self, forKey: .authenticationToken),
            !token.isEmpty
        {
            authToken = token
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.authToken, .init(codingPath: [], debugDescription: "No token"))
        }
    }

    /// The legacy switch endpoint answers in XML even when asked for JSON, so try JSON first and
    /// then the root element's `authenticationToken` attribute. Approach after Dusk (MIT).
    public static func decode(from data: Data) throws -> PlexSwitchResult {
        if let result = try? PlexJSON.decoder().decode(PlexSwitchResult.self, from: data) { return result }
        let reader = SwitchTokenReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        // The reader stops after the root element, so `parse()` reports false; the token decides.
        _ = parser.parse()
        guard let token = reader.token else { throw PlexError.decoding }
        return PlexSwitchResult(authToken: token)
    }
}

/// Reads the token attribute from the first XML element of a switch response.
private final class SwitchTokenReader: NSObject, XMLParserDelegate {
    private(set) var token: String?

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        guard token == nil else { return }
        token = [attributeDict["authenticationToken"], attributeDict["authToken"]]
            .compactMap { $0 }.first { !$0.isEmpty }
        parser.abortParsing()
    }
}
