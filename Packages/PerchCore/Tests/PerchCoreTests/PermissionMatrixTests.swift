import Testing

@testable import PerchCore

/// Expectations are written from the table in docs/PERMISSIONS.md, not from the implementation.
struct PermissionMatrixTests {
    // MARK: Fixtures

    static let own = RoomID("own-room")
    static let otherRoom = RoomRef(id: RoomID("other-room"), isShared: false)
    static let sharedRoom = RoomRef(id: RoomID("living-room"), isShared: true)
    static let ownRoom = RoomRef(id: own, isShared: false)

    static func context(
        _ role: Role, fresh: Bool = false, aiEnabled: Bool = true, aiLevel: Int = 3,
        yearInReview: Bool = true
    ) -> PermissionContext {
        PermissionContext(
            role: role, ownRooms: [own], isPINFresh: fresh, aiEnabled: aiEnabled,
            aiLevel: aiLevel, yearInReviewEnabled: yearInReview)
    }

    static func decide(_ action: CoreAction, _ role: Role, fresh: Bool = false) -> Decision {
        PermissionMatrix.decide(action, in: context(role, fresh: fresh))
    }

    static func isDenied(_ decision: Decision) -> Bool {
        if case .denied = decision { return true }
        return false
    }

    struct Cell: Sendable, CustomTestStringConvertible {
        let name: String
        let action: CoreAction
        let role: Role
        let fresh: Bool
        let expected: Decision
        var testDescription: String { "\(name) / \(role) / fresh=\(fresh)" }
    }

    static let denyRole = Decision.denied(.role)

    /// (row, action, parent, teen, kid) for a context where the PIN is not fresh.
    static let rows: [(String, CoreAction, Decision, Decision, Decision)] = [
        ("Browse library", .browseLibrary, .allowed, .allowed, .allowed),
        ("Play", .play, .allowed, .allowed, .allowed),
        ("Switch profile", .switchProfile, .allowed, .allowed, .needsPIN),
        ("Open Settings", .openSettings, .allowed, .limited, .needsPIN),
        ("Open Admin", .openAdmin, .needsFreshPIN, denyRole, denyRole),
        ("Edit setup", .editSetup, .needsFreshPIN, denyRole, denyRole),
        ("Request a title", .requestTitle, .allowed, .queued, .queued),
        ("Approve requests", .approveRequests, .allowed, denyRole, denyRole),
        ("Doorbell overlay", .seeDoorbellOverlay, .allowed, .allowed, .allowed),
        ("Unlock door", .unlockDoor, .needsFreshPIN, denyRole, denyRole),
        ("View cameras", .viewCameras, .allowed, .allowed, .allowed),
        ("Camera history", .viewCameraHistory, .allowed, .allowed, denyRole),
        ("Lights own room", .lightsAndScenes(ownRoom), .allowed, .allowed, .allowed),
        ("Lights shared room", .lightsAndScenes(sharedRoom), .allowed, .allowed, .denied(.room)),
        ("Blinds shared room", .blindsAmpInputs(sharedRoom), .allowed, .allowed, denyRole),
        ("Alarm", .alarm, .needsFreshPIN, denyRole, denyRole),
        ("Send messages to TV", .sendMessageToTV, .allowed, .allowed, denyRole),
        ("Use Ask level 1", .useAsk(level: 1), .allowed, .allowed, denyRole),
        ("Change rows own profile", .changeRowsAndCollections(ownProfile: true), .allowed, .allowed, denyRole),
        ("Year in review", .yearInReview, .allowed, .allowed, .allowed),
    ]

    static let cells: [Cell] = {
        var out: [Cell] = []
        for (name, action, parent, teen, kid) in rows {
            out.append(Cell(name: name, action: action, role: .parent, fresh: false, expected: parent))
            out.append(Cell(name: name, action: action, role: .teen, fresh: false, expected: teen))
            out.append(Cell(name: name, action: action, role: .kid, fresh: false, expected: kid))
        }
        // PIN-fresh variants.
        for (name, action) in [("Open Admin", CoreAction.openAdmin), ("Edit setup", .editSetup), ("Unlock door", .unlockDoor), ("Alarm", .alarm)] {
            out.append(Cell(name: name, action: action, role: .parent, fresh: true, expected: .allowed))
            out.append(Cell(name: name, action: action, role: .teen, fresh: true, expected: denyRole))
            out.append(Cell(name: name, action: action, role: .kid, fresh: true, expected: denyRole))
        }
        return out
    }()

    // MARK: Whole table

    @Test(arguments: cells)
    func matrixCell(_ cell: Cell) {
        #expect(Self.decide(cell.action, cell.role, fresh: cell.fresh) == cell.expected)
    }

    // MARK: Named "no" cells

    @Test func teenCannotOpenAdmin() {
        #expect(Self.isDenied(Self.decide(.openAdmin, .teen)))
    }
    @Test func kidCannotOpenAdmin() {
        #expect(Self.isDenied(Self.decide(.openAdmin, .kid)))
    }
    @Test func teenCannotOpenAdminEvenWithFreshPIN() {
        #expect(Self.isDenied(Self.decide(.openAdmin, .teen, fresh: true)))
    }
    @Test func kidCannotOpenAdminEvenWithFreshPIN() {
        #expect(Self.isDenied(Self.decide(.openAdmin, .kid, fresh: true)))
    }
    @Test func parentCannotOpenAdminWithoutFreshPIN() {
        #expect(!Self.decide(.openAdmin, .parent).isAllowed)
    }
    @Test func teenCannotApproveRequests() {
        #expect(Self.isDenied(Self.decide(.approveRequests, .teen)))
    }
    @Test func kidCannotApproveRequests() {
        #expect(Self.isDenied(Self.decide(.approveRequests, .kid)))
    }
    @Test func teenCannotUnlockDoor() {
        #expect(Self.isDenied(Self.decide(.unlockDoor, .teen)))
        #expect(Self.isDenied(Self.decide(.unlockDoor, .teen, fresh: true)))
    }
    @Test func kidCannotUnlockDoor() {
        #expect(Self.isDenied(Self.decide(.unlockDoor, .kid)))
        #expect(Self.isDenied(Self.decide(.unlockDoor, .kid, fresh: true)))
    }
    @Test func parentCannotUnlockDoorWithoutFreshPIN() {
        #expect(!Self.decide(.unlockDoor, .parent).isAllowed)
    }
    @Test func teenCannotUseAlarm() {
        #expect(Self.isDenied(Self.decide(.alarm, .teen)))
        #expect(Self.isDenied(Self.decide(.alarm, .teen, fresh: true)))
    }
    @Test func kidCannotUseAlarm() {
        #expect(Self.isDenied(Self.decide(.alarm, .kid)))
        #expect(Self.isDenied(Self.decide(.alarm, .kid, fresh: true)))
    }
    @Test func parentCannotUseAlarmWithoutFreshPIN() {
        #expect(!Self.decide(.alarm, .parent).isAllowed)
    }
    @Test func kidCannotViewCameraHistory() {
        #expect(Self.isDenied(Self.decide(.viewCameraHistory, .kid)))
    }
    @Test func kidCanViewCamerasLive() {
        #expect(Self.decide(.viewCameras, .kid) == .allowed)
    }
    @Test func kidCannotSendMessagesToTV() {
        #expect(Self.isDenied(Self.decide(.sendMessageToTV, .kid)))
    }
    @Test func kidCannotUseAsk() {
        for level in 1...4 {
            #expect(!PermissionMatrix.decide(.useAsk(level: level), in: Self.context(.kid, aiLevel: 4)).isAllowed)
        }
    }
    @Test func kidCannotChangeRowsOrCollections() {
        #expect(Self.isDenied(Self.decide(.changeRowsAndCollections(ownProfile: true), .kid)))
        #expect(Self.isDenied(Self.decide(.changeRowsAndCollections(ownProfile: false), .kid)))
    }
    @Test func teenCannotChangeAnotherProfilesRows() {
        #expect(Self.isDenied(Self.decide(.changeRowsAndCollections(ownProfile: false), .teen)))
    }
    @Test func teenCanChangeOwnProfileRows() {
        #expect(Self.decide(.changeRowsAndCollections(ownProfile: true), .teen) == .allowed)
    }
    @Test func kidNeedsPINToSwitchProfile() {
        #expect(Self.decide(.switchProfile, .kid) == .needsPIN)
        #expect(!Self.decide(.switchProfile, .kid).isAllowed)
    }
    @Test func kidNeedsPINToOpenSettings() {
        #expect(Self.decide(.openSettings, .kid) == .needsPIN)
        #expect(!Self.decide(.openSettings, .kid).isAllowed)
    }

    // MARK: Rooms

    @Test func kidCannotControlLightsInSharedRoom() {
        #expect(Self.isDenied(Self.decide(.lightsAndScenes(Self.sharedRoom), .kid)))
    }
    @Test func kidCannotControlLightsInOtherRoom() {
        #expect(Self.isDenied(Self.decide(.lightsAndScenes(Self.otherRoom), .kid)))
    }
    @Test func kidCanControlLightsInOwnRoom() {
        #expect(Self.decide(.lightsAndScenes(Self.ownRoom), .kid) == .allowed)
    }
    @Test func teenCannotControlLightsInAnotherNonSharedRoom() {
        #expect(Self.isDenied(Self.decide(.lightsAndScenes(Self.otherRoom), .teen)))
    }
    @Test func teenCanControlLightsInOwnAndSharedRooms() {
        #expect(Self.decide(.lightsAndScenes(Self.ownRoom), .teen) == .allowed)
        #expect(Self.decide(.lightsAndScenes(Self.sharedRoom), .teen) == .allowed)
    }
    @Test func parentCanControlLightsInAnyRoom() {
        #expect(Self.decide(.lightsAndScenes(Self.otherRoom), .parent) == .allowed)
        #expect(Self.decide(.lightsAndScenes(Self.sharedRoom), .parent) == .allowed)
    }
    @Test func teenCannotControlBlindsInNonSharedRoom() {
        #expect(Self.isDenied(Self.decide(.blindsAmpInputs(Self.otherRoom), .teen)))
        #expect(Self.isDenied(Self.decide(.blindsAmpInputs(Self.ownRoom), .teen)))
    }
    @Test func teenCanControlBlindsInSharedRoom() {
        #expect(Self.decide(.blindsAmpInputs(Self.sharedRoom), .teen) == .allowed)
    }
    @Test func kidCannotControlBlindsAnywhere() {
        for room in [Self.ownRoom, Self.otherRoom, Self.sharedRoom] {
            #expect(Self.isDenied(Self.decide(.blindsAmpInputs(room), .kid)))
        }
    }
    @Test func parentCanControlBlindsAnywhere() {
        for room in [Self.ownRoom, Self.otherRoom, Self.sharedRoom] {
            #expect(Self.decide(.blindsAmpInputs(room), .parent) == .allowed)
        }
    }

    // MARK: Ask

    @Test func teenCannotUseAskWhenNotEnabled() {
        let ctx = Self.context(.teen, aiEnabled: false, aiLevel: 3)
        #expect(PermissionMatrix.decide(.useAsk(level: 1), in: ctx).isAllowed == false)
        #expect(Self.isDenied(PermissionMatrix.decide(.useAsk(level: 1), in: ctx)))
    }
    @Test func teenCannotUseAskAboveLevel3EvenIfAdminLevelIs4() {
        let ctx = Self.context(.teen, aiEnabled: true, aiLevel: 4)
        #expect(Self.isDenied(PermissionMatrix.decide(.useAsk(level: 4), in: ctx)))
    }
    @Test func teenCanUseAskUpToLevel3WhenEnabled() {
        let ctx = Self.context(.teen, aiEnabled: true, aiLevel: 4)
        for level in 1...3 {
            #expect(PermissionMatrix.decide(.useAsk(level: level), in: ctx) == .allowed)
        }
    }
    @Test func parentAskFollowsLevelSetInAdmin() {
        let ctx = Self.context(.parent, aiLevel: 4)
        #expect(PermissionMatrix.decide(.useAsk(level: 4), in: ctx) == .allowed)
    }

    // MARK: Year in review

    @Test func kidCannotSeeYearInReviewWhenParentDisables() {
        let ctx = Self.context(.kid, yearInReview: false)
        #expect(Self.isDenied(PermissionMatrix.decide(.yearInReview, in: ctx)))
    }
    @Test func kidSeesYearInReviewByDefault() {
        #expect(PermissionMatrix.decide(.yearInReview, in: Self.context(.kid)) == .allowed)
    }

    // MARK: Top Shelf pseudo-role is read-only

    @Test func topShelfCanOnlyBrowse() {
        #expect(Self.decide(.browseLibrary, .topShelf) == .allowed)
        for (name, action, _, _, _) in Self.rows where name != "Browse library" {
            #expect(!Self.decide(action, .topShelf, fresh: true).isAllowed, "\(name)")
        }
    }
}
