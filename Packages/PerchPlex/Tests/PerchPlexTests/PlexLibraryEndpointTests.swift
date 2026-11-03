import Foundation
import PerchCore
import Testing

@testable import PerchPlex

private let base = URL(string: "http://192.0.2.10:32400")!
private let token = "SECRET-TOKEN-123"

private func items(_ request: URLRequest) -> [String: String] {
    let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(query.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}

private func expectTokenOnlyInHeader(_ request: URLRequest) {
    #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == token)
    #expect(request.url?.absoluteString.contains(token) == false)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.host == "192.0.2.10")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
}

@Suite("Library endpoints")
struct PlexLibraryEndpointTests {
    let endpoints = testEndpoints

    @Test func sectionItemsPageAndSort() {
        let request = endpoints.sectionItems(
            base: base, token: token, sectionID: "1", sort: "addedAt:desc", start: 50, size: 100)
        #expect(request.url?.path == "/library/sections/1/all")
        let q = items(request)
        #expect(q["sort"] == "addedAt:desc")
        #expect(q["X-Plex-Container-Start"] == "50")
        #expect(q["X-Plex-Container-Size"] == "100")
        expectTokenOnlyInHeader(request)
    }

    @Test func sectionItemsWithoutSort() {
        let request = endpoints.sectionItems(
            base: base, token: token, sectionID: "2", sort: nil, start: 0, size: 50)
        #expect(items(request)["sort"] == nil)
    }

    @Test func sectionCountAsksForOne() {
        let request = endpoints.sectionCount(base: base, token: token, sectionID: "1")
        #expect(request.url?.path == "/library/sections/1/all")
        let q = items(request)
        #expect(q["X-Plex-Container-Start"] == "0")
        #expect(q["X-Plex-Container-Size"] == "1")
        expectTokenOnlyInHeader(request)
    }

    @Test func existingSectionsBuilderStillWorks() {
        let request = endpoints.librarySections(base: base, token: token)
        #expect(request.url?.path == "/library/sections")
        expectTokenOnlyInHeader(request)
    }

    @Test func hubsAndContinueWatching() {
        let hubs = endpoints.hubs(base: base, token: token, count: 20)
        #expect(hubs.url?.path == "/hubs")
        #expect(items(hubs) == ["count": "20", "includeGuids": "1"])
        expectTokenOnlyInHeader(hubs)

        let cw = endpoints.continueWatching(base: base, token: token)
        #expect(cw.url?.path == "/hubs/continueWatching")
        #expect(items(cw) == ["includeGuids": "1"])
        expectTokenOnlyInHeader(cw)

        let deck = endpoints.onDeck(base: base, token: token)
        #expect(deck.url?.path == "/library/onDeck")
        expectTokenOnlyInHeader(deck)
    }

    @Test func hubItemsFollowsAServerPathAndKeepsItsQuery() throws {
        let request = try #require(
            endpoints.hubItems(
                base: base, token: token, path: "/hubs/sections/1/recentlyAdded?type=1", start: 0, size: 20))
        #expect(request.url?.path == "/hubs/sections/1/recentlyAdded")
        let q = items(request)
        #expect(q["type"] == "1")
        #expect(q["X-Plex-Container-Size"] == "20")
        expectTokenOnlyInHeader(request)
    }

    @Test(arguments: [
        "hubs/continueWatching", "//evil.example/hubs", "https://evil.example/hubs",
        "/hubs?X-Plex-Token=abc", "/hubs?token=abc", "/../etc", "", "http://192.0.2.10:32400/hubs",
    ])
    func hubItemsRejectsBadPaths(path: String) {
        #expect(endpoints.hubItems(base: base, token: token, path: path, start: 0, size: 10) == nil)
    }

    @Test func metadataBrowseHasNoCheckFiles() {
        let request = endpoints.metadata(base: base, token: token, ratingKey: "2103", forPlayback: false)
        #expect(request.url?.path == "/library/metadata/2103")
        let q = items(request)
        #expect(q == ["includeMarkers": "1", "includeChapters": "1", "includeExtras": "1", "includeGuids": "1"])
        expectTokenOnlyInHeader(request)
    }

    @Test func metadataForPlaybackAddsCheckFiles() {
        let request = endpoints.metadata(base: base, token: token, ratingKey: "2103", forPlayback: true)
        #expect(items(request)["checkFiles"] == "1")
        #expect(items(request)["includeMarkers"] == "1")
    }

    @Test func extrasChildrenAndLeaves() {
        #expect(endpoints.extras(base: base, token: token, ratingKey: "9").url?.path == "/library/metadata/9/extras")
        #expect(endpoints.children(base: base, token: token, ratingKey: "9").url?.path == "/library/metadata/9/children")
        #expect(endpoints.allLeaves(base: base, token: token, ratingKey: "9").url?.path == "/library/metadata/9/allLeaves")
        expectTokenOnlyInHeader(endpoints.allLeaves(base: base, token: token, ratingKey: "9"))
    }

    @Test func ratingKeyCannotChangeThePath() {
        let request = endpoints.children(base: base, token: token, ratingKey: "1/../../identity")
        #expect(request.url?.path.hasSuffix("/children") == true)
        #expect(request.url?.path.hasPrefix("/library/metadata/") == true)
        #expect(request.url?.absoluteString.contains("/../") == false)
    }

    @Test func timelineQueryAndSessionHeader() {
        let request = endpoints.timeline(
            base: base, token: token, ratingKey: "2103", state: .playing, timeMs: 61_000,
            durationMs: 2_700_000, sessionID: "SESSION-1")
        #expect(request.url?.path == "/:/timeline")
        let q = items(request)
        #expect(q["ratingKey"] == "2103")
        #expect(q["key"] == "/library/metadata/2103")
        #expect(q["state"] == "playing")
        #expect(q["time"] == "61000")
        #expect(q["duration"] == "2700000")
        #expect(q["X-Plex-Session-Identifier"] == nil)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Session-Identifier") == "SESSION-1")
        expectTokenOnlyInHeader(request)
    }

    @Test(arguments: [PlaybackState.playing, .paused, .buffering, .stopped])
    func timelineStateNames(state: PlaybackState) {
        let request = endpoints.timeline(
            base: base, token: token, ratingKey: "1", state: state, timeMs: 0, durationMs: nil, sessionID: "S")
        #expect(items(request)["state"] == state.rawValue)
        #expect(items(request)["duration"] == nil)
    }

    @Test func scrobbleUnscrobbleAndProgress() {
        let scrobble = endpoints.scrobble(base: base, token: token, ratingKey: "55")
        #expect(scrobble.url?.path == "/:/scrobble")
        #expect(items(scrobble) == ["key": "55", "identifier": "com.plexapp.plugins.library"])
        expectTokenOnlyInHeader(scrobble)

        let unscrobble = endpoints.unscrobble(base: base, token: token, ratingKey: "55")
        #expect(unscrobble.url?.path == "/:/unscrobble")
        #expect(items(unscrobble) == ["key": "55", "identifier": "com.plexapp.plugins.library"])

        let progress = endpoints.progress(base: base, token: token, ratingKey: "55", timeMs: 90_000)
        #expect(progress.url?.path == "/:/progress")
        #expect(items(progress) == ["key": "55", "identifier": "com.plexapp.plugins.library", "time": "90000"])
        expectTokenOnlyInHeader(progress)
    }

    @Test func baseWithTrailingSlashOrPathStillJoins() {
        let slash = URL(string: "https://plex.example:32400/")!
        #expect(endpoints.onDeck(base: slash, token: token).url?.path == "/library/onDeck")
        let prefixed = URL(string: "https://plex.example/server")!
        #expect(endpoints.onDeck(base: prefixed, token: token).url?.path == "/server/library/onDeck")
    }

    @Test func identityHeadersArePresent() {
        let request = endpoints.onDeck(base: base, token: token)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Client-Identifier") == "TEST-CLIENT")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Product") == "Perch")
    }
}
