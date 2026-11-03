import Foundation
import Synchronization

/// The screens of the first-run wizard, in order (docs/notes/wp-05-plan.md).
public enum SetupStep: Int, CaseIterable, Sendable, Comparable {
    case welcome, connectPlex, chooseServer, adminPIN, profiles, addLater, done

    public static func < (lhs: SetupStep, rhs: SetupStep) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What Back does at the first step: first run leaves the app, a re-run returns home.
public enum SetupBackAtStart: Sendable, Equatable { case leaveApp, returnHome }

/// Pure model of where the wizard is and what it may do. No I/O: the screens feed it facts
/// (how many servers, the Admin PIN source, whether the Admin PIN was verified) and ask it questions.
public struct SetupProgress: Sendable, Equatable {
    public var serverCount: Int
    public var adminPINSource: AdminPINSource
    public let isRerun: Bool
    public private(set) var current: SetupStep
    /// True once the Admin PIN step verified a PIN during this run. Never persisted.
    public private(set) var adminPINVerified = false

    public init(
        serverCount: Int = 0, adminPINSource: AdminPINSource = .unavailable, isRerun: Bool = false,
        current: SetupStep = .welcome
    ) {
        self.serverCount = serverCount
        self.adminPINSource = adminPINSource
        self.isRerun = isRerun
        self.current = current
    }

    /// The steps that apply now, in order. Choose server only appears with more than one server.
    public var steps: [SetupStep] {
        SetupStep.allCases.filter { $0 != .chooseServer || serverCount > 1 }
    }

    public func next(after step: SetupStep) -> SetupStep? {
        steps.first { $0 > step }
    }

    public func previous(before step: SetupStep) -> SetupStep? {
        steps.last { $0 < step }
    }

    /// Connect Plex and the Admin PIN can never be skipped.
    public func canSkip(_ step: SetupStep) -> Bool {
        switch step {
        case .connectPlex, .adminPIN, .done: false
        default: true
        }
    }

    /// Setup can finish only with a working Admin PIN that was verified in this run.
    public var canFinish: Bool {
        switch adminPINSource {
        case .perch, .plexOwner: adminPINVerified
        case .setupRequired, .unavailable: false
        }
    }

    public mutating func markAdminPINVerified() { adminPINVerified = true }

    /// Forget the verification (for example when the Admin PIN source changes under the wizard).
    public mutating func resetAdminPINVerification() { adminPINVerified = false }

    /// Whether the Continue button may move on from `step`. Leaving the Admin PIN step needs the
    /// verification; reaching Done needs `canFinish`.
    public func canAdvance(from step: SetupStep) -> Bool {
        guard let target = next(after: step) else { return false }
        if step == .adminPIN && !canFinish { return false }
        if target == .done && !canFinish { return false }
        return true
    }

    /// Moves to the next step if allowed. Returns whether it moved.
    @discardableResult
    public mutating func advance() -> Bool {
        guard canAdvance(from: current), let target = next(after: current) else { return false }
        current = target
        return true
    }

    /// "Skip for now": like `advance()` but only on skippable steps.
    @discardableResult
    public mutating func skip() -> Bool {
        guard canSkip(current) else { return false }
        return advance()
    }

    /// Moves to the previous step. Returns false at the first step; then use `backAtStart`.
    @discardableResult
    public mutating func goBack() -> Bool {
        guard let target = previous(before: current) else { return false }
        current = target
        return true
    }

    public var backAtStart: SetupBackAtStart { isRerun ? .returnHome : .leaveApp }
}

/// One line on the "Add later" screen. Modules register theirs so later work packages plug in.
public struct AddLaterEntry: Sendable, Equatable, Identifiable {
    public let moduleID: ModuleID
    public let title: String
    public let detail: String
    /// Lower comes first; ties keep registration order.
    public let order: Int
    public var id: ModuleID { moduleID }

    public static let comingSoon = "Coming soon"

    public init(moduleID: ModuleID, title: String, detail: String = AddLaterEntry.comingSoon, order: Int = 100) {
        self.moduleID = moduleID
        self.title = title
        self.detail = detail
        self.order = order
    }
}

public final class AddLaterRegistry: Sendable {
    private let storage = Mutex<[AddLaterEntry]>([])

    public init() {}

    /// Registering the same module again replaces its entry.
    public func register(_ entry: AddLaterEntry) {
        storage.withLock { list in
            if let index = list.firstIndex(where: { $0.moduleID == entry.moduleID }) {
                list[index] = entry
            } else {
                list.append(entry)
            }
        }
    }

    public func entries() -> [AddLaterEntry] {
        let list = storage.withLock { $0 }
        return list.enumerated().sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
    }
}

/// The setup-complete flag, in the App Group defaults next to the other app-local keys.
public struct SetupCompletion: Sendable {
    public static let key = "perch.setupComplete"
    private let store: any KeyValueStore

    public init(store: any KeyValueStore) { self.store = store }

    public var isComplete: Bool { store.data(forKey: Self.key)?.first == 1 }

    public func setComplete(_ complete: Bool) {
        store.set(complete ? Data([1]) : nil, forKey: Self.key)
    }
}
