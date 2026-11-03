import Foundation
import PerchCore

@testable import PerchPlex

let reporterContext = PlexServerContext(
    baseURL: URL(string: "http://plex.test:32400")!, token: "SECRET-TOKEN", profileID: "p1",
    machineID: "m1", generation: 1)

/// A context source whose generation the test moves.
actor FakeContextSource: PlexServerContextProviding {
    private(set) var generation: UInt64
    init(generation: UInt64 = 1) { self.generation = generation }
    func setGeneration(_ value: UInt64) { generation = value }
    func libraryContext() async throws -> PlexServerContext {
        var context = reporterContext
        context.generation = generation
        return context
    }
    func currentGeneration() async -> UInt64 { generation }
}

actor RecordingSink: PlexWatchStateSink {
    private(set) var progress: [PlaybackProgress] = []
    private(set) var watched: [(itemID: String, watched: Bool)] = []
    func playbackProgressed(_ progress: PlaybackProgress) async { self.progress.append(progress) }
    func watchStateChanged(itemID: String, watched: Bool) async {
        self.watched.append((itemID, watched))
    }
}

/// A sleep the test ticks by hand. Cancelling the sleeping task throws out of `sleep`.
actor TickGate {
    private var sleepers: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    var sleeping: Int { sleepers.count }

    func sleep() async throws {
        let id = UUID()
        try await withTaskCancellationHandler(
            operation: { try await self.park(id) },
            onCancel: { Task { await self.cancel(id) } })
    }

    private var cancelledEarly: Set<UUID> = []

    private func park(_ id: UUID) async throws {
        if cancelledEarly.remove(id) != nil { throw CancellationError() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sleepers.append((id, continuation))
        }
    }

    private func cancel(_ id: UUID) {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else {
            cancelledEarly.insert(id)
            return
        }
        sleepers.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    /// Wakes the oldest sleeper once.
    func tick() {
        guard !sleepers.isEmpty else { return }
        sleepers.removeFirst().continuation.resume()
    }

    func waitUntilSleeping() async {
        for _ in 0..<20_000 {
            if !sleepers.isEmpty { return }
            await Task.yield()
        }
    }
}

/// Records requests and holds each reply until released, so a test can pile reports up behind one.
actor GatedTransport: PlexTransport {
    private(set) var requests: [URLRequest] = []
    private var held: [CheckedContinuation<Void, Never>] = []
    private var holding: Bool

    init(holding: Bool) { self.holding = holding }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if holding { await withCheckedContinuation { held.append($0) } }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    /// Lets the oldest held reply through.
    func releaseOne() {
        guard !held.isEmpty else { return }
        held.removeFirst().resume()
    }

    func releaseAll() {
        holding = false
        let waiting = held
        held = []
        for continuation in waiting { continuation.resume() }
    }

    func waitForRequests(_ count: Int) async {
        for _ in 0..<20_000 {
            if requests.count >= count { return }
            await Task.yield()
        }
    }
}

extension URLRequest {
    func query(_ name: String) -> String? {
        URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}
