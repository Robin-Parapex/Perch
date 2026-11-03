import Foundation

public enum PlaybackState: String, Codable, Sendable, Hashable {
    case playing, paused, buffering, stopped
}

/// Where a title stood at a moment of playback.
public struct PlaybackProgress: Codable, Sendable, Hashable {
    public var itemID: String
    public var state: PlaybackState
    public var positionMs: Int
    public var durationMs: Int?

    public init(itemID: String, state: PlaybackState, positionMs: Int, durationMs: Int?) {
        self.itemID = itemID
        self.state = state
        self.positionMs = positionMs
        self.durationMs = durationMs
    }
}

/// Reports one playback to the library that owns the title. The player depends on PerchCore
/// only (MODULES.md), so it reports through this. One reporter per playback; after `stop` it
/// sends nothing more. Positions are in ms.
public protocol PlaybackReporting: Sendable {
    var sessionID: String { get }
    func report(_ state: PlaybackState, positionMs: Int) async
    func stop(positionMs: Int) async
}
