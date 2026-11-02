/// Everything the matrix needs to know about the person and device asking.
public struct PermissionContext: Sendable, Equatable {
    public var role: Role
    public var plexUserID: PlexUserID?
    public var ownRooms: Set<RoomID>
    /// The Admin PIN was entered in the last 5 minutes on this device.
    public var isPINFresh: Bool
    public var aiEnabled: Bool
    public var aiLevel: Int
    public var yearInReviewEnabled: Bool

    public init(
        role: Role,
        plexUserID: PlexUserID? = nil,
        ownRooms: Set<RoomID> = [],
        isPINFresh: Bool = false,
        aiEnabled: Bool = false,
        aiLevel: Int = 0,
        yearInReviewEnabled: Bool = true
    ) {
        self.role = role
        self.plexUserID = plexUserID
        self.ownRooms = ownRooms
        self.isPINFresh = isPINFresh
        self.aiEnabled = aiEnabled
        self.aiLevel = aiLevel
        self.yearInReviewEnabled = yearInReviewEnabled
    }
}

public enum DenialReason: Sendable, Equatable {
    case role, room, aiDisabled, aiLevel, disabledByParent
}

public enum Decision: Sendable, Equatable {
    case allowed
    case limited
    case queued
    case needsPIN
    case needsFreshPIN
    case denied(DenialReason)

    /// True when the action may go ahead now (possibly reduced or queued).
    public var isAllowed: Bool {
        switch self {
        case .allowed, .limited, .queued: true
        case .needsPIN, .needsFreshPIN, .denied: false
        }
    }
}

/// The permission matrix from docs/PERMISSIONS.md. Fails closed.
public enum PermissionMatrix {
    /// The base table, before rooms, AI level and PIN freshness. Payloads are ignored.
    public static func policy(for action: CoreAction) -> ActionPolicy {
        switch action {
        case .browseLibrary:
            ActionPolicy(parent: .allow, teen: .allow, kid: .allow, topShelf: .allow)
        case .play, .seeDoorbellOverlay, .viewCameras, .lightsAndScenes, .yearInReview:
            ActionPolicy(parent: .allow, teen: .allow, kid: .allow)
        case .switchProfile:
            ActionPolicy(parent: .allow, teen: .allow, kid: .needsPIN)
        case .openSettings:
            ActionPolicy(parent: .allow, teen: .limited, kid: .needsPIN)
        case .openAdmin, .unlockDoor, .alarm:
            ActionPolicy(parent: .needsFreshPIN, teen: .deny, kid: .deny)
        case .requestTitle:
            ActionPolicy(parent: .allow, teen: .queued, kid: .queued)
        case .approveRequests:
            ActionPolicy(parent: .allow, teen: .deny, kid: .deny)
        case .viewCameraHistory, .blindsAmpInputs, .sendMessageToTV, .useAsk,
            .changeRowsAndCollections:
            ActionPolicy(parent: .allow, teen: .allow, kid: .deny)
        }
    }

    public static func decide(_ action: CoreAction, in context: PermissionContext) -> Decision {
        let base = decide(policy: policy(for: action), in: context)
        guard base == .allowed else { return base }
        let role = context.role

        switch action {
        case .lightsAndScenes(let room):
            switch role {
            case .parent: return .allowed
            case .teen:
                return room.isShared || context.ownRooms.contains(room.id)
                    ? .allowed : .denied(.room)
            case .kid:
                return context.ownRooms.contains(room.id) ? .allowed : .denied(.room)
            case .topShelf: return .denied(.role)
            }
        case .blindsAmpInputs(let room):
            switch role {
            case .parent: return .allowed
            case .teen: return room.isShared ? .allowed : .denied(.room)
            case .kid, .topShelf: return .denied(.role)
            }
        case .useAsk(let level):
            guard (1...4).contains(level) else { return .denied(.aiLevel) }
            switch role {
            case .parent:
                return level <= context.aiLevel ? .allowed : .denied(.aiLevel)
            case .teen:
                guard context.aiEnabled else { return .denied(.aiDisabled) }
                return level <= min(3, context.aiLevel) ? .allowed : .denied(.aiLevel)
            case .kid, .topShelf: return .denied(.role)
            }
        case .changeRowsAndCollections(let ownProfile):
            if role == .teen && !ownProfile { return .denied(.role) }
            return .allowed
        case .yearInReview:
            if role == .kid && !context.yearInReviewEnabled { return .denied(.disabledByParent) }
            return .allowed
        default:
            return .allowed
        }
    }

    /// Module actions: base mapping only, no payload rules.
    public static func decide(policy: ActionPolicy, in context: PermissionContext) -> Decision {
        switch policy.access(for: context.role) {
        case .deny: .denied(.role)
        case .needsFreshPIN: context.isPINFresh ? .allowed : .needsFreshPIN
        case .needsPIN: .needsPIN
        case .queued: .queued
        case .limited: .limited
        case .allow: .allowed
        }
    }

    /// An unknown module action (no policy) is denied.
    public static func decide(policy: ActionPolicy?, in context: PermissionContext) -> Decision {
        guard let policy else { return .denied(.role) }
        return decide(policy: policy, in: context)
    }
}
