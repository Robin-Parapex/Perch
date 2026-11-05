import SwiftUI
import Testing

@testable import PerchCore

private struct FakeRow: RowProvider {
    let id = "fake.row"
    let title = "Fake"
    let placement = RowPlacement.home(order: 1)
    func cachedRow(in context: RowContext) -> MediaRow? { nil }
    func refreshRow(in context: RowContext) async throws -> MediaRow {
        MediaRow(id: id, title: title, items: [])
    }
}

private struct FakeTab: TabProvider {
    let id: String
    let title: String
    let systemImage = "star"
    let order: Int
    @MainActor func makeView() -> AnyView { AnyView(EmptyView()) }
}

@MainActor
private final class FakeModule: Module {
    static let id: ModuleID = "fake"
    let status = ModuleStatus.ok
    let poller = Poller(id: "fake.poll", policy: .fixed(.seconds(60))) {}
    func settings() -> AnyView { AnyView(EmptyView()) }
    func testConnection() async -> TestResult { .success(nil) }
    func contributions() -> [Contribution] {
        [
            .row(FakeRow()),
            .tab(FakeTab(id: "t2", title: "B", order: 2)),
            .tab(FakeTab(id: "t1b", title: "Z", order: 1)),
            .tab(FakeTab(id: "t1a", title: "A", order: 1)),
            .poller(poller),
        ]
    }
    func policy(for action: ActionID) -> ActionPolicy? {
        action.rawValue == "fake.doThing" ? .parentOnly : nil
    }
}

/// Same id as FakeModule, to test duplicate handling.
@MainActor
private final class DuplicateModule: Module {
    static let id: ModuleID = "fake"
    let status = ModuleStatus.notConfigured
    func settings() -> AnyView { AnyView(EmptyView()) }
    func testConnection() async -> TestResult { .failure("no") }
    func contributions() -> [Contribution] { [] }
    func policy(for action: ActionID) -> ActionPolicy? { nil }
}

@MainActor
struct ModuleRegistryTests {
    @Test func contributionsAndTypedAccessors() {
        let registry = ModuleRegistry(modules: [FakeModule()])
        #expect(registry.contributions().count == 5)
        #expect(registry.rowProviders.map(\.id) == ["fake.row"])
        #expect(registry.pollers.map(\.id) == ["fake.poll"])
        #expect(registry.overlayProviders.isEmpty)
    }

    @Test func tabsSortedByOrderThenTitle() {
        let registry = ModuleRegistry(modules: [FakeModule()])
        #expect(registry.tabs.map(\.id) == ["t1a", "t1b", "t2"])
    }

    @Test func duplicateIDIgnored() {
        let registry = ModuleRegistry(modules: [FakeModule(), DuplicateModule()])
        #expect(registry.modules.count == 1)
        #expect(registry.module(id: "fake")?.status == .ok)
        #expect(registry.module(id: "nope") == nil)
    }

    @Test func policyRouting() {
        let registry = ModuleRegistry(modules: [FakeModule()])
        #expect(registry.policy(for: "fake.doThing") == .parentOnly)
        #expect(registry.policy(for: "fake.other") == nil)
        #expect(registry.policy(for: "other.x") == nil)
        #expect(registry.policy(for: "nodot") == nil)
    }
}

private struct OrderedRow: RowProvider {
    let id: String
    let placement: RowPlacement
    var title: String { id }
    func cachedRow(in context: RowContext) -> MediaRow? { nil }
    func refreshRow(in context: RowContext) async throws -> MediaRow {
        MediaRow(id: id, title: title, items: [])
    }
}

@MainActor
private final class HomeRowsModule: Module {
    static let id: ModuleID = "homerows"
    let status = ModuleStatus.ok
    func settings() -> AnyView { AnyView(EmptyView()) }
    func testConnection() async -> TestResult { .success(nil) }
    func contributions() -> [Contribution] {
        [
            .row(OrderedRow(id: "c", placement: .home(order: 2))),
            .row(OrderedRow(id: "title", placement: .titlePage)),
            .row(OrderedRow(id: "b", placement: .home(order: 1))),
            .row(OrderedRow(id: "a", placement: .home(order: 1))),
            .row(OrderedRow(id: "person", placement: .personPage)),
        ]
    }
    func policy(for action: ActionID) -> ActionPolicy? { nil }
}

@MainActor
struct HomeRowProviderTests {
    @Test func homeRowProvidersSortByOrderThenIDAndExcludeOtherPlacements() {
        let registry = ModuleRegistry(modules: [HomeRowsModule()])
        #expect(registry.homeRowProviders.map(\.id) == ["a", "b", "c"])
        #expect(registry.rowProviders.count == 5)
    }
}
