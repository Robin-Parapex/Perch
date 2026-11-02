import PerchCore
import SwiftUI

/// Plex as a PerchCore module. No contributions yet; later WPs add rows, tabs and the player.
@MainActor
public final class PlexModule: Module {
    public static let id = ModuleID("plex")

    private let session: PlexSession
    private var snapshot = PlexSessionSnapshot(
        state: .signedOut, plexTVReachable: true, profileSwitchingAvailable: true)

    public init(session: PlexSession) {
        self.session = session
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

    public func contributions() -> [Contribution] { [] }

    public func policy(for action: ActionID) -> ActionPolicy? { nil }
}
