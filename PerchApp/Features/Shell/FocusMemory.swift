import Foundation

/// Where focus last was on each screen, in memory, per profile (DESIGN: "every screen remembers its last focused
/// item; Back lands there"; the FocusCoordinator idea from Swiftfin, reimplemented). One app-level store keyed by
/// profile and screen, so a tab switch, a pushed screen or the picker never loses the place. Generalised from
/// WP-09's HomeFocusMemory in WP-13.
@MainActor
final class FocusMemory {
    static let shared = FocusMemory()

    /// A profile's screen. `screen` is a stable id ("home", "films", a title page's "title.<id>").
    struct Scope: Hashable {
        let profileID: String
        let screen: String
    }

    private var last: [Scope: AnyHashable] = [:]
    /// Last focused item per group (a row) on a screen.
    private var itemByGroup: [Scope: [String: String]] = [:]

    /// Records the screen's current focus; `group` and `item` also remember the item for that group (a row's card).
    func record<Focus: Hashable>(_ focus: Focus, in scope: Scope, group: String? = nil, item: String? = nil) {
        last[scope] = AnyHashable(focus)
        if let group, let item { itemByGroup[scope, default: [:]][group] = item }
    }

    /// The screen's last focus, when it was recorded with this type.
    func lastFocus<Focus: Hashable>(_ type: Focus.Type = Focus.self, in scope: Scope) -> Focus? {
        last[scope]?.base as? Focus
    }

    func rememberedItem(group: String, in scope: Scope) -> String? { itemByGroup[scope]?[group] }

    /// Forgets one screen (for example a title page that no longer exists).
    func forget(_ scope: Scope) {
        last[scope] = nil
        itemByGroup[scope] = nil
    }
}
