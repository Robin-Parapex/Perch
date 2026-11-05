import Foundation
import Testing

@testable import PerchCore

@Suite("Artwork cache keys")
struct ArtworkCacheKeyTests {
    @Test func serverKeyIsServerPathAndSize() {
        let key = ArtworkCacheKey.server(serverID: "abc123", path: "/library/metadata/1/thumb/9", size: .poster)
        #expect(key == "abc123|/library/metadata/1/thumb/9|poster")
    }

    @Test func serverKeyDiffersBySizeAndServer() {
        let path = "/library/metadata/1/art/2"
        let keys = Set(ArtworkSize.allCases.map { ArtworkCacheKey.server(serverID: "a", path: path, size: $0) })
        #expect(keys.count == ArtworkSize.allCases.count)
        #expect(
            ArtworkCacheKey.server(serverID: "a", path: path, size: .backdrop)
                != ArtworkCacheKey.server(serverID: "b", path: path, size: .backdrop))
    }

    @Test func publicKeyDropsQueryFragmentAndCredentials() throws {
        let url = try #require(URL(string: "https://me:pw@plex.tv/users/abc/avatar?c=123&X-Plex-Token=SECRET#x"))
        let key = try #require(ArtworkCacheKey.publicImage(url))
        #expect(key == "public|https://plex.tv/users/abc/avatar")
        #expect(!key.contains("SECRET"))
        #expect(!key.lowercased().contains("token"))
    }

    @Test func publicKeyRefusesPlainHTTP() throws {
        let url = try #require(URL(string: "http://example.com/a.png"))
        #expect(ArtworkCacheKey.publicImage(url) == nil)
    }
}
