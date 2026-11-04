import Foundation
import PerchCore
import UIKit

/// What the info panel shows for the item (title, episode line, description, artwork).
public struct PlayerItemMetadata: Sendable, Equatable {
    public var title: String
    public var subtitle: String?
    public var summary: String?
    public var artworkData: Data?

    public init(title: String, subtitle: String? = nil, summary: String? = nil, artworkData: Data? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.summary = summary
        self.artworkData = artworkData
    }
}

/// The next item the app offers at the credits. `ratingKey` is opaque to the player.
public struct UpNextProposal: Sendable, Equatable {
    public var title: String
    public var subtitle: String?
    public var previewImageData: Data?
    public var ratingKey: String

    public init(title: String, subtitle: String? = nil, previewImageData: Data? = nil, ratingKey: String) {
        self.title = title
        self.subtitle = subtitle
        self.previewImageData = previewImageData
        self.ratingKey = ratingKey
    }
}

/// How an up-next proposal was accepted: the user pressed Play, or the countdown ran out.
public enum UpNextAcceptance: Sendable, Equatable {
    case user, countdown
}

/// What an engine tells the session. `positionTick` arrives about every 0.5 s while an item is loaded.
public enum EngineEvent: Sendable, Equatable {
    case playing, paused, buffering, ended
    case failed(String)
    /// Any remote press or touch-surface gesture.
    case userInput
    case positionTick(Int)
}

/// The seam between the session and a player engine. 1.x has `NativeEngine` (AVKit); the 2.0 FFmpeg
/// engine implements the same protocol with its own chrome, so nothing engine-specific leaks above it.
@MainActor
public protocol PlaybackEngine: AnyObject {
    /// Short engine name for the playback log ("native").
    var name: String { get }
    var viewController: UIViewController { get }
    var positionMs: Int { get }
    /// One stream for the engine's lifetime (it spans every item loaded); finishes at `teardown()`.
    var events: AsyncStream<EngineEvent> { get }

    /// Prepares the item until it is ready, then seeks with zero tolerance to `source.startMs`.
    /// Does not start playback.
    func load(_ source: PlaybackSource, metadata: PlayerItemMetadata) async throws
    func play()
    func pause()
    func seek(toMs: Int) async

    /// Shows (or with nil hides) the engine's own Skip button.
    func showSkip(_ offer: SkipOffer?, onSkip: @escaping @MainActor () -> Void)
    /// Shows (or with nil hides) the engine's own up-next proposal. `.timed` counts down and accepts
    /// at 0 (`.countdown`); `.manual` waits for the user. Hiding with nil calls neither callback.
    func showUpNext(
        _ proposal: UpNextProposal?, mode: UpNextMode,
        onAccept: @escaping @MainActor (UpNextAcceptance) -> Void,
        onDismiss: @escaping @MainActor () -> Void)

    /// Stops playback, drops the item and observers, resets display criteria. Idempotent.
    func teardown()
}
