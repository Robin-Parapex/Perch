import Foundation
import PerchCore

/// Why a stream could not be prepared. The text is the server's decision wording, never a URL.
public enum PlexPlaybackError: Error, Equatable, Sendable {
    case noPlayableVersion
    case transcodeRefused(String)
}

/// A theme tune the app can open with `AVURLAsset` (WP-11): the token is only in `headers`.
public struct PlexThemeSource: Sendable, Equatable {
    public let url: URL
    public let headers: [String: String]

    public init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }
}

extension PlexLibrary {
    /// The theme tune of a title (`/library/metadata/<key>/theme/...`, INTEGRATIONS), authorised like playback.
    /// Nil unless `path` is a plain server path.
    public func themeSource(ratingKey: String, path: String) async throws -> PlexThemeSource? {
        let context = try await current()
        try await authorisePlay(context, entity: ratingKey)
        guard let path = PlexLibraryMapping.themePath(path),
            let url = endpoints.directPlayURL(base: context.baseURL, partKey: path)
        else { return nil }
        return PlexThemeSource(url: url, headers: endpoints.themeHeaders(token: context.token))
    }

    /// Turns a rating key into something the player can open. The token travels only in `headers`,
    /// never in the URL. Request shapes proven on the live server in the WP-07 spike (after Dusk, MIT).
    public func playbackSource(
        for ratingKey: String, startMs: Int?, subtitleStreamID: Int?,
        sessionID: String = UUID().uuidString
    ) async throws -> PlaybackSource {
        let startedAt = ContinuousClock.now
        let context = try await current()
        try await authorisePlay(context, entity: ratingKey)
        let detail = try await detailForPlayback(ratingKey: ratingKey)
        let detailAt = ContinuousClock.now

        let versions = detail.versions
        let index =
            versions.firstIndex { $0.parts.first?.isAccessible == true }
            ?? (versions.isEmpty ? nil : 0)
        guard let index, let part = versions[index].parts.first else {
            throw PlexPlaybackError.noPlayableVersion
        }
        let version = versions[index]
        let decision = PlexPlaybackDecider.decide(version: version, subtitleStreamID: subtitleStreamID)
        let headers = endpoints.playbackHeaders(token: context.token, sessionID: sessionID)

        let url: URL
        let isTranscode = decision.method != .directPlay
        if !isTranscode {
            guard let key = part.key, let direct = endpoints.directPlayURL(base: context.baseURL, partKey: key)
            else { throw PlexPlaybackError.noPlayableVersion }
            url = direct
        } else {
            var subtitles: String?
            var streamID: Int?
            switch decision.subtitle {
            case .none: break
            case .text(let id): subtitles = "auto"; streamID = id
            case .burnIn(let id): subtitles = "burn"; streamID = id
            }
            let query = endpoints.transcodeQuery(
                ratingKey: ratingKey, mediaIndex: index,
                directStream: decision.method != .transcode,
                // From the audio dimension: a video transcode still copies AAC/AC3/EAC3 (keeps Atmos).
                directStreamAudio: decision.audioPassthrough,
                sessionID: sessionID, subtitles: subtitles, subtitleStreamID: streamID,
                offsetSeconds: startMs.map { $0 / 1000 })
            let body = try await transport.perform(
                endpoints.transcodeDecision(base: context.baseURL, token: context.token, query: query),
                host: .server)
            try Self.requireAccepted(body)
            plexLog.info(
                "Playback source prep=\(Self.ms(startedAt, detailAt), privacy: .public)ms decision=\(Self.ms(detailAt, .now), privacy: .public)ms"
            )
            plexLog.info(
                "Playback decision range=\(decision.videoRange.rawValue, privacy: .public) dv=\(decision.dolbyVisionProfile.map(String.init) ?? "-", privacy: .public) server: \(Self.decisionSummary(body), privacy: .public)"
            )
            guard let start = endpoints.transcodeStartURL(base: context.baseURL, query: query) else {
                throw PlexError.decoding
            }
            url = start
        }

        let summary = detail.summary
        var title = summary.title
        if summary.kind == .episode, let series = summary.seriesTitle {
            var parts = [series]
            if let season = summary.seasonNumber, let episode = summary.episodeNumber {
                parts.append("S\(season)E\(episode)")
            }
            parts.append(summary.title)
            title = parts.joined(separator: " \u{00B7} ")
        }
        return PlaybackSource(
            ratingKey: ratingKey, title: title, url: url, headers: headers, decision: decision,
            startMs: max(0, startMs ?? 0), durationMs: part.durationMs ?? version.durationMs ?? summary.durationMs,
            sessionID: sessionID, markers: detail.markers, isTranscodeSession: isTranscode)
    }

    /// Ends the server's transcode session. Best effort: failures are logged (path only) and dropped.
    public func stopTranscode(sessionID: String) async {
        do {
            let context = try await current()
            _ = try await transport.perform(
                endpoints.transcodeStop(base: context.baseURL, token: context.token, sessionID: sessionID),
                host: .server)
        } catch {
            plexLog.error("transcode stop failed")
        }
    }

    private static func ms(_ from: ContinuousClock.Instant, _ to: ContinuousClock.Instant) -> Int {
        Int(((to - from) / .milliseconds(1)).rounded())
    }

    /// What the server will send, from named fields only (never the body, which carries paths):
    /// container, protocol and codecs of the media, then each stream's type, codec and copy/transcode.
    static func decisionSummary(_ body: Data) -> String {
        let container =
            (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["MediaContainer"]
            as? [String: Any]
        let media = ((container?["Metadata"] as? [[String: Any]])?.first?["Media"] as? [[String: Any]])?.first
        func field(_ dict: [String: Any]?, _ key: String) -> String { dict?[key].map { "\($0)" } ?? "-" }
        var parts = ["container", "protocol", "videoCodec", "audioCodec", "videoResolution", "bitrate"].map {
            "\($0)=\(field(media, $0))"
        }
        // The server's own reasons (plain wording, no paths).
        for key in ["directPlayDecisionText", "transcodeDecisionText", "generalDecisionText"] {
            parts.append("\(key)=\(field(container, key))")
        }
        let streams = ((media?["Part"] as? [[String: Any]])?.first?["Stream"] as? [[String: Any]]) ?? []
        for stream in streams {
            parts.append(
                "stream\(field(stream, "streamType"))=\(field(stream, "codec"))/\(field(stream, "decision"))")
        }
        return parts.joined(separator: " ")
    }

    /// Requires the general and the transcode decision codes in 1000..<2000.
    private static func requireAccepted(_ body: Data) throws {
        let container =
            (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["MediaContainer"]
            as? [String: Any]
        func code(_ name: String) -> Int? {
            (container?["\(name)Code"] as? Int) ?? (container?["\(name)Code"] as? String).flatMap(Int.init)
        }
        func text(_ name: String) -> String { "\(container?["\(name)Text"] ?? "-")" }
        let general = code("generalDecision"), transcode = code("transcodeDecision")
        guard let general, let transcode, (1000..<2000).contains(general), (1000..<2000).contains(transcode)
        else {
            let summary = ["generalDecision", "transcodeDecision"].map {
                "\($0)=\(code($0).map(String.init) ?? "-") \(text($0))"
            }.joined(separator: "; ")
            throw PlexPlaybackError.transcodeRefused(summary)
        }
    }
}
