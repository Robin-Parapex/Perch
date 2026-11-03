#if DEBUG
import Foundation
import PerchPlex
import Synchronization

/// DEBUG-only canned plex.tv and server answers (WP-05 decision 12, change C1), so the whole first run,
/// the picker and the PIN rules run in UI tests and screenshots without a real account.
/// `-PerchFakeHousehold withPINs|noPINs`. Every token here is an obvious fake; the fake Plex PIN is 1234.
struct FakeHouseholdTransport: PlexTransport {
    enum Household: String {
        /// Owner (admin) with a Plex PIN, a protected adult, a kid.
        case withPINs
        /// Owner without a PIN, an adult without a PIN, a kid.
        case noPINs
    }

    static let plexPIN = "1234"
    static let linkCode = "PRCH"

    private struct FakeUser {
        let id: Int
        let name: String
        let admin: Bool
        let restricted: Bool
        let protected: Bool
    }

    /// Mutable bits (the link poll count, rendered art) behind a lock so the transport stays Sendable.
    private final class State: Sendable {
        let polls = Mutex(0)
        let art = Mutex<[Int: Data]>([:])
    }

    private let household: Household
    private let state = State()

    init(household: Household) { self.household = household }

    /// Nil unless the launch arguments ask for a fake household.
    static func fromArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments)
        -> FakeHouseholdTransport?
    {
        guard let index = arguments.firstIndex(of: "-PerchFakeHousehold") else { return nil }
        let value = arguments.indices.contains(index + 1) ? arguments[index + 1] : ""
        return FakeHouseholdTransport(household: Household(rawValue: value) ?? .withPINs)
    }

    private var users: [FakeUser] {
        switch household {
        case .withPINs:
            [
                FakeUser(id: 1001, name: "Robin", admin: true, restricted: false, protected: true),
                FakeUser(id: 1002, name: "Jo", admin: false, restricted: false, protected: true),
                FakeUser(id: 1003, name: "Sam", admin: false, restricted: true, protected: false),
            ]
        case .noPINs:
            [
                FakeUser(id: 1001, name: "Robin", admin: true, restricted: false, protected: false),
                FakeUser(id: 1002, name: "Jo", admin: false, restricted: false, protected: false),
                FakeUser(id: 1003, name: "Sam", admin: false, restricted: true, protected: false),
            ]
        }
    }

    private static let serverHost = "192.168.1.50"
    private static let serverURI = "http://192.168.1.50:32400"
    private static let machineID = "FAKE-MACHINE-LIVING-ROOM"

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        let path = url.path
        if host == "plex.tv" || host == "clients.plex.tv" { return try plexTV(request, path: path) }
        if host == Self.serverHost { return try await server(request, path: path) }
        throw URLError(.cannotFindHost)
    }

    // MARK: plex.tv

    private func plexTV(_ request: URLRequest, path: String) throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let method = request.httpMethod ?? "GET"
        switch (method, path) {
        case ("POST", "/api/v2/pins"):
            state.polls.withLock { $0 = 0 }
            let expires = Date.now.addingTimeInterval(900).formatted(.iso8601)
            return try json(["id": 1, "code": Self.linkCode, "expiresAt": expires], url)
        case ("GET", "/api/v2/pins/1"):
            let count = state.polls.withLock { value -> Int in
                value += 1
                return value
            }
            // The first poll is still waiting; the second finds the account linked.
            var body: [String: Any] = ["id": 1, "code": Self.linkCode]
            if count >= 2 { body["authToken"] = "FAKE-ACCOUNT-TOKEN" }
            return try json(body, url)
        case ("GET", "/api/v2/user"):
            guard let owner = users.first(where: \.admin) else { throw URLError(.badServerResponse) }
            return try json(
                [
                    "id": owner.id, "uuid": "fake-uuid-\(owner.id)", "username": owner.name.lowercased(),
                    "title": owner.name,
                ], url)
        case ("GET", "/api/v2/home/users"):
            return try json(
                [
                    "users": users.map { user -> [String: Any] in
                        var row: [String: Any] = [
                            "id": user.id, "uuid": "fake-uuid-\(user.id)", "title": user.name,
                            "admin": user.admin, "guest": false, "restricted": user.restricted,
                            "protected": user.protected,
                        ]
                        if user.restricted { row["restrictionProfile"] = "little_kid" }
                        return row
                    }
                ], url)
        case ("GET", "/api/v2/resources"):
            return try json(
                [
                    [
                        "name": "Living room", "clientIdentifier": Self.machineID, "provides": "server",
                        "accessToken": "FAKE-SERVER-TOKEN", "owned": true,
                        "connections": [
                            [
                                "protocol": "http", "address": Self.serverHost, "port": 32400,
                                "uri": Self.serverURI, "local": true, "relay": false, "IPv6": false,
                            ]
                        ],
                    ]
                ], url)
        default:
            if method == "POST", path.hasPrefix("/api/home/users/"), path.hasSuffix("/switch") {
                return switchUser(url, path: path)
            }
            return (Data(), response(url, 404))
        }
    }

    /// Protected users need the fixed PIN; the answer is XML like the real service (WP-04 review).
    private func switchUser(_ url: URL, path: String) -> (Data, HTTPURLResponse) {
        let parts = path.split(separator: "/")
        guard parts.count == 5, let id = Int(parts[3]), let user = users.first(where: { $0.id == id }) else {
            return (Data(), response(url, 404))
        }
        if user.protected {
            let entered = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "pin" }?.value
            guard entered == Self.plexPIN else { return (Data(), response(url, 401)) }
        }
        let xml = #"<user id="\#(id)" title="\#(user.name)" authenticationToken="FAKE-USER-TOKEN-\#(id)"/>"#
        return (Data(xml.utf8), response(url, 200, type: "application/xml"))
    }

    // MARK: Server

    private func server(_ request: URLRequest, path: String) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        if path == "/identity" {
            return try json(
                ["MediaContainer": ["machineIdentifier": Self.machineID, "version": "0.0-fake"]], url)
        }
        let token = request.value(forHTTPHeaderField: "X-Plex-Token") ?? ""
        guard !token.isEmpty else { return (Data(), response(url, 401)) }
        switch path {
        case "/library/sections":
            return try json(
                [
                    "MediaContainer": [
                        "size": 2,
                        "Directory": [["key": "1", "title": "Films"], ["key": "2", "title": "Shows"]],
                    ]
                ], url)
        case "/library/recentlyAdded":
            let items = (1...5).map { ["art": "/library/metadata/\($0)/art/1", "contentRating": "U"] }
            return try json(["MediaContainer": ["size": items.count, "Metadata": items]], url)
        default:
            if path.hasPrefix("/library/metadata/") {
                let number = path.split(separator: "/").dropFirst(2).first.flatMap { Int($0) } ?? 1
                let data = await art(number)
                return (data, response(url, 200, type: "image/png"))
            }
            return (Data(), response(url, 404))
        }
    }

    private func art(_ number: Int) async -> Data {
        if let cached = state.art.withLock({ $0[number] }) { return cached }
        let data = await FakeArt.png(index: number)
        state.art.withLock { $0[number] = data }
        return data
    }

    // MARK: Helpers

    private func json(_ object: Any, _ url: URL) throws -> (Data, HTTPURLResponse) {
        (try JSONSerialization.data(withJSONObject: object), response(url, 200, type: "application/json"))
    }

    private func response(_ url: URL, _ status: Int, type: String? = nil) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: type.map { ["Content-Type": $0] })!
    }
}
#endif
