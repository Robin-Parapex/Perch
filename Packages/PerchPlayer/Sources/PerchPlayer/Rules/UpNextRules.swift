import Foundation
import PerchCore

public enum UpNextMode: Sendable, Equatable {
    case timed(seconds: Int)
    case manual
}

public enum UpNextPhase: Sendable, Equatable {
    case idle
    case proposed(UpNextMode)
    case dismissed
}

public enum EndAction: Sendable, Equatable {
    case advance, stillWatching, stop
}

// Approach from Dusk (MIT): estimated credits are manual-only; pass-out limit.
public struct UpNextRules: Sendable {
    private let hasNext: Bool
    private let policy: PlaybackPolicy
    private let autoChainCount: Int
    public let creditsStartMs: Int?
    public let isEstimated: Bool
    private var dismissed = false
    private var timedSpent = false

    public init(
        markers: [MediaMarker], durationMs: Int?, hasNext: Bool, policy: PlaybackPolicy = .household,
        autoChainCount: Int
    ) {
        self.hasNext = hasNext
        self.policy = policy
        self.autoChainCount = autoChainCount
        if let final = markers.first(where: { $0.kind == .credits && $0.isFinal }) {
            creditsStartMs = final.startMs
            isEstimated = false
        } else if let durationMs, durationMs >= 5 * 60_000 {
            creditsStartMs = durationMs - min(max(durationMs * 4 / 100, 45_000), 120_000)
            isEstimated = true
        } else {
            creditsStartMs = nil
            isEstimated = false
        }
    }

    public mutating func phase(atMs positionMs: Int) -> UpNextPhase {
        guard hasNext, let start = creditsStartMs, positionMs >= start else {
            dismissed = false
            return .idle
        }
        if dismissed { return .dismissed }
        if !isEstimated, !timedSpent, policy.autoplayNext, autoChainCount < policy.stillWatchingAfter {
            return .proposed(.timed(seconds: policy.upNextCountdownSeconds))
        }
        return .proposed(.manual)
    }

    /// The user dismissed the proposal. It stays dismissed here and never runs timed again.
    public mutating func dismiss() {
        dismissed = true
        timedSpent = true
    }

    /// For an item that ends without an accepted proposal. A dismissed proposal means stop (Back cancels).
    public func endAction() -> EndAction {
        guard hasNext, !dismissed, policy.autoplayNext else { return .stop }
        return autoChainCount >= policy.stillWatchingAfter ? .stillWatching : .advance
    }
}
