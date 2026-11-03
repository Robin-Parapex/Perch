import SwiftUI

public enum ModuleStatus: Sendable, Equatable {
    case notConfigured, ok, degraded(String), error(String)
}

public enum TestResult: Sendable, Equatable {
    case success(String?)
    case failure(String)
}

public enum RowPlacement: Sendable, Equatable {
    case home(order: Int)
    case titlePage
    case personPage
}

public enum PlayerEvent: Sendable, Equatable {
    case play, pause, credits, stop, failure(String)
}

// Extension points are thin for now; each later WP that first uses one fixes its shape.

/// A row on a page (shape fixed in WP-06). `cachedRow` answers at once from what the provider
/// last saw, so Home never waits (SPEC.md, never a spinner on Home); `refreshRow` fetches anew.
/// Read rows through `ModuleRegistry.cachedRow` and `refreshRow`, which apply the ceiling.
public protocol RowProvider: Sendable {
    var id: String { get }
    var title: String { get }
    var placement: RowPlacement { get }
    func cachedRow(in context: RowContext) -> MediaRow?
    func refreshRow(in context: RowContext) async throws -> MediaRow
}

/// An action on the title page. Shape to be fixed by the first WP that uses it.
public protocol TitleActionProvider: Sendable {
    var id: String { get }
    var title: String { get }
}

/// A search source. Shape to be fixed by the first WP that uses it.
public protocol SearchProvider: Sendable {
    var id: String { get }
    var title: String { get }
}

/// An overlay shown above the app for an event. Shape to be fixed by the first WP that uses it.
public protocol OverlayProvider: Sendable {
    var id: String { get }
    func handles(_ event: PerchEvent) -> Bool
    @MainActor func overlay(for event: PerchEvent) -> AnyView?
}

/// A source of events (polling, sockets). Shape to be fixed by the first WP that uses it.
public protocol EventSource: Sendable {
    var id: String { get }
    func start(publishingTo bus: EventBus) async
    func stop() async
}

/// Reacts to player events. Shape to be fixed by the first WP that uses it.
public protocol PlayerHook: Sendable {
    var id: String { get }
    func handle(_ event: PlayerEvent) async
}

/// A Settings page. Shape to be fixed by the first WP that uses it.
public protocol SettingsPage: Sendable {
    var id: String { get }
    var title: String { get }
    @MainActor func makeView() -> AnyView
}

/// An Admin panel. Shape to be fixed by the first WP that uses it.
public protocol AdminPanel: Sendable {
    var id: String { get }
    var title: String { get }
    @MainActor func makeView() -> AnyView
}

/// A sidebar tab added by a module. Shape to be fixed by the first WP that uses it.
public protocol TabProvider: Sendable {
    var id: String { get }
    var title: String { get }
    var systemImage: String { get }
    var order: Int { get }
    @MainActor func makeView() -> AnyView
}

public enum Contribution: Sendable {
    case row(any RowProvider)
    case titleAction(any TitleActionProvider)
    case search(any SearchProvider)
    case overlay(any OverlayProvider)
    case eventSource(any EventSource)
    case playerHook(any PlayerHook)
    case settingsPage(any SettingsPage)
    case adminPanel(any AdminPanel)
    case tab(any TabProvider)
    case poller(Poller)
}

/// An optional integration composed by the app at launch.
/// `settings()` is the module's settings page and is Admin PIN gated by the host.
/// `policy(for:)` replaces MODULES.md's `requiredRole(for:)` (DECISIONS.md, WP-02); nil means an
/// unknown action, which the core denies.
@MainActor
public protocol Module: AnyObject {
    static var id: ModuleID { get }
    var status: ModuleStatus { get }
    func settings() -> AnyView
    func testConnection() async -> TestResult
    func contributions() -> [Contribution]
    func policy(for action: ActionID) -> ActionPolicy?
}
