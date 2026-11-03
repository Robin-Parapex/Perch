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
                        "Directory": [
                            ["key": "1", "title": "Films", "type": "movie"],
                            ["key": "2", "title": "Shows", "type": "show"],
                        ],
                    ]
                ], url)
        case "/library/recentlyAdded":
            let items = (1...5).map { ["art": "/library/metadata/\($0)/art/1", "contentRating": "U"] }
            return try json(["MediaContainer": ["size": items.count, "Metadata": items]], url)
        case "/hubs/continueWatching": return raw(Self.continueWatchingJSON, url)
        case "/hubs": return raw(Self.hubsJSON, url)
        case "/library/onDeck": return raw(Self.onDeckJSON, url)
        // Watch-state and timeline writes: accepted, nothing kept.
        case "/:/timeline", "/:/scrobble", "/:/unscrobble", "/:/progress":
            return (Data(), response(url, 200))
        default:
            // "/library/metadata/{rk}" is a detail; deeper paths (thumb, art) are the sample art.
            let parts = path.split(separator: "/")
            if parts.count == 3, parts[0] == "library", parts[1] == "metadata" {
                return raw(Self.detailJSON(ratingKey: String(parts[2])), url)
            }
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

    // MARK: Library answers (invented titles)

    private static let continueWatchingJSON = """
        {"MediaContainer": {"size": 1, "Hub": [
          {"hubIdentifier": "home.continue", "title": "Continue Watching", "type": "mixed", "key": "/hubs/continueWatching/items", "size": 4, "Metadata": [
            {"ratingKey": "2101", "key": "/library/metadata/2101", "type": "episode", "title": "Salt and Signal", "grandparentRatingKey": "2000", "grandparentTitle": "The Lantern Keepers", "grandparentThumb": "/library/metadata/2000/thumb/1", "parentRatingKey": "2100", "parentIndex": 1, "index": 3, "contentRating": "TV-14", "duration": 2700000, "viewOffset": 600000, "viewCount": 0, "thumb": "/library/metadata/2101/thumb/1", "addedAt": 1700000100, "lastViewedAt": 1790000500},
            {"ratingKey": "1001", "key": "/library/metadata/1001", "type": "movie", "title": "Harbour Lights", "year": 2019, "contentRating": "PG", "duration": 7200000, "viewOffset": 2400000, "viewCount": 0, "thumb": "/library/metadata/1001/thumb/1", "art": "/library/metadata/1001/art/1", "addedAt": 1700000000, "lastViewedAt": 1790000000},
            {"ratingKey": "3102", "key": "/library/metadata/3102", "type": "episode", "title": "The Second Folder", "grandparentRatingKey": "3000", "grandparentTitle": "Cold Harbour Files", "grandparentThumb": "/library/metadata/3000/thumb/1", "parentRatingKey": "3100", "parentIndex": 2, "index": 2, "contentRating": "TV-14", "duration": 3000000, "viewCount": 0, "thumb": "/library/metadata/3102/thumb/1", "addedAt": 1700000300}
          ]}
        ]}}
        """

    private static let hubsJSON = """
        {"MediaContainer": {"size": 2, "Hub": [
          {"hubIdentifier": "movie.recentlyadded.1", "title": "Recently Added Movies", "type": "movie", "key": "/hubs/sections/1/recentlyAdded?type=1", "size": 2, "Metadata": [
            {"ratingKey": "1003", "type": "movie", "title": "Paper Boats", "year": 2024, "contentRating": "PG", "thumb": "/library/metadata/1003/thumb/1", "addedAt": 1790000300},
            {"ratingKey": "1002", "type": "movie", "title": "The Quiet Orchard", "year": 2023, "contentRating": "PG", "thumb": "/library/metadata/1002/thumb/1", "addedAt": 1790000100}
          ]},
          {"hubIdentifier": "tv.recentlyadded.2", "title": "Recently Added TV", "type": "episode", "key": "/hubs/sections/2/recentlyAdded?type=4", "size": 1, "Metadata": [
            {"ratingKey": "2104", "type": "episode", "title": "Slack Water", "grandparentRatingKey": "2000", "grandparentTitle": "The Lantern Keepers", "parentRatingKey": "2100", "parentIndex": 1, "index": 5, "contentRating": "TV-14", "thumb": "/library/metadata/2104/thumb/1", "addedAt": 1790000200}
          ]}
        ]}}
        """

    private static let onDeckJSON = """
        {"MediaContainer": {"size": 1, "Metadata": [
          {"ratingKey": "3102", "key": "/library/metadata/3102", "type": "episode", "title": "The Second Folder", "grandparentRatingKey": "3000", "grandparentTitle": "Cold Harbour Files", "parentRatingKey": "3100", "parentIndex": 2, "index": 2, "contentRating": "TV-14", "duration": 3000000, "viewCount": 0, "thumb": "/library/metadata/3102/thumb/1", "addedAt": 1700000300}
        ]}}
        """

    /// One episode whatever the key: intro and final credits markers, three chapters, a trailer, and a
    /// 4K HEVC Dolby Vision profile 8 file with EAC3 5.1 audio and an SRT subtitle.
    private static func detailJSON(ratingKey: String) -> String {
        """
        {"MediaContainer": {"size": 1, "Metadata": [
          {"ratingKey": "\(ratingKey)", "key": "/library/metadata/\(ratingKey)", "type": "episode", "title": "Salt and Signal",
            "grandparentRatingKey": "2000", "grandparentTitle": "The Lantern Keepers", "parentRatingKey": "2100", "parentTitle": "Season 1", "parentIndex": 1, "index": 3,
            "contentRating": "TV-14", "summary": "The keepers watch for a light that never comes.", "year": 2024,
            "thumb": "/library/metadata/\(ratingKey)/thumb/1", "duration": 2700000, "viewOffset": 600000, "viewCount": 0, "addedAt": 1700000100,
            "Media": [{"id": 7001, "duration": 2700000, "width": 3840, "height": 2160, "videoResolution": "4k", "container": "mkv", "videoCodec": "hevc", "audioCodec": "eac3",
              "Part": [{"id": 8001, "key": "/library/parts/8001/1/file.mkv", "duration": 2699500, "size": 4123456789, "container": "mkv", "accessible": true,
                "Stream": [
                  {"id": 9001, "streamType": 1, "codec": "hevc", "bitDepth": 10, "colorTrc": "smpte2084", "DOVIProfile": 8, "DOVIPresent": true, "frameRate": 23.976, "width": 3840, "height": 2160, "default": true, "selected": true},
                  {"id": 9002, "streamType": 2, "codec": "eac3", "channels": 6, "languageCode": "eng", "default": true, "selected": true},
                  {"id": 9003, "streamType": 3, "codec": "srt", "format": "srt", "key": "/library/streams/9003", "languageCode": "eng", "title": "SDH"}
                ]}]}],
            "Marker": [
              {"id": 501, "type": "intro", "startTimeOffset": 5000, "endTimeOffset": 65000},
              {"id": 503, "type": "credits", "startTimeOffset": 2600000, "endTimeOffset": 2700000, "final": true}
            ],
            "Chapter": [
              {"id": 601, "index": 1, "startTimeOffset": 0, "endTimeOffset": 900000, "tag": "Cold open"},
              {"id": 602, "index": 2, "startTimeOffset": 900000, "endTimeOffset": 1800000, "tag": "The Signal"},
              {"id": 603, "index": 3, "startTimeOffset": 1800000, "endTimeOffset": 2700000, "tag": "Dawn"}
            ],
            "Extras": {"size": 1, "Metadata": [
              {"ratingKey": "2901", "type": "clip", "subtype": "trailer", "title": "Season 1 Trailer", "duration": 90000}
            ]}
          }
        ]}}
        """
    }

    // MARK: Helpers

    private func raw(_ body: String, _ url: URL) -> (Data, HTTPURLResponse) {
        (Data(body.utf8), response(url, 200, type: "application/json"))
    }

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
