import SwiftUI

/// Holds the composed modules and exposes their contributions by kind.
@MainActor
public final class ModuleRegistry {
    public let modules: [any Module]

    /// Duplicate module ids: the first is kept, later ones are ignored.
    public init(modules: [any Module]) {
        var seen = Set<ModuleID>()
        var unique: [any Module] = []
        for module in modules where seen.insert(type(of: module).id).inserted {
            unique.append(module)
        }
        self.modules = unique
    }

    public func module(id: ModuleID) -> (any Module)? {
        modules.first { type(of: $0).id == id }
    }

    public func contributions() -> [Contribution] {
        modules.flatMap { $0.contributions() }
    }

    public var rowProviders: [any RowProvider] {
        contributions().compactMap { if case .row(let v) = $0 { v } else { nil } }
    }
    public var tabs: [any TabProvider] {
        contributions().compactMap { if case .tab(let v) = $0 { v } else { nil } }
            .sorted { ($0.order, $0.title) < ($1.order, $1.title) }
    }
    public var overlayProviders: [any OverlayProvider] {
        contributions().compactMap { if case .overlay(let v) = $0 { v } else { nil } }
    }
    public var eventSources: [any EventSource] {
        contributions().compactMap { if case .eventSource(let v) = $0 { v } else { nil } }
    }
    public var playerHooks: [any PlayerHook] {
        contributions().compactMap { if case .playerHook(let v) = $0 { v } else { nil } }
    }
    public var settingsPages: [any SettingsPage] {
        contributions().compactMap { if case .settingsPage(let v) = $0 { v } else { nil } }
    }
    public var adminPanels: [any AdminPanel] {
        contributions().compactMap { if case .adminPanel(let v) = $0 { v } else { nil } }
    }
    public var pollers: [Poller] {
        contributions().compactMap { if case .poller(let v) = $0 { v } else { nil } }
    }
    public var titleActionProviders: [any TitleActionProvider] {
        contributions().compactMap { if case .titleAction(let v) = $0 { v } else { nil } }
    }
    public var searchProviders: [any SearchProvider] {
        contributions().compactMap { if case .search(let v) = $0 { v } else { nil } }
    }

    /// Routes by the part of the action id before the first ".". Nil if no such module.
    public func policy(for action: ActionID) -> ActionPolicy? {
        guard let dot = action.rawValue.firstIndex(of: ".") else { return nil }
        let prefix = ModuleID(String(action.rawValue[..<dot]))
        return module(id: prefix)?.policy(for: action)
    }
}
