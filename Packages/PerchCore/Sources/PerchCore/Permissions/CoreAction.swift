/// A room plus whether it is a shared space (living room, kitchen) rather than someone's own.
public struct RoomRef: Hashable, Sendable {
    public let id: RoomID
    public let isShared: Bool

    public init(id: RoomID, isShared: Bool) {
        self.id = id
        self.isShared = isShared
    }
}

/// Every action PerchCore itself gates (docs/PERMISSIONS.md). Module actions use `ActionID`.
public enum CoreAction: Hashable, Sendable {
    case browseLibrary
    case play
    case switchProfile
    case openSettings
    case openAdmin
    case requestTitle
    case approveRequests
    case seeDoorbellOverlay
    case unlockDoor
    case viewCameras
    case viewCameraHistory
    case lightsAndScenes(RoomRef)
    case blindsAmpInputs(RoomRef)
    case alarm
    case sendMessageToTV
    case useAsk(level: Int)
    case changeRowsAndCollections(ownProfile: Bool)
    case yearInReview

    /// Actions that change the state of the house or the household's approvals.
    public var isPrivileged: Bool {
        switch self {
        case .unlockDoor, .alarm, .approveRequests, .openAdmin: true
        default: false
        }
    }

    /// Stable dotted name for the audit log. Payloads are not part of the name.
    public var auditName: String {
        switch self {
        case .browseLibrary: "core.browseLibrary"
        case .play: "core.play"
        case .switchProfile: "core.switchProfile"
        case .openSettings: "core.openSettings"
        case .openAdmin: "core.openAdmin"
        case .requestTitle: "core.requestTitle"
        case .approveRequests: "core.approveRequests"
        case .seeDoorbellOverlay: "core.seeDoorbellOverlay"
        case .unlockDoor: "core.unlockDoor"
        case .viewCameras: "core.viewCameras"
        case .viewCameraHistory: "core.viewCameraHistory"
        case .lightsAndScenes: "core.lightsAndScenes"
        case .blindsAmpInputs: "core.blindsAmpInputs"
        case .alarm: "core.alarm"
        case .sendMessageToTV: "core.sendMessageToTV"
        case .useAsk: "core.useAsk"
        case .changeRowsAndCollections: "core.changeRowsAndCollections"
        case .yearInReview: "core.yearInReview"
        }
    }

    /// One sample of every case, for tests that walk the whole matrix.
    public static var representativeCases: [CoreAction] {
        let room = RoomRef(id: RoomID("living-room"), isShared: true)
        return [
            .browseLibrary, .play, .switchProfile, .openSettings, .openAdmin, .requestTitle,
            .approveRequests, .seeDoorbellOverlay, .unlockDoor, .viewCameras, .viewCameraHistory,
            .lightsAndScenes(room), .blindsAmpInputs(room), .alarm, .sendMessageToTV,
            .useAsk(level: 1), .changeRowsAndCollections(ownProfile: true), .yearInReview,
        ]
    }
}
