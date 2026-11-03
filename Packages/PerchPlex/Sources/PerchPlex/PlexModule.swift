import PerchCore
import SwiftUI

/// Plex as a PerchCore module. Contributes the three Home rows; later WPs add tabs and the player.
@MainActor
public final class PlexModule: Module {
    public static let id = ModuleID("plex")

    private let session: PlexSession
    private let library: PlexLibrary?
    private var snapshot = PlexSessionSnapshot(
        state: .signedOut, plexTVReachable: true, profileSwitchingAvailable: true)

    public init(session: PlexSession, library: PlexLibrary? = nil) {
        self.session = session
        self.library = library
        Task { [weak self] in
            for await update in await session.updates() {
                guard let self else { return }
                self.snapshot = update
            }
        }
    }

    public var status: ModuleStatus {
        switch snapshot.state {
        case .signedOut: .notConfigured
        case .connecting: .degraded("Connecting")
        case .ready: snapshot.plexTVReachable ? .ok : .degraded("Profile PINs can't be checked right now")
        case .serverUnreachable: .error("Can't reach your library right now")
        }
    }

    public func settings() -> AnyView { AnyView(EmptyView()) }

    public func testConnection() async -> TestResult { await session.testServerConnection() }

    public func contributions() -> [Contribution] {
        guard let library else { return [] }
        return [
            (PlexHomeRows.continueWatchingID, "Continue watching", 0),
            (PlexHomeRows.upNextID, "Up next in your series", 1),
            (PlexHomeRows.recentlyAddedID, "Recently added", 2),
        ].map { id, title, order in
            .row(PlexHomeRowProvider(id: id, title: title, placement: .home(order: order), library: library))
        }
    }

    public func policy(for action: ActionID) -> ActionPolicy? { nil }
}
