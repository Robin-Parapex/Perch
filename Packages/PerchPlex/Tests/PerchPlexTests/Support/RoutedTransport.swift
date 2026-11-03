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

    func requests(forHost host: String) -> [URLRequest] {
        requests.filter { $0.url?.host(percentEncoded: false) == host }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let host = request.url?.host(percentEncoded: false) ?? ""
        let path = request.url?.path ?? ""
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
