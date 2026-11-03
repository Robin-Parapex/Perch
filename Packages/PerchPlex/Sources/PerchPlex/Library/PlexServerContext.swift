import Foundation
import PerchCore

/// Everything a library call needs to talk to the active server as the active profile.
///
/// The token is the server token for the current profile. It never leaves PerchPlex: this type is
/// internal, and results reaching other modules are neutral PerchCore types. A context whose
/// `generation` differs from `currentGeneration()` is stale (the profile, server or sign-in state
/// changed since it was made), and anything fetched with it must be dropped.
struct PlexServerContext: Sendable, Equatable {
    var baseURL: URL
    var token: String
    var profileID: String
    var machineID: String
    var generation: UInt64
}

/// What the library reads from the session. `PlexSession` conforms.
protocol PlexServerContextProviding: Sendable {
    /// The current context, or a `PlexError` when no server is ready.
    func libraryContext() async throws -> PlexServerContext
    /// Bumped whenever the profile, machine or base URL changes, or the session leaves ready.
    func currentGeneration() async -> UInt64
}

/// Where playback progress and watched changes go once the server has them, so a cache can follow
/// without refetching. Called only after the server accepted the send, and only while the sender's
/// context is still current. `generation` is the sender's own; an implementation ignores any call
/// whose generation is not the current one.
protocol PlexWatchStateSink: Sendable {
    func playbackProgressed(_ progress: PlaybackProgress, generation: UInt64) async
    func watchStateChanged(itemID: String, watched: Bool, generation: UInt64) async
}
