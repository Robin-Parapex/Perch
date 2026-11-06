import Observation
import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI

/// One Home model per profile, kept while the profile is current so Home survives being re-routed (a
/// setup re-run, the picker) with its rows and refresh state. A new profile gets a new model.
@MainActor
final class HomeStore {
    static let shared = HomeStore()

    struct Entry {
        let home: HomeProfile
        let model: HomeModel
    }

    private(set) var current: Entry?
    private var noProfile: HomeModel?

    func entry(for profile: PlexActiveProfile, core: CoreServices) -> Entry {
        if let current, current.home.profile == profile { return current }
        let home = HomeProfile.resolve(profile, keyValues: core.keyValues)
        let model = HomeModel(
            sources: HomeProfile.sources(core.modules.homeRowProviders, context: home.context),
            isServerUnreachable: { core.plexSignIn.snapshot.state == .serverUnreachable })
        let entry = Entry(home: home, model: model)
        current = entry
        // Before the first frame: the hero's backdrop and logo, row 1's artwork and the page tint (spec 8).
        core.artworkPrefetcher.focus(item: model.heroItem)
        if let first = model.rows.first { HomeView.prefetch(first, with: core) }
        core.artworkTint.focus(model.heroItem)
        return entry
    }

    /// Home with no profile (the DEBUG gallery pin, or a session that lost its profile): no rows.
    func noProfileModel(core: CoreServices) -> HomeModel {
        if let noProfile { return noProfile }
        let model = HomeModel(sources: [], isServerUnreachable: { core.plexSignIn.snapshot.state == .serverUnreachable })
        noProfile = model
        return model
    }
}
