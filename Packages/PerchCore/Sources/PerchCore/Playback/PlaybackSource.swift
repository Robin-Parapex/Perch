import Foundation

/// Everything the player needs to start one item. The URL and headers carry the Plex token, so the
/// descriptions print the URL path and header names only.
public struct PlaybackSource: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var ratingKey: String
    public var title: String
    public var url: URL
    public var headers: [String: String]
    public var decision: PlaybackDecision
    public var startMs: Int
    public var durationMs: Int?
    public var sessionID: String
    public var markers: [MediaMarker]
    public var isTranscodeSession: Bool

    public init(
        ratingKey: String, title: String, url: URL, headers: [String: String] = [:],
        decision: PlaybackDecision, startMs: Int = 0, durationMs: Int? = nil, sessionID: String,
        markers: [MediaMarker] = [], isTranscodeSession: Bool = false
    ) {
        self.ratingKey = ratingKey
        self.title = title
        self.url = url
        self.headers = headers
        self.decision = decision
        self.startMs = startMs
        self.durationMs = durationMs
        self.sessionID = sessionID
        self.markers = markers
        self.isTranscodeSession = isTranscodeSession
    }

    public var description: String {
        let names = headers.keys.sorted().joined(separator: ", ")
        return "PlaybackSource(ratingKey: \(ratingKey), title: \(title), path: \(url.path), "
            + "headers: [\(names)], method: \(decision.method.rawValue), startMs: \(startMs), "
            + "session: \(sessionID), transcode: \(isTranscodeSession))"
    }

    public var debugDescription: String { description }
}
