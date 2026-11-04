import Foundation

@testable import PerchPlex

/// Like `FakeTransport` but routes by host as well as path, and can delay a reply (a real sleep),
/// so a test can make one address answer before another. Unrouted requests answer 404.
actor RoutedTransport: PlexTransport {
    enum Reply: Sendable {
        case ok(Data)
        case status(Int)
        case fail(URLError.Code)
    }

    private struct Route {
        let host: String
        let path: String
        let delay: Duration
        let reply: Reply
    }

    private var routes: [Route] = []
    private(set) var requests: [URLRequest] = []

    init() {}

    func route(host: String, path: String = "/identity", delay: Duration = .zero, _ reply: Reply) {
        routes.append(Route(host: host, path: path, delay: delay, reply: reply))
    }

    /// Replaces the route for `host` and `path` (later requests get the new reply).
    func reroute(host: String, path: String = "/identity", _ reply: Reply) {
        routes.removeAll { $0.host == host && $0.path == path }
        route(host: host, path: path, reply)
    }

    private var holdKey: String?
    private var heldRequest: CheckedContinuation<Void, Never>?
    private var holdArrived = false

    /// The next request to `host` and `path` waits until `releaseHold()`; later ones pass straight through.
    func holdNext(host: String, path: String) { holdKey = host + path }

    /// Waits until the held request has arrived.
    func waitForHeldRequest() async {
        while !holdArrived { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func releaseHold() {
        heldRequest?.resume()
        heldRequest = nil
    }

    func requests(forHost host: String) -> [URLRequest] {
        requests.filter { $0.url?.host(percentEncoded: false) == host }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let host = request.url?.host(percentEncoded: false) ?? ""
        let path = request.url?.path ?? ""
        if let holdKey, holdKey == host + path {
            self.holdKey = nil
            await withCheckedContinuation { continuation in
                heldRequest = continuation
                holdArrived = true
            }
        }
        guard let route = routes.first(where: { $0.host == host && $0.path == path }) else {
            return (Data(), Self.http(request, 404))
        }
        if route.delay > .zero { try await Task.sleep(for: route.delay) }
        switch route.reply {
        case .ok(let body): return (body, Self.http(request, 200))
        case .status(let code): return (Data(), Self.http(request, code))
        case .fail(let code): throw URLError(code)
        }
    }

    private static func http(_ request: URLRequest, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}
