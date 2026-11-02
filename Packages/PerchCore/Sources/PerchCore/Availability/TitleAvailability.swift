import Foundation

/// Where a title stands, in the words the family sees. No service names appear here.
public enum TitleAvailability: Sendable, Hashable {
    case requested
    /// `progress` is 0...1 when known.
    case gettingReady(progress: Double?)
    case someEpisodesReady
    case readyToWatch
    case notFound

    /// The user-facing label (GLOSSARY.md). Kids see "Waiting for a parent" for a pending request.
    public func label(forKids: Bool = false) -> String {
        switch self {
        case .requested: forKids ? "Waiting for a parent" : "Requested"
        case .gettingReady: "Getting it ready"
        case .someEpisodesReady: "Some episodes ready"
        case .readyToWatch: "Ready to watch"
        case .notFound: "Couldn't find this yet"
        }
    }

    /// Progress clamped to 0...1; only present for `gettingReady` with a known value.
    public var progress: Double? {
        guard case .gettingReady(let value?) = self, !value.isNaN else { return nil }
        return min(max(value, 0), 1)
    }
}
