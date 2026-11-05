import Foundation
import PerchCore
import Testing
import UIKit

@testable import PerchApp

/// A source that draws a small PNG after an optional delay, counting its loads.
private struct DrawingSource: ArtworkSource {
    let delay: Duration
    var name: String { "test" }

    func data(path: String, size: ArtworkSize) async throws -> Data? {
        if delay > .zero { try await Task.sleep(for: delay) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 12), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 12))
        }.pngData()
    }
}

/// WP-08 review: ArtworkService's clearing rules against a real Nuke pipeline in a temporary directory.
@MainActor @Suite("ArtworkService", .serialized)
struct ArtworkServiceTests {
    private struct Fixture {
        let service: ArtworkService
        let defaults: UserDefaults
        let directory: URL
    }

    private func make(saved: String? = nil, delay: Duration = .zero, directory: URL? = nil, defaults: UserDefaults? = nil)
        -> Fixture
    {
        let defaults = defaults ?? UserDefaults(suiteName: "test.artwork.\(UUID().uuidString)")!
        if let saved { defaults.set(saved, forKey: ArtworkService.serverIDKey) }
        let directory = directory
            ?? FileManager.default.temporaryDirectory.appending(path: "artwork-\(UUID().uuidString)", directoryHint: .isDirectory)
        let service = ArtworkService(
            sources: [DrawingSource(delay: delay)], diskDirectory: directory, defaults: defaults,
            currentServerID: { nil }, becomesShared: false)
        return Fixture(service: service, defaults: defaults, directory: directory)
    }

    private let key = ArtworkCacheKey.server(serverID: "A", path: "/library/metadata/1/thumb/1", size: .poster)

    @Test func signOutClearsMemoryAndDisk() async {
        let f = make()
        f.service.observe(.ready(serverID: "A"))
        #expect(await f.service.load(path: "/library/metadata/1/thumb/1", size: .poster) != nil)
        f.service.flushDisk()
        #expect(f.service.isCached(key: key, in: .memory))
        #expect(f.service.isCached(key: key, in: .disk))
        f.defaults.set("x", forKey: LibraryBackdrop.defaultsKey)

        f.service.observe(.signedOut)
        f.service.flushDisk()
        #expect(!f.service.isCached(key: key, in: .memory))
        #expect(!f.service.isCached(key: key, in: .disk))
        #expect(f.service.serverID == nil)
        #expect(f.defaults.string(forKey: ArtworkService.serverIDKey) == nil)
        #expect(f.defaults.string(forKey: LibraryBackdrop.defaultsKey) == nil)
    }

    @Test func explicitSignOutClearsToo() async {
        let f = make(saved: "A")
        #expect(await f.service.load(path: "/library/metadata/1/thumb/1", size: .poster) != nil)
        f.service.signedOut()
        f.service.flushDisk()
        #expect(!f.service.isCached(key: key, in: .memory))
        #expect(!f.service.isCached(key: key, in: .disk))
    }

    @Test func firstLaunchSignedOutKeepsTheCache() async {
        let first = make()
        first.service.observe(.ready(serverID: "A"))
        #expect(await first.service.load(path: "/library/metadata/1/thumb/1", size: .poster) != nil)
        first.service.flushDisk()

        // The next launch: same disk and defaults; the first state seen is signed out (resume not run yet).
        let next = make(directory: first.directory, defaults: first.defaults)
        next.service.observe(.signedOut)
        #expect(next.service.isCached(key: key, in: .disk))
        #expect(next.service.serverID == "A")
    }

    @Test func connectingFallsBackToTheLastServer() async {
        let f = make(saved: "A")
        f.service.observe(.connecting)
        #expect(f.service.serverID == "A")
        #expect(f.service.cacheKey(path: "/x", size: .poster) == "A|/x|poster")
        #expect(await f.service.load(path: "/x", size: .poster) != nil)
    }

    @Test func anotherServerClears() async {
        let f = make(saved: "A")
        #expect(await f.service.load(path: "/library/metadata/1/thumb/1", size: .poster) != nil)
        f.service.observe(.signedOut)  // a revoked token: no clear yet
        f.service.observe(.ready(serverID: "B"))
        f.service.flushDisk()
        #expect(!f.service.isCached(key: key, in: .disk))
        #expect(f.service.serverID == "B")
    }

    @Test func loadInFlightDuringAClearIsNotStored() async {
        let f = make(saved: "A", delay: .milliseconds(400))
        let load = Task { await f.service.load(path: "/library/metadata/1/thumb/1", size: .poster) }
        try? await Task.sleep(for: .milliseconds(100))
        f.service.removeAll()
        #expect(await load.value == nil)
        f.service.flushDisk()
        #expect(!f.service.isCached(key: key, in: .memory))
        #expect(!f.service.isCached(key: key, in: .disk))
    }

    @Test func avatarKeyKeepsTheCacheBuster() throws {
        let f = make()
        let url = try #require(URL(string: "https://plex.tv/users/abc/avatar?c=1750000000&X-Plex-Token=SECRET"))
        #expect(f.service.publicCacheKey(url) == "public|https://plex.tv/users/abc/avatar?c=1750000000")
    }
}
