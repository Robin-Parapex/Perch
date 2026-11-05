import Foundation
import PerchCore
import Testing

@testable import PerchPlex

private let base = URL(string: "http://192.0.2.10:32400")!
private let token = "SECRET-TOKEN-123"

@Suite("Photo transcode requests")
struct PlexPhotoTranscodeTests {
    let endpoints = testEndpoints

    @Test func queryMatchesEachSize() throws {
        for size in ArtworkSize.allCases {
            let request = try #require(
                endpoints.photoTranscode(base: base, path: "/library/metadata/1/thumb/5", size: size, token: token))
            let url = try #require(request.url)
            #expect(url.path == "/photo/:/transcode")
            let q = Dictionary(
                uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                    .map { ($0.name, $0.value ?? "") })
            #expect(q["width"] == String(size.pixelSize.width))
            #expect(q["height"] == String(size.pixelSize.height))
            #expect(q["minSize"] == "1")
            #expect(q["upscale"] == "1")
            #expect(q["url"] == "/library/metadata/1/thumb/5")
            #expect(request.url?.host == "192.0.2.10")
        }
    }

    @Test func versionQueryStaysInsideTheEncodedUrlValue() throws {
        let path = "/library/metadata/1/thumb/5?t=1699"
        let request = try #require(endpoints.photoTranscode(base: base, path: path, size: .poster, token: token))
        let url = try #require(request.url)
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(comps.queryItems?.first(where: { $0.name == "url" })?.value == path)
        #expect(comps.queryItems?.contains(where: { $0.name == "t" }) == false)
        #expect(url.absoluteString.contains("url=%2Flibrary%2Fmetadata%2F1%2Fthumb%2F5%3Ft%3D1699"))
    }

    @Test func tokenIsHeaderOnly() throws {
        let request = try #require(
            endpoints.photoTranscode(base: base, path: "/library/metadata/1/art/2", size: .backdrop, token: token))
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == token)
        #expect(request.value(forHTTPHeaderField: "Accept") == "image/*")
        #expect(request.httpMethod == "GET")
        let url = request.url?.absoluteString ?? ""
        #expect(!url.contains(token) && !url.localizedCaseInsensitiveContains("token"))
    }

    @Test func refusesPathsThatAreNotPlainServerPaths() {
        for path in [
            "//evil", "http://x", "relative", "/library/metadata/1/thumb/5?X-Plex-Token=abc",
        ] {
            #expect(endpoints.photoTranscode(base: base, path: path, size: .poster, token: token) == nil)
        }
    }
}

@Suite("Clear logo decoding")
struct PlexClearLogoDecodeTests {
    private func summaries(_ json: String) throws -> [MediaSummary] {
        let c = try PlexWireContainer.decode(from: Data(json.utf8))
        return PlexLibraryMapping.summaries(c.items)
    }

    @Test func clearLogoIsPickedFromSeveralImageTypes() throws {
        let rows = try summaries(
            #"""
            {"MediaContainer":{"Metadata":[{"ratingKey":"123","type":"movie","title":"A","Image":[
            {"alt":"A","type":"coverPoster","url":"/library/metadata/123/thumb/1"},
            {"alt":"A","type":"background","url":"/library/metadata/123/art/1"},
            {"alt":"A","type":"clearLogo","url":"/library/metadata/123/clearLogo/1699"},
            {"alt":"A","type":"snapshot","url":"/library/metadata/123/snap/1"}]}]}}
            """#)
        #expect(rows.first?.logoPath == "/library/metadata/123/clearLogo/1699")
    }

    @Test func absentOrLogolessImageArrayGivesNil() throws {
        let rows = try summaries(
            #"""
            {"MediaContainer":{"Metadata":[{"ratingKey":"1","type":"movie","title":"A"},
            {"ratingKey":"2","type":"episode","title":"E","Image":[{"type":"snapshot","url":"/x/1"}]}]}}
            """#)
        #expect(rows.map(\.logoPath) == [nil, nil])
    }

    @Test func snapshotRoundTripKeepsLogoPathAndOldSnapshotsDecode() throws {
        let item = MediaSummary(id: "1", kind: .film, title: "T", logoPath: "/library/metadata/1/clearLogo/9")
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "perch-logo-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rows = PlexHomeRows(continueWatching: [item], upNext: [], recentlyAdded: [])
        PlexHomeSnapshotStore(directory: directory).write(rows, profileID: "1001", machineID: "M1")
        let read = PlexHomeSnapshotStore(directory: directory).read(profileID: "1001")
        #expect(read?.continueWatching.items.first?.logoPath == "/library/metadata/1/clearLogo/9")

        let old = #"{"id":"1","kind":"film","title":"Old","viewCount":0}"#
        #expect(try JSONDecoder().decode(MediaSummary.self, from: Data(old.utf8)).logoPath == nil)
    }
}

@Suite("Session image requests", .timeLimit(.minutes(1)))
struct PlexSessionImageRequestTests {
    @Test func nilWhenSignedOut() async {
        let rig = SessionRig()
        defer { rig.cleanup() }
        let session = rig.makeSession()
        #expect(await session.imageRequest(path: "/library/metadata/1/thumb/2", size: .poster) == nil)
        #expect(await session.currentServerID == nil)
    }

    @Test func buildsAgainstTheConnectedServer() async throws {
        let rig = SessionRig()
        defer { rig.cleanup() }
        await rig.transport.scriptHealthyAccount()
        let session = rig.makeSession()
        try await session.signIn(accountToken: "TOKEN-OWNER")
        let request = try #require(await session.imageRequest(path: "/library/metadata/1/thumb/2", size: .landscape))
        guard case .ready(_, let server) = await session.snapshot().state else {
            Issue.record("expected ready")
            return
        }
        #expect(request.url?.host == server.baseURL.host)
        #expect(request.url?.path == "/photo/:/transcode")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "FAKE-SERVER-TOKEN-1")
        #expect(await session.currentServerID == server.machineID)
    }
}
