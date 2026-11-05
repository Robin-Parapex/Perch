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

    @Test func publicKeyKeepsOnlyTheCacheBuster() throws {
        let url = try #require(URL(string: "https://me:pw@plex.tv/users/abc/avatar?c=123&X-Plex-Token=SECRET#x"))
        let key = try #require(ArtworkCacheKey.publicImage(url))
        #expect(key == "public|https://plex.tv/users/abc/avatar?c=123")
        #expect(!key.contains("SECRET"))
        #expect(!key.lowercased().contains("token"))
    }

    @Test func changedAvatarGetsANewKey() throws {
        let old = try #require(URL(string: "https://plex.tv/users/abc/avatar?c=111"))
        let new = try #require(URL(string: "https://plex.tv/users/abc/avatar?c=222"))
        #expect(ArtworkCacheKey.publicImage(old) != ArtworkCacheKey.publicImage(new))
        let bare = try #require(URL(string: "https://plex.tv/users/abc/avatar?size=200"))
        #expect(ArtworkCacheKey.publicImage(bare) == "public|https://plex.tv/users/abc/avatar")
    }

    @Test func publicKeyRefusesPlainHTTP() throws {
        let url = try #require(URL(string: "http://example.com/a.png"))
        #expect(ArtworkCacheKey.publicImage(url) == nil)
    }
}

@Suite("Artwork cache policy")
struct ArtworkCachePolicyTests {
    @Test func firstLaunchSignedOutDoesNotClear() {
        var policy = ArtworkCachePolicy(savedServerID: "A")
        #expect(policy.observe(.signedOut) == false)
        #expect(policy.serverID == "A")
        #expect(policy.observe(.connecting) == false)
        #expect(policy.observe(.ready(serverID: "A")) == false)
    }

    @Test func signOutAfterReadyClears() {
        var policy = ArtworkCachePolicy(savedServerID: nil)
        #expect(policy.observe(.ready(serverID: "A")) == false)
        #expect(policy.observe(.signedOut) == true)
        #expect(policy.serverID == nil)
        #expect(policy.observe(.signedOut) == false)
    }

    @Test func serverIDSurvivesConnectingAndUnreachable() {
        var policy = ArtworkCachePolicy(savedServerID: "A")
        #expect(policy.observe(.connecting) == false)
        #expect(policy.serverID == "A")
        #expect(policy.observe(.ready(serverID: "A")) == false)
        #expect(policy.observe(.connecting) == false)
        #expect(policy.serverID == "A")
    }

    @Test func differentFirstReadyServerClears() {
        // A revoked token starts signed out (no clear), then a sign-in to another server.
        var policy = ArtworkCachePolicy(savedServerID: "A")
        #expect(policy.observe(.signedOut) == false)
        #expect(policy.observe(.ready(serverID: "B")) == true)
        #expect(policy.serverID == "B")
    }

    @Test func explicitSignOutForgetsTheServer() {
        var policy = ArtworkCachePolicy(savedServerID: "A")
        policy.signedOut()
        #expect(policy.serverID == nil)
        #expect(policy.observe(.signedOut) == false)
        #expect(policy.observe(.ready(serverID: "A")) == false)
    }
}
