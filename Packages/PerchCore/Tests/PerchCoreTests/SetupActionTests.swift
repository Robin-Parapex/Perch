import Testing

@testable import PerchCore

@Suite struct SetupActionTests {
    static let parent = PermissionContext(role: .parent, plexUserID: "1")
    static let kid = PermissionContext(role: .kid, plexUserID: "2")

    @Test func editSetupIsPrivilegedAndAudited() async throws {
        #expect(CoreAction.editSetup.isPrivileged)
        let log = AuditLog(store: nil)
        let (auth, pin) = try await AuditTests.makeAuth(log: log)

        #expect(await auth.authorise(.editSetup, context: Self.parent, entity: "setup.rerun") == .needsFreshPIN)
        #expect(await pin.verify("1234") == .accepted)
        #expect(await auth.authorise(.editSetup, context: Self.parent, entity: "setup.rerun") == .allowed)

        let entries = await log.entries()
        #expect(entries.map(\.outcome) == [.allowed, .needsPIN])
        #expect(entries.allSatisfy { $0.action == "core.editSetup" && $0.entity == "setup.rerun" })
    }

    @Test func aKidIsDeniedEvenWithAFreshPIN() async throws {
        let log = AuditLog(store: nil)
        let (auth, pin) = try await AuditTests.makeAuth(log: log)
        #expect(await pin.verify("1234") == .accepted)

        #expect(await auth.authorise(.editSetup, context: Self.kid) == .denied(.role))
        #expect(await log.entries().first?.outcome == .denied)
    }
}
