import Foundation

public enum SettingsError: Error, Equatable {
    case corrupt
    case tooLarge(bytes: Int)
    case secretLikeConfigKey(module: ModuleID, key: String)
}

/// Per-person settings, keyed by Plex user ID. No secrets (they live in the Keychain).
public struct ProfileSettings: Codable, Sendable, Equatable {
    public var plexUserID: PlexUserID
    public var displayName: String
    public var role: Role
    public var seerrUserID: Int?
    public var rooms: [RoomID]
    public var plexRestriction: PlexRestriction
    public var ceilingOverride: RatingCeiling?
    public var pinRequiredToExit: Bool
    public var aiEnabled: Bool
    public var aiLevel: Int
    public var yearInReviewEnabled: Bool

    public init(
        plexUserID: PlexUserID,
        displayName: String = "",
        role: Role = .kid,
        seerrUserID: Int? = nil,
        rooms: [RoomID] = [],
        plexRestriction: PlexRestriction = .custom(allowedRatings: []),
        ceilingOverride: RatingCeiling? = nil,
        pinRequiredToExit: Bool = false,
        aiEnabled: Bool = false,
        aiLevel: Int = 0,
        yearInReviewEnabled: Bool = true
    ) {
        self.plexUserID = plexUserID
        self.displayName = displayName
        self.role = role
        self.seerrUserID = seerrUserID
        self.rooms = rooms
        self.plexRestriction = plexRestriction
        self.ceilingOverride = ceilingOverride
        self.pinRequiredToExit = pinRequiredToExit
        self.aiEnabled = aiEnabled
        self.aiLevel = aiLevel
        self.yearInReviewEnabled = yearInReviewEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case plexUserID, displayName, role, seerrUserID, rooms, plexRestriction, ceilingOverride
        case pinRequiredToExit, aiEnabled, aiLevel, yearInReviewEnabled
    }

    /// Tolerant: only the Plex user ID is required; missing fields fail safe (kid, U).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plexUserID = try c.decode(PlexUserID.self, forKey: .plexUserID)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        role = try c.decodeIfPresent(Role.self, forKey: .role) ?? .kid
        seerrUserID = try c.decodeIfPresent(Int.self, forKey: .seerrUserID)
        rooms = try c.decodeIfPresent([RoomID].self, forKey: .rooms) ?? []
        plexRestriction =
            try c.decodeIfPresent(PlexRestriction.self, forKey: .plexRestriction)
            ?? .custom(allowedRatings: [])
        ceilingOverride = try c.decodeIfPresent(RatingCeiling.self, forKey: .ceilingOverride)
        pinRequiredToExit = try c.decodeIfPresent(Bool.self, forKey: .pinRequiredToExit) ?? false
        aiEnabled = try c.decodeIfPresent(Bool.self, forKey: .aiEnabled) ?? false
        aiLevel = try c.decodeIfPresent(Int.self, forKey: .aiLevel) ?? 0
        yearInReviewEnabled =
            try c.decodeIfPresent(Bool.self, forKey: .yearInReviewEnabled) ?? true
    }

    /// Owner or unrestricted -> parent; any restricted user -> kid. Teen is by assignment only.
    public static func defaults(
        plexUserID: PlexUserID,
        displayName: String,
        isOwner: Bool,
        restriction: PlexRestriction
    ) -> ProfileSettings {
        let isParent = isOwner || restriction == .unrestricted
        return ProfileSettings(
            plexUserID: plexUserID,
            displayName: displayName,
            role: isParent ? .parent : .kid,
            plexRestriction: restriction,
            pinRequiredToExit: !isParent
        )
    }

    public var ceiling: RatingCeiling {
        RatingCeiling.effective(plex: plexRestriction, adminOverride: ceilingOverride)
    }

    /// Stores the lower of the value and what Plex allows; nil clears the override.
    public mutating func setCeilingOverride(_ value: RatingCeiling?) {
        guard let value else {
            ceilingOverride = nil
            return
        }
        ceilingOverride = min(value, RatingCeiling(plex: plexRestriction))
    }

    public func permissionContext(isPINFresh: Bool) -> PermissionContext {
        PermissionContext(
            role: role,
            plexUserID: plexUserID,
            ownRooms: Set(rooms),
            isPINFresh: isPINFresh,
            aiEnabled: aiEnabled,
            aiLevel: aiLevel,
            yearInReviewEnabled: yearInReviewEnabled
        )
    }
}

public struct ModuleSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// Non-secret configuration only (base URLs, names). Keys live in the Keychain.
    public var config: [String: String]

    public init(enabled: Bool = false, config: [String: String] = [:]) {
        self.enabled = enabled
        self.config = config
    }

    private enum CodingKeys: String, CodingKey { case enabled, config }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        config = try c.decodeIfPresent([String: String].self, forKey: .config) ?? [:]
    }
}

public struct HouseholdSettings: Codable, Sendable, Equatable {
    public var ownerPlexUserID: PlexUserID?

    public init(ownerPlexUserID: PlexUserID? = nil) {
        self.ownerPlexUserID = ownerPlexUserID
    }

    private enum CodingKeys: String, CodingKey { case ownerPlexUserID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ownerPlexUserID = try c.decodeIfPresent(PlexUserID.self, forKey: .ownerPlexUserID)
    }
}

public struct SettingsDocument: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var household: HouseholdSettings
    public var profiles: [PlexUserID: ProfileSettings]
    public var modules: [ModuleID: ModuleSettings]

    public init() {
        schemaVersion = Self.currentSchemaVersion
        household = HouseholdSettings()
        profiles = [:]
        modules = [:]
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, household, profiles, modules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion =
            try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        household = try c.decodeIfPresent(HouseholdSettings.self, forKey: .household) ?? HouseholdSettings()
        profiles =
            try c.decodeIfPresent([PlexUserID: ProfileSettings].self, forKey: .profiles) ?? [:]
        modules = try c.decodeIfPresent([ModuleID: ModuleSettings].self, forKey: .modules) ?? [:]
    }

    public var householdLowestCeiling: RatingCeiling {
        RatingCeiling.householdLowest(profiles.values.map(\.ceiling))
    }

    /// Guard so modules cannot slip secrets into the document.
    public func validate() throws {
        for (module, settings) in modules {
            for key in settings.config.keys {
                let lower = key.lowercased()
                if ["key", "token", "secret", "password"].contains(where: { lower.contains($0) }) {
                    throw SettingsError.secretLikeConfigKey(module: module, key: key)
                }
            }
        }
    }
}
