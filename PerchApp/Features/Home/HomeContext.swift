import Darwin
import Foundation
import OSLog
import PerchCore
import PerchPlex

/// Who Home is for, resolved without an await so the first frame can read the cached rows.
struct HomeProfile: Equatable {
    let profile: PlexActiveProfile
    /// Nil when the settings document has no entry for this profile yet.
    let role: Role?
    let context: RowContext

    var isKid: Bool { role == .kid }

    /// RowContext built as the WP-08 Library check did, with the Admin override from the settings document.
    static func resolve(_ profile: PlexActiveProfile, keyValues: any KeyValueStore) -> HomeProfile {
        let settings = settingsDocument(keyValues).profiles[profile.id]
        let context = RowContext(
            profileID: profile.id.rawValue, serviceCeiling: RatingCeiling(plex: profile.restriction),
            ceiling: RatingCeiling.effective(plex: profile.restriction, adminOverride: settings?.ceilingOverride))
        return HomeProfile(profile: profile, role: settings?.role, context: context)
    }

    /// The same read as `SettingsStore.document` (its default key, ISO 8601 dates, an empty document when the
    /// value is missing or unreadable), done synchronously: the store is an actor and Home must not await
    /// before its first frame. The store writes the same value synchronously, so the two cannot disagree.
    static func settingsDocument(_ keyValues: any KeyValueStore) -> SettingsDocument {
        guard let data = keyValues.data(forKey: "perch.settings.v1") else { return SettingsDocument() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(SettingsDocument.self, from: data)) ?? SettingsDocument()
    }

    /// One model source per Home provider, in the registry's order; every row passes the ceiling.
    @MainActor
    static func sources(_ providers: [any RowProvider], context: RowContext) -> [HomeModel.Source] {
        providers.map { provider in
            HomeModel.Source(
                id: provider.id,
                cached: { ModuleRegistry.cachedRow(provider, in: context) },
                refresh: { try await ModuleRegistry.refreshRow(provider, in: context) })
        }
    }
}

/// What can hold focus on Home.
enum HomeFocus: Hashable {
    case hero
    case profileMenu
    case card(row: String, item: String)

    var rowID: String? {
        if case .card(let row, _) = self { row } else { nil }
    }
}

/// Last focused card per row and the last focus on Home, in memory, per profile (spec 5; the
/// FocusCoordinator idea from Swiftfin, reimplemented).
@MainActor
final class HomeFocusMemory {
    static let shared = HomeFocusMemory()

    private var itemByRow: [String: [String: String]] = [:]
    private var last: [String: HomeFocus] = [:]

    func record(_ focus: HomeFocus, profileID: String) {
        last[profileID] = focus
        if case .card(let row, let item) = focus { itemByRow[profileID, default: [:]][row] = item }
    }

    func rememberedItem(row: String, profileID: String) -> String? { itemByRow[profileID]?[row] }

    func lastFocus(profileID: String) -> HomeFocus? { last[profileID] }
}

#if DEBUG
/// DEBUG launch signpost: `perch.launch home-first-frame=<ms>` once, from process start to the first Home frame.
@MainActor
enum LaunchSignpost {
    private static var logged = false
    private static let log = Logger(subsystem: "com.robrolabs.perch", category: "launch")

    static func homeFirstFrame() {
        guard !logged else { return }
        logged = true
        guard let start = processStart() else { return }
        let ms = Int((Date().timeIntervalSince(start) * 1000).rounded())
        log.notice("perch.launch home-first-frame=\(ms, privacy: .public)")
    }

    /// The kernel's start time for this process (kinfo_proc p_starttime).
    private static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
#endif
