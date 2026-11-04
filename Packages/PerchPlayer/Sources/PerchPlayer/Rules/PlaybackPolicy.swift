import Foundation

/// Playback behaviour switches. These are defaults until per-profile settings arrive in WP-18.
public struct PlaybackPolicy: Sendable, Equatable {
    public var autoSkipIntro: Bool
    public var autoSkipCredits: Bool
    public var autoplayNext: Bool
    public var upNextCountdownSeconds: Int
    /// Consecutive automatic advances allowed before asking "Are you still watching?".
    public var stillWatchingAfter: Int
    public var skipPadMs: Int
    public var autoSkipCountdownSeconds: Int

    public init(
        autoSkipIntro: Bool = false, autoSkipCredits: Bool = false, autoplayNext: Bool = true,
        upNextCountdownSeconds: Int = 10, stillWatchingAfter: Int = 3, skipPadMs: Int = 500,
        autoSkipCountdownSeconds: Int = 5
    ) {
        self.autoSkipIntro = autoSkipIntro
        self.autoSkipCredits = autoSkipCredits
        self.autoplayNext = autoplayNext
        self.upNextCountdownSeconds = upNextCountdownSeconds
        self.stillWatchingAfter = stillWatchingAfter
        self.skipPadMs = skipPadMs
        self.autoSkipCountdownSeconds = autoSkipCountdownSeconds
    }

    public static let household = PlaybackPolicy()
}
