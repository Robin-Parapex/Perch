import Foundation
import PerchCore

/// Library request builders. Pure, like the rest of `PlexEndpoints`: the token is always the
/// `X-Plex-Token` header, never a query item. Endpoint set after Dusk (MIT) and python-plexapi;
/// V4 of WP-06 confirms each path on the live server. `librarySections(base:token:)` already
/// exists in PlexEndpoints.swift and is reused as is.
extension PlexEndpoints {
    /// The identifier the scrobble and progress endpoints expect.
    static let libraryPluginIdentifier = "com.plexapp.plugins.library"

    // MARK: building

    func libraryRequest(
        base: URL, token: String, path: String, query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) -> URLRequest {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        var basePath = components.percentEncodedPath
        if basePath.hasSuffix("/") { basePath.removeLast() }
        components.percentEncodedPath = basePath + path
        components.queryItems = query.isEmpty ? nil : query
        return finish(components.url!, token: token, headers: headers)
    }

    private func finish(_ url: URL, token: String, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in identity.headers(token: token) { request.setValue(value, forHTTPHeaderField: key) }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return request
    }

    /// One path segment, percent-encoded so an id can never add or remove a path component.
    func segment(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    func paging(start: Int, size: Int) -> [URLQueryItem] {
        [
            .init(name: "X-Plex-Container-Start", value: String(max(0, start))),
            .init(name: "X-Plex-Container-Size", value: String(max(1, size))),
        ]
    }

    // MARK: sections and items

    /// `sort` is one Plex sort such as "titleSort" or "addedAt:desc"; nil leaves the server order.
    public func sectionItems(
        base: URL, token: String, sectionID: String, sort: String?, start: Int, size: Int
    ) -> URLRequest {
        var query: [URLQueryItem] = []
        if let sort, !sort.isEmpty { query.append(.init(name: "sort", value: sort)) }
        query += paging(start: start, size: size)
        return libraryRequest(
            base: base, token: token, path: "/library/sections/\(segment(sectionID))/all", query: query)
    }

    /// Asks for one item so `totalSize` in the reply is the section's count.
    public func sectionCount(base: URL, token: String, sectionID: String) -> URLRequest {
        libraryRequest(
            base: base, token: token, path: "/library/sections/\(segment(sectionID))/all",
            query: paging(start: 0, size: 1))
    }

    // MARK: hubs

    public func hubs(base: URL, token: String, count: Int) -> URLRequest {
        libraryRequest(
            base: base, token: token, path: "/hubs",
            query: [
                .init(name: "count", value: String(max(1, count))),
                .init(name: "includeGuids", value: "1"),
            ])
    }

    public func continueWatching(base: URL, token: String) -> URLRequest {
        libraryRequest(
            base: base, token: token, path: "/hubs/continueWatching",
            query: [.init(name: "includeGuids", value: "1")])
    }

    /// Follows a hub's `key`. Returns nil unless `path` is a server-relative path (no scheme, no
    /// host, no token in the query), so the token header can only go to `base`.
    public func hubItems(base: URL, token: String, path: String, start: Int, size: Int) -> URLRequest? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("://"),
            !path.contains(".."),
            let parts = URLComponents(string: path),
            !(parts.queryItems ?? []).contains(where: { $0.name.lowercased().contains("token") }),
            var target = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        target.percentEncodedPath = parts.percentEncodedPath
        target.queryItems = (parts.queryItems ?? []) + paging(start: start, size: size)
        target.fragment = nil
        guard let url = target.url else { return nil }
        return finish(url, token: token, headers: [:])
    }

    public func onDeck(base: URL, token: String) -> URLRequest {
        libraryRequest(base: base, token: token, path: "/library/onDeck")
    }

    // MARK: metadata

    /// `forPlayback` adds `checkFiles=1`, which makes the server check the files; only the player asks.
    public func metadata(base: URL, token: String, ratingKey: String, forPlayback: Bool) -> URLRequest {
        var query: [URLQueryItem] = [
            .init(name: "includeMarkers", value: "1"),
            .init(name: "includeChapters", value: "1"),
            .init(name: "includeExtras", value: "1"),
            .init(name: "includeGuids", value: "1"),
        ]
        if forPlayback { query.append(.init(name: "checkFiles", value: "1")) }
        return libraryRequest(
            base: base, token: token, path: "/library/metadata/\(segment(ratingKey))", query: query)
    }

    public func extras(base: URL, token: String, ratingKey: String) -> URLRequest {
        libraryRequest(
            base: base, token: token, path: "/library/metadata/\(segment(ratingKey))/extras")
    }

    public func children(base: URL, token: String, ratingKey: String) -> URLRequest {
        libraryRequest(
            base: base, token: token, path: "/library/metadata/\(segment(ratingKey))/children")
    }

    public func allLeaves(base: URL, token: String, ratingKey: String) -> URLRequest {
        libraryRequest(
            base: base, token: token, path: "/library/metadata/\(segment(ratingKey))/allLeaves")
    }

    // MARK: playback and watch state

    /// Timeline report. Times are ms. The session id is a header, as Plex expects.
    public func timeline(
        base: URL, token: String, ratingKey: String, state: PlaybackState, timeMs: Int,
        durationMs: Int?, sessionID: String
    ) -> URLRequest {
        var query: [URLQueryItem] = [
            .init(name: "ratingKey", value: ratingKey),
            .init(name: "key", value: "/library/metadata/\(ratingKey)"),
            .init(name: "state", value: state.rawValue),
            .init(name: "time", value: String(max(0, timeMs))),
        ]
        if let durationMs { query.append(.init(name: "duration", value: String(max(0, durationMs)))) }
        return libraryRequest(
            base: base, token: token, path: "/:/timeline", query: query,
            headers: ["X-Plex-Session-Identifier": sessionID])
    }

    public func scrobble(base: URL, token: String, ratingKey: String) -> URLRequest {
        libraryRequest(
            base: base, token: token, path: "/:/scrobble",
            query: [
                .init(name: "key", value: ratingKey),
                .init(name: "identifier", value: Self.libraryPluginIdentifier),
            ])
    }

    public func unscrobble(base: URL, token: String, ratingKey: String) -> URLRequest {
        libraryRequest(
            base: base, token: token, path: "/:/unscrobble",
            query: [
                .init(name: "key", value: ratingKey),
                .init(name: "identifier", value: Self.libraryPluginIdentifier),
            ])
    }

    /// Sets the resume point without a timeline session.
    public func progress(base: URL, token: String, ratingKey: String, timeMs: Int) -> URLRequest {
        libraryRequest(
            base: base, token: token, path: "/:/progress",
            query: [
                .init(name: "key", value: ratingKey),
                .init(name: "identifier", value: Self.libraryPluginIdentifier),
                .init(name: "time", value: String(max(0, timeMs))),
            ])
    }

    // MARK: transcode sessions

    /// Direct-play URL for a part's file. Nil unless `key` is a server-relative path. No query, so no token.
    public func directPlayURL(base: URL, partKey key: String) -> URL? {
        guard key.hasPrefix("/"), !key.hasPrefix("//"), !key.contains("://"), !key.contains(".."),
            !key.contains("?"), var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        var basePath = components.percentEncodedPath
        if basePath.hasSuffix("/") { basePath.removeLast() }
        components.percentEncodedPath = basePath + key
        components.queryItems = nil
        return components.url
    }

    /// Headers for the player's asset: identity plus the token (the only place it goes), and the session.
    public func playbackHeaders(token: String, sessionID: String) -> [String: String] {
        var headers = identity.headers(token: token)
        headers["Accept"] = nil
        headers["X-Plex-Session-Identifier"] = sessionID
        return headers
    }

    /// Headers for a theme tune's asset (WP-11): identity plus the token, never in the URL.
    public func themeHeaders(token: String) -> [String: String] {
        var headers = identity.headers(token: token)
        headers["Accept"] = nil
        return headers
    }

    /// The query shared by `decision` and `start.m3u8` (the server wants the same items on both).
    /// Never carries the token. Items after Dusk's parameter set; the profile extra gives the HLS target
    /// ("Generic" alone gave decision 4005 on the live server).
    public func transcodeQuery(
        ratingKey: String, mediaIndex: Int, directStream: Bool, directStreamAudio: Bool,
        sessionID: String, subtitles: String?, subtitleStreamID: Int?, offsetSeconds: Int?
    ) -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            .init(name: "hasMDE", value: "1"),
            .init(name: "path", value: "/library/metadata/\(ratingKey)"),
            .init(name: "mediaIndex", value: String(mediaIndex)),
            .init(name: "partIndex", value: "0"),
            .init(name: "protocol", value: "hls"),
            .init(name: "fastSeek", value: "1"),
            .init(name: "directPlay", value: "0"),
            .init(name: "directStream", value: directStream ? "1" : "0"),
            .init(name: "directStreamAudio", value: directStreamAudio ? "1" : "0"),
            .init(name: "location", value: "lan"),
            .init(name: "autoAdjustQuality", value: "0"),
            .init(name: "mediaBufferSize", value: "102400"),
            .init(name: "session", value: sessionID),
            .init(name: "transcodeSessionId", value: sessionID),
            .init(name: "copyts", value: "1"),
            .init(name: "X-Plex-Session-Identifier", value: sessionID),
            .init(
                name: "X-Plex-Client-Profile-Extra",
                value:
                    "add-transcode-target(type=videoProfile&context=streaming&protocol=hls&container=mpegts&videoCodec=h264,hevc&audioCodec=aac,ac3,eac3)"),
            .init(name: "X-Plex-Incomplete-Segments", value: "1"),
        ]
        if let subtitles { items.append(.init(name: "subtitles", value: subtitles)) }
        if let subtitleStreamID { items.append(.init(name: "subtitleStreamID", value: String(subtitleStreamID))) }
        if let offsetSeconds, offsetSeconds > 0 { items.append(.init(name: "offset", value: String(offsetSeconds))) }
        // Client identity (never the token) as query items too, as Dusk sends it.
        let headers = identity.headers()
        for key in ["X-Plex-Product", "X-Plex-Version", "X-Plex-Client-Identifier", "X-Plex-Platform", "X-Plex-Device"] {
            if let value = headers[key] { items.append(.init(name: key, value: value)) }
        }
        return items
    }

    public func transcodeDecision(base: URL, token: String, query: [URLQueryItem]) -> URLRequest {
        libraryRequest(base: base, token: token, path: "/video/:/transcode/universal/decision", query: query)
    }

    /// The HLS start playlist URL for the same query. No token in it.
    public func transcodeStartURL(base: URL, query: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        var basePath = components.percentEncodedPath
        if basePath.hasSuffix("/") { basePath.removeLast() }
        components.percentEncodedPath = basePath + "/video/:/transcode/universal/start.m3u8"
        components.queryItems = query
        return components.url
    }

    public func transcodeStop(base: URL, token: String, sessionID: String) -> URLRequest {
        libraryRequest(
            base: base, token: token, path: "/video/:/transcode/universal/stop",
            query: [.init(name: "session", value: sessionID)])
    }
}
