import Foundation

/// An event published by a module (or the core) and consumed by overlays and other listeners.
public struct PerchEvent: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case doorbell(cameraID: String?)
        case notice(title: String, message: String?)
        case titleReady(title: String, plexRatingKey: String?)
        case custom(name: String, payload: [String: String])
    }

    public let id: UUID
    public let date: Date
    public let source: ModuleID
    public let kind: Kind

    public init(id: UUID = UUID(), date: Date = Date(), source: ModuleID, kind: Kind) {
        self.id = id
        self.date = date
        self.source = source
        self.kind = kind
    }
}

/// In-process fan-out of events. Late subscribers get nothing that was published earlier.
public actor EventBus {
    private var continuations: [UUID: AsyncStream<PerchEvent>.Continuation] = [:]

    public init() {}

    public func publish(_ event: PerchEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    public func subscribe(bufferingNewest limit: Int = 32) -> AsyncStream<PerchEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<PerchEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(limit))
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.remove(id) }
        }
        return stream
    }

    public var subscriberCount: Int { continuations.count }

    private func remove(_ id: UUID) {
        continuations[id] = nil
    }
}
