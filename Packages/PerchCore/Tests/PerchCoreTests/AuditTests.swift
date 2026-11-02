import Foundation
import Testing

@testable import PerchCore

@Suite struct AuditTests {
    static let parent = PermissionContext(role: .parent, plexUserID: "1")
    static let kid = PermissionContext(role: .kid, plexUserID: "2")

    @Test func recordsNewestFirst() async {
        let log = AuditLog(store: nil)
        await log.record(action: "a", entity: "e1", context: Self.parent, outcome: .allowed)
        await log.record(action: "b", entity: nil, context: Self.kid, outcome: .denied)
        let entries = await log.entries()
        #expect(entries.map(\.action) == ["b", "a"])
        #expect(entries[0].plexUserID == "2" && entries[0].role == .kid && entries[0].outcome == .denied)
        #expect(entries[1].entity == "e1")
    }

    @Test func usesInjectedClock() async {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        let log = AuditLog(store: nil, now: { fixed })
        await log.record(action: "a", entity: nil, context: Self.parent, outcome: .allowed)
        #expect(await log.entries().first?.date == fixed)
    }

    @Test func capacityDropsOldest() async {
        let log = AuditLog(store: nil, capacity: 3)
        for i in 1...5 {
            await log.record(action: "a\(i)", entity: nil, context: Self.parent, outcome: .allowed)
        }
        #expect(await log.entries().map(\.action) == ["a5", "a4", "a3"])
    }

    @Test func persistsAcrossInstances() async {
        let kv = InMemoryKeyValueStore()
        let first = AuditLog(store: kv)
        await first.record(action: "one", entity: "x", context: Self.parent, outcome: .allowed)
        await first.record(action: "two", entity: nil, context: Self.kid, outcome: .failed)
        let second = AuditLog(store: kv)
        let entries = await second.entries()
        #expect(entries.map(\.action) == ["two", "one"])
        await second.record(action: "three", entity: nil, context: Self.parent, outcome: .allowed)
        #expect(await AuditLog(store: kv).entries().count == 3)
    }

    @Test func corruptValueStartsEmptyAndIsKept() async {
        let kv = InMemoryKeyValueStore()
        let garbage = Data("garbage".utf8)
        kv.set(garbage, forKey: "perch.audit.v1")
        let log = AuditLog(store: kv)
        #expect(await log.entries().isEmpty)
        #expect(kv.data(forKey: "perch.audit.v1.corrupt") == garbage)
        await log.record(action: "a", entity: nil, context: Self.parent, outcome: .allowed)
        #expect(await AuditLog(store: kv).entries().count == 1)
        #expect(kv.data(forKey: "perch.audit.v1.corrupt") == garbage)
    }

    @Test func largeCorruptValueIsKeptTruncated() async {
        let kv = InMemoryKeyValueStore()
        kv.set(Data(repeating: UInt8(ascii: "x"), count: 100_000), forKey: "perch.audit.v1")
        let log = AuditLog(store: kv)
        #expect(await log.entries().isEmpty)
        #expect(kv.data(forKey: "perch.audit.v1.corrupt")?.count == 32_768)
    }

    @Test func truncatesLongActionAndEntity() async {
        let log = AuditLog(store: nil)
        await log.record(
            action: String(repeating: "a", count: 200), entity: String(repeating: "e", count: 300),
            context: Self.parent, outcome: .allowed)
        let entry = await log.entries()[0]
        #expect(entry.action.count == 80)
        #expect(entry.entity?.count == 120)
    }

    @Test func defaultCapacityIs500() async {
        let log = AuditLog(store: nil)
        for i in 1...505 {
            await log.record(action: "a\(i)", entity: nil, context: Self.parent, outcome: .allowed)
        }
        let entries = await log.entries()
        #expect(entries.count == 500)
        #expect(entries.first?.action == "a505" && entries.last?.action == "a6")
    }

    /// An Authoriser over a real AdminPIN with PIN "1234" set; module policies come from `policies`.
    static func makeAuth(
        log: AuditLog, policies: [ActionID: ActionPolicy] = [:]
    ) async throws -> (Authoriser, AdminPIN) {
        let pin = AdminPIN(
            secrets: InMemorySecretStore(), keyValues: InMemoryKeyValueStore(), plexVerifier: nil,
            ownerHasPlexPIN: false, hasher: PINHasher(iterations: 1_000))
        try await pin.setPerchPIN("1234")
        let auth = Authoriser(auditLog: log, adminPIN: pin, modulePolicies: { policies[$0] })
        return (auth, pin)
    }

    @Test func authoriserLogsPrivilegedCoreActions() async throws {
        let log = AuditLog(store: nil)
        let (auth, pin) = try await Self.makeAuth(log: log)
        let denied = await auth.authorise(.unlockDoor, context: Self.kid, entity: "lock.front_door")
        #expect(denied == .denied(.role))
        // The caller's claim of freshness is ignored while the Admin PIN is not fresh.
        var claimed = Self.parent
        claimed.isPINFresh = true
        #expect(await auth.authorise(.unlockDoor, context: claimed, entity: "lock.front_door") == .needsFreshPIN)
        #expect(await pin.verify("1234") == .accepted)
        #expect(await auth.authorise(.unlockDoor, context: Self.parent, entity: "lock.front_door") == .allowed)
        let entries = await log.entries()
        #expect(entries.count == 3)
        #expect(entries.map(\.outcome) == [.allowed, .needsPIN, .denied])
        #expect(entries.allSatisfy { $0.action == "core.unlockDoor" && $0.entity == "lock.front_door" })
        #expect(entries[2].role == .kid && entries[2].plexUserID == "2")
    }

    @Test func authoriserDoesNotLogNonPrivileged() async throws {
        let log = AuditLog(store: nil)
        let (auth, _) = try await Self.makeAuth(log: log)
        #expect(await auth.authorise(.play, context: Self.kid) == .allowed)
        #expect(await log.entries().isEmpty)
    }

    @Test func moduleActionLoggingFollowsPolicyPrivilege() async throws {
        let log = AuditLog(store: nil)
        let (auth, _) = try await Self.makeAuth(
            log: log,
            policies: [
                "ha.unlock": ActionPolicy(parent: .allow, teen: .deny, kid: .deny, isPrivileged: true),
                "ha.lights": ActionPolicy(parent: .allow, teen: .deny, kid: .deny),
            ])
        #expect(await auth.authorise(moduleAction: "ha.unlock", context: Self.parent, entity: "lock.back") == .allowed)
        #expect(await auth.authorise(moduleAction: "ha.lights", context: Self.parent) == .allowed)
        let entries = await log.entries()
        #expect(entries.count == 1)
        #expect(entries[0].action == "ha.unlock" && entries[0].entity == "lock.back" && entries[0].outcome == .allowed)
    }

    @Test func unknownModuleActionIsDeniedAndAlwaysLogged() async throws {
        let log = AuditLog(store: nil)
        let (auth, _) = try await Self.makeAuth(log: log)
        #expect(await auth.authorise(moduleAction: "x.unknown", context: Self.parent) == .denied(.role))
        #expect(await auth.authorise(moduleAction: "x.unknown", context: Self.parent) == .denied(.role))
        let entries = await log.entries()
        #expect(entries.count == 2 && entries.allSatisfy { $0.outcome == .denied && $0.action == "x.unknown" })
    }

    @Test func adminChangeAndFailure() async {
        let log = AuditLog(store: nil)
        let (auth, _) = try! await Self.makeAuth(log: log)
        await auth.recordAdminChange("Changed Sam's ceiling to PG", context: Self.parent)
        await auth.recordFailure(action: "core.unlockDoor", entity: "lock.front_door", context: Self.parent)
        let entries = await log.entries()
        #expect(entries[1].action == "core.adminChange")
        #expect(entries[1].entity == "Changed Sam's ceiling to PG" && entries[1].outcome == .allowed)
        #expect(entries[0].outcome == .failed && entries[0].action == "core.unlockDoor")
    }
}
