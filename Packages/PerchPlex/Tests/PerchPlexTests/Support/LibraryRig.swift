import Foundation
import PerchCore

@testable import PerchPlex

/// Answers by URL path from a queue of steps (the last step repeats). A step can be held: the request
/// waits until the test releases that path, so a test can switch profile or toggle watched state while
/// a fetch is in flight. Unscripted paths answer 404. Records every request.
actor ScriptTransport: PlexTransport {
    struct Step: Sendable {
        var status: Int
        var body: Data
        var held: Bool
    }

    private var queues: [String: [Step]] = [:]
    private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]
    private(set) var requests: [URLRequest] = []

    init() {}

    func script(path: String, fixture name: String, status: Int = 200, held: Bool = false) {
        queues[path, default: []].append(Step(status: status, body: Fixture.data(name), held: held))
    }

    func script(path: String, json: String, status: Int = 200, held: Bool = false) {
        queues[path, default: []].append(Step(status: status, body: Data(json.utf8), held: held))
    }

    func requests(forPath path: String) -> [URLRequest] {
        requests.filter { $0.url?.path == path }
    }

    /// Lets every request currently held on `path` go on.
    func release(path: String) {
        let continuations = waiting.removeValue(forKey: path) ?? []
        for continuation in continuations { continuation.resume() }
    }

    /// Waits (polling, bounded) until `path` has been requested `count` times.
    func waitForRequests(path: String, count: Int) async -> Bool {
        for _ in 0..<500 {
            if requests(forPath: path).count >= count { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let path = request.url?.path ?? ""
        guard var queue = queues[path], !queue.isEmpty else { return (Data(), Self.http(request, 404)) }
        let step = queue.count > 1 ? queue.removeFirst() : queue[0]
        queues[path] = queue
        if step.held {
            await withCheckedContinuation { continuation in
                waiting[path, default: []].append(continuation)
            }
        }
        return (step.body, Self.http(request, step.status))
    }

    private static func http(_ request: URLRequest, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

/// Decides every action the same way and records what it was asked.
actor StubAuthoriser: PlexActionAuthorising {
    var decision: Decision
    private(set) var actions: [CoreAction] = []

    init(_ decision: Decision = .allowed) { self.decision = decision }

    func set(_ decision: Decision) { self.decision = decision }

    func authorise(_ action: CoreAction, context: PermissionContext, entity: String?) async -> Decision {
        actions.append(action)
        return decision
    }
}

let testServerToken = "FAKE-SERVER-TOKEN-1"

/// A signed-in owner session, a library over a scripted transport, and a temp snapshot directory.
struct LibraryRig {
    let sessionRig: SessionRig
    let session: PlexSession
    let transport: ScriptTransport
    let authoriser: StubAuthoriser
    let snapshots: PlexHomeSnapshotStore
    let snapshotDirectory: URL
    let library: PlexLibrary

    static func make(decision: Decision = .allowed) async throws -> LibraryRig {
        let sessionRig = SessionRig()
        await sessionRig.transport.scriptHealthyAccount()
        let session = sessionRig.makeSession()
        try await session.signIn(accountToken: "TOKEN-OWNER")
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "perch-snapshots-\(UUID().uuidString)", directoryHint: .isDirectory)
        return make(
            sessionRig: sessionRig, session: session, directory: directory, decision: decision)
    }

    static func make(
        sessionRig: SessionRig, session: PlexSession, directory: URL, decision: Decision = .allowed
    ) -> LibraryRig {
        let transport = ScriptTransport()
        let authoriser = StubAuthoriser(decision)
        let snapshots = PlexHomeSnapshotStore(directory: directory)
        let library = PlexLibrary(
            contextSource: session, transport: transport, endpoints: testEndpoints,
            settings: sessionRig.settings, authoriser: authoriser, snapshots: snapshots)
        return LibraryRig(
            sessionRig: sessionRig, session: session, transport: transport, authoriser: authoriser,
            snapshots: snapshots, snapshotDirectory: directory, library: library)
    }

    /// The Home fixtures: continue watching, on deck and hubs.
    func scriptHome() async {
        await transport.script(path: "/hubs/continueWatching", fixture: "lib-continue-watching")
        await transport.script(path: "/library/onDeck", fixture: "lib-on-deck")
        await transport.script(path: "/hubs", fixture: "lib-hubs")
        await transport.script(path: "/library/recentlyAdded", fixture: "lib-recently-added")
    }

    func cleanup() {
        sessionRig.cleanup()
        try? FileManager.default.removeItem(at: snapshotDirectory)
    }
}

/// Polls (bounded) until `condition` holds.
func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<300 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}
