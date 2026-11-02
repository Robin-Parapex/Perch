import Testing

@testable import PerchCore

struct PermissionRulesTests {
    let own = RoomRef(id: RoomID("own"), isShared: false)
    let other = RoomRef(id: RoomID("other"), isShared: false)
    let shared = RoomRef(id: RoomID("lounge"), isShared: true)

    func ctx(
        _ role: Role, fresh: Bool = false, ai: Bool = false, level: Int = 0, yir: Bool = true
    ) -> PermissionContext {
        PermissionContext(
            role: role, ownRooms: [RoomID("own")], isPINFresh: fresh, aiEnabled: ai, aiLevel: level,
            yearInReviewEnabled: yir)
    }

    @Test func lights() {
        #expect(PermissionMatrix.decide(.lightsAndScenes(other), in: ctx(.parent)) == .allowed)
        #expect(PermissionMatrix.decide(.lightsAndScenes(own), in: ctx(.teen)) == .allowed)
        #expect(PermissionMatrix.decide(.lightsAndScenes(shared), in: ctx(.teen)) == .allowed)
        #expect(PermissionMatrix.decide(.lightsAndScenes(other), in: ctx(.teen)) == .denied(.room))
        #expect(PermissionMatrix.decide(.lightsAndScenes(own), in: ctx(.kid)) == .allowed)
        #expect(PermissionMatrix.decide(.lightsAndScenes(shared), in: ctx(.kid)) == .denied(.room))
        #expect(PermissionMatrix.decide(.lightsAndScenes(other), in: ctx(.kid)) == .denied(.room))
    }

    @Test func blinds() {
        #expect(PermissionMatrix.decide(.blindsAmpInputs(other), in: ctx(.parent)) == .allowed)
        #expect(PermissionMatrix.decide(.blindsAmpInputs(shared), in: ctx(.teen)) == .allowed)
        #expect(PermissionMatrix.decide(.blindsAmpInputs(own), in: ctx(.teen)) == .denied(.room))
        #expect(PermissionMatrix.decide(.blindsAmpInputs(shared), in: ctx(.kid)) == .denied(.role))
    }

    @Test func askLevels() {
        #expect(PermissionMatrix.decide(.useAsk(level: 2), in: ctx(.parent, level: 2)) == .allowed)
        #expect(PermissionMatrix.decide(.useAsk(level: 3), in: ctx(.parent, level: 2)) == .denied(.aiLevel))
        #expect(PermissionMatrix.decide(.useAsk(level: 4), in: ctx(.parent, level: 4)) == .allowed)
        #expect(PermissionMatrix.decide(.useAsk(level: 1), in: ctx(.teen, ai: false, level: 4)) == .denied(.aiDisabled))
        #expect(PermissionMatrix.decide(.useAsk(level: 4), in: ctx(.teen, ai: true, level: 4)) == .denied(.aiLevel))
        #expect(PermissionMatrix.decide(.useAsk(level: 3), in: ctx(.teen, ai: true, level: 3)) == .allowed)
        #expect(PermissionMatrix.decide(.useAsk(level: 1), in: ctx(.kid, ai: true, level: 4)) == .denied(.role))
        #expect(PermissionMatrix.decide(.useAsk(level: 0), in: ctx(.parent, level: 4)) == .denied(.aiLevel))
        #expect(PermissionMatrix.decide(.useAsk(level: 5), in: ctx(.parent, level: 4)) == .denied(.aiLevel))
    }

    @Test func freshPIN() {
        for action in [CoreAction.unlockDoor, .alarm, .openAdmin] {
            #expect(PermissionMatrix.decide(action, in: ctx(.parent)) == .needsFreshPIN)
            #expect(PermissionMatrix.decide(action, in: ctx(.parent, fresh: true)) == .allowed)
            #expect(PermissionMatrix.decide(action, in: ctx(.teen, fresh: true)) == .denied(.role))
            #expect(PermissionMatrix.decide(action, in: ctx(.kid, fresh: true)) == .denied(.role))
        }
    }

    @Test func topShelfOnlyBrowses() {
        for action in CoreAction.representativeCases {
            let decision = PermissionMatrix.decide(action, in: ctx(.topShelf, fresh: true, ai: true, level: 4))
            if action == .browseLibrary {
                #expect(decision == .allowed)
            } else {
                #expect(decision == .denied(.role), "\(action.auditName)")
            }
        }
    }

    @Test func unknownModulePolicyDenied() {
        let none: ActionPolicy? = nil
        #expect(PermissionMatrix.decide(policy: none, in: ctx(.parent, fresh: true)) == .denied(.role))
    }

    @Test func kidYearInReview() {
        #expect(PermissionMatrix.decide(.yearInReview, in: ctx(.kid, yir: false)) == .denied(.disabledByParent))
        #expect(PermissionMatrix.decide(.yearInReview, in: ctx(.kid)) == .allowed)
        #expect(PermissionMatrix.decide(.yearInReview, in: ctx(.teen, yir: false)) == .allowed)
    }
}
