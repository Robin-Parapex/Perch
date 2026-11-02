import Foundation

/// A Plex user ID (account owner or Plex Home user). Per-person data is keyed by this.
public struct PlexUserID: RawRepresentable, Hashable, Codable, CodingKeyRepresentable, Sendable,
    CustomStringConvertible, ExpressibleByStringLiteral
{
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }

    // Bare-string encoding plus CodingKeyRepresentable: `[PlexUserID: T]` serialises as a JSON object.
    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A module identifier: "plex", "seerr", "homeassistant", "ai", ...
public struct ModuleID: RawRepresentable, Hashable, Codable, CodingKeyRepresentable, Sendable,
    CustomStringConvertible, ExpressibleByStringLiteral
{
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A module-declared action ("seerr.request", "homeassistant.unlock"). Core actions use `CoreAction`.
public struct ActionID: RawRepresentable, Hashable, Codable, CodingKeyRepresentable, Sendable,
    CustomStringConvertible, ExpressibleByStringLiteral
{
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A room in the house (Home Assistant area). Profiles list the rooms they own.
public struct RoomID: RawRepresentable, Hashable, Codable, CodingKeyRepresentable, Sendable,
    CustomStringConvertible, ExpressibleByStringLiteral
{
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
