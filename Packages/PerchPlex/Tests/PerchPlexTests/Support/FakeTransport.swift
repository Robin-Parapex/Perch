import Foundation

@testable import PerchPlex

/// Records every request and answers from a script matched by URL path (and optionally method).
/// Each path has a queue of replies; the last one repeats. An unscripted path answers 404.
actor FakeTransport: PlexTransport {
    enum Reply: Sendable {
        case response(status: Int, body: Data)
        case failure(URLError.Code)
    }

    private struct Rule {
        let path: String
        let method: String?
        var replies: [Reply]
    }

    private var rules: [Rule] = []
    private(set) var requests: [URLRequest] = []

    init() {}

    func script(path: String, method: String? = nil, _ replies: Reply...) {
        rules.append(Rule(path: path, method: method, replies: replies))
    }

    func script(path: String, method: String? = nil, fixture name: String, status: Int = 200) {
        rules.append(
            Rule(path: path, method: method, replies: [.response(status: status, body: Fixture.data(name))]))
    }

    func requests(forPath path: String) -> [URLRequest] {
        requests.filter { $0.url?.path == path }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        guard let index = rules.firstIndex(where: { $0.path == path && ($0.method ?? method) == method })
        else {
            return (Data(), Self.http(request, 404))
        }
        let reply = rules[index].replies.count > 1
            ? rules[index].replies.removeFirst() : rules[index].replies[0]
        switch reply {
        case .response(let status, let body): return (body, Self.http(request, status))
        case .failure(let code): throw URLError(code)
        }
    }

    private static func http(_ request: URLRequest, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

enum Fixture {
    static func data(_ name: String) -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json")!
        return try! Data(contentsOf: url)
    }
}
