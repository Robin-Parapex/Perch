import Foundation
import PerchCore

/// A "Skip intro" or "Skip credits" button the player should show right now.
public struct SkipOffer: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case intro, credits }

    public var kind: Kind
    public var markerID: String
    public var targetMs: Int
    /// Set only when the policy auto-skips this kind and the marker has not auto-skipped yet.
    public var autoSkipAfterSeconds: Int?

    public init(kind: Kind, markerID: String, targetMs: Int, autoSkipAfterSeconds: Int? = nil) {
        self.kind = kind
        self.markerID = markerID
        self.targetMs = targetMs
        self.autoSkipAfterSeconds = autoSkipAfterSeconds
    }
}

// Approach from Dusk (MIT): one auto-skip per marker, 0.5 s pad.
public struct SkipRules: Sendable {
    private let markers: [MediaMarker]
    private let durationMs: Int?
    private let policy: PlaybackPolicy
    private var spent: Set<String> = []

    public init(markers: [MediaMarker], durationMs: Int?, policy: PlaybackPolicy = .household) {
        self.markers = markers
        self.durationMs = durationMs
        self.policy = policy
    }

    public static func markerID(kind: SkipOffer.Kind, startMs: Int) -> String {
        "\(kind == .intro ? "intro" : "credits")-\(startMs)"
    }

    /// The offer for this position, or nil. Never offers while seeking. The final credits marker
    /// never offers a skip because up-next handles it.
    public mutating func offer(atMs positionMs: Int, isSeeking: Bool) -> SkipOffer? {
        guard !isSeeking else { return nil }
        for marker in markers where positionMs >= marker.startMs && positionMs < marker.endMs {
            let kind: SkipOffer.Kind
            switch marker.kind {
            case .intro: kind = .intro
            case .credits:
                guard !marker.isFinal else { continue }
                kind = .credits
            case .other: continue
            }
            let id = Self.markerID(kind: kind, startMs: marker.startMs)
            var target = marker.endMs + policy.skipPadMs
            if let durationMs { target = min(target, durationMs - 1000) }
            let autoOn = kind == .intro ? policy.autoSkipIntro : policy.autoSkipCredits
            let auto = autoOn && !spent.contains(id) ? policy.autoSkipCountdownSeconds : nil
            return SkipOffer(kind: kind, markerID: id, targetMs: target, autoSkipAfterSeconds: auto)
        }
        return nil
    }

    /// Call once the offer was taken or auto-skipped; it will not auto-skip again this session.
    public mutating func markSpent(_ markerID: String) {
        spent.insert(markerID)
    }
}
