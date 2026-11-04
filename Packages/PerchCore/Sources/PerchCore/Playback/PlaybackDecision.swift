import Foundation

/// How a title reaches the screen, from least to most server work (ARCHITECTURE.md, decision table).
public enum PlaybackMethod: String, Codable, Sendable {
    case directPlay, directStream, audioTranscode, transcode
}

public enum VideoRange: String, Codable, Sendable {
    case sdr, hdr10, hdr10Plus, dolbyVision
}

/// The subtitle track in use, if any. Text subtitles are shown by the player; image subtitles are burned in.
public enum SubtitleChoice: Codable, Sendable, Equatable {
    case none
    case text(streamID: Int)
    case burnIn(streamID: Int)
}

/// What the decision table chose for one playback, and why. Kept plain so it can go in the log.
public struct PlaybackDecision: Codable, Sendable, Equatable {
    public var method: PlaybackMethod
    /// One plain line per table row that applied.
    public var reasons: [String]
    public var videoRange: VideoRange
    public var dolbyVisionProfile: Int?
    public var frameRate: Double?
    public var width: Int?
    public var height: Int?
    public var subtitle: SubtitleChoice
    /// What is lost or changed, e.g. "Atmos lost", "Dolby Vision 7 plays as HDR10".
    public var notes: [String]
    /// Whether the chosen audio track goes through untouched (AAC, AC3, EAC3) when the server repackages
    /// or transcodes the video. True when there is no audio track.
    public var audioPassthrough: Bool

    public init(
        method: PlaybackMethod, reasons: [String] = [], videoRange: VideoRange = .sdr,
        dolbyVisionProfile: Int? = nil, frameRate: Double? = nil, width: Int? = nil,
        height: Int? = nil, subtitle: SubtitleChoice = .none, notes: [String] = [],
        audioPassthrough: Bool = true
    ) {
        self.method = method
        self.reasons = reasons
        self.videoRange = videoRange
        self.dolbyVisionProfile = dolbyVisionProfile
        self.frameRate = frameRate
        self.width = width
        self.height = height
        self.subtitle = subtitle
        self.notes = notes
        self.audioPassthrough = audioPassthrough
    }
}
