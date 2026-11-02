import Foundation
import OSLog

public struct AuditEntry: Codable, Sendable, Equatable, Identifiable {
    public enum Outcome: String, Codable, Sendable {
        case allowed, denied, needsPIN, failed
    }

    public var id: UUID
    public var date: Date
    public var plexUserID: PlexUserID?
    public var role: Role
    public var action: String
    /// A caller-supplied name such as "lock.front_door". Never a secret.
    public var entity: String?
    public var outcome: Outcome

    public init(
        id: UUID = UUID(),
        date: Date,
        plexUserID: PlexUserID?,
        role: Role,
        action: String,
        entity: String?,
        outcome: Outcome
    ) {
        self.id = id
        self.date = date
        self.plexUserID = plexUserID
        self.role = role
        self.action = action
        self.entity = entity
        self.outcome = outcome
    }
}

/// Local log of privileged actions on this device (docs/PERMISSIONS.md).
/// Kept in the App Group defaults suite; the capacity keeps it far inside the tvOS budget.
public actor AuditLog {
    private let store: (any KeyValueStore)?
    private let key: String
    private let capacity: Int
    private let now: NowProvider
    private var items: [AuditEntry] = []  // oldest first
    private var loaded = false
    private static let logger = Logger(subsystem: "com.robrolabs.perch", category: "audit")

    /// Description of the last failed write, nil after a successful one. Never holds entry contents.
    public private(set) var lastPersistError: String?

    /// A nil store keeps the log in memory only.
    public init(
        store: (any KeyValueStore)?, key: String = "perch.audit.v1", capacity: Int = 500,
        now: @escaping NowProvider = { Date() }
    ) {
        self.store = store
        self.key = key
        self.capacity = max(1, capacity)
        self.now = now
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let store, let data = store.data(forKey: key) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([AuditEntry].self, from: data) {
            items = Array(decoded.suffix(capacity))
        } else {
            // Diagnostic copy only: keep the first 32 KB to stay inside the tvOS storage budget.
            store.set(data.prefix(32_768), forKey: key + ".corrupt")
            store.set(nil, forKey: key)
        }
    }

    public func record(
        action: String, entity: String?, context: PermissionContext, outcome: AuditEntry.Outcome
    ) {
        record(
            AuditEntry(
                date: now(), plexUserID: context.plexUserID, role: context.role,
                action: action, entity: entity, outcome: outcome))
    }

    public func record(_ entry: AuditEntry) {
        loadIfNeeded()
        var entry = entry
        entry.action = String(entry.action.prefix(80))
        entry.entity = entry.entity.map { String($0.prefix(120)) }
        items.append(entry)
        if items.count > capacity { items.removeFirst(items.count - capacity) }
        persist()
    }

    /// Newest first.
    public func entries() -> [AuditEntry] {
        loadIfNeeded()
        return items.reversed()
    }

    private func persist() {
        guard let store else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            store.set(try encoder.encode(items), forKey: key)
            lastPersistError = nil
        } catch {
            let description = String(describing: type(of: error)) + ": " + error.localizedDescription
            lastPersistError = description
            Self.logger.error("Audit log write failed: \(description, privacy: .public)")
        }
    }
}

/// Decides with the matrix and logs every privileged action.
public actor Authoriser {
    private let auditLog: AuditLog
    private let adminPIN: AdminPIN
    private let modulePolicies: @Sendable (ActionID) async -> ActionPolicy?

    public init(
        auditLog: AuditLog, adminPIN: AdminPIN,
        modulePolicies: @escaping @Sendable (ActionID) async -> ActionPolicy?
    ) {
        self.auditLog = auditLog
        self.adminPIN = adminPIN
        self.modulePolicies = modulePolicies
    }

    private static func outcome(_ decision: Decision) -> AuditEntry.Outcome {
        switch decision {
        case .allowed, .limited, .queued: .allowed
        case .needsPIN, .needsFreshPIN: .needsPIN
        case .denied: .denied
        }
    }

    /// PIN freshness is decided here from the Admin PIN, never taken from the caller's context.
    private func withFreshness(_ context: PermissionContext) async -> PermissionContext {
        var copy = context
        copy.isPINFresh = await adminPIN.isFresh()
        return copy
    }

    public func authorise(
        _ action: CoreAction, context: PermissionContext, entity: String? = nil
    ) async -> Decision {
        let context = await withFreshness(context)
        let decision = PermissionMatrix.decide(action, in: context)
        if action.isPrivileged {
            await auditLog.record(
                action: action.auditName, entity: entity, context: context,
                outcome: Self.outcome(decision))
        }
        return decision
    }

    /// Unknown actions are denied and always audited; known ones when their policy is privileged.
    public func authorise(
        moduleAction: ActionID, context: PermissionContext, entity: String? = nil
    ) async -> Decision {
        let context = await withFreshness(context)
        let policy = await modulePolicies(moduleAction)
        let decision = PermissionMatrix.decide(policy: policy, in: context)
        if policy == nil || policy?.isPrivileged == true {
            await auditLog.record(
                action: moduleAction.rawValue, entity: entity, context: context,
                outcome: Self.outcome(decision))
        }
        return decision
    }

    public func recordAdminChange(_ description: String, context: PermissionContext) async {
        await auditLog.record(
            action: "core.adminChange", entity: description, context: context, outcome: .allowed)
    }

    /// A privileged call that was allowed but then failed at the device.
    public func recordFailure(action: String, entity: String?, context: PermissionContext) async {
        await auditLog.record(action: action, entity: entity, context: context, outcome: .failed)
    }
}
