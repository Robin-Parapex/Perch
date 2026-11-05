import Observation
import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI

/// Home's shell: picks the profile, keeps one model per profile, hosts the profile picker, the DEBUG gallery
/// and the "Run setup again" flow. The screen itself is `HomeView`.
struct HomeScreen: View {
    private enum Route: Hashable {
        case picker
        #if DEBUG
        case gallery
        #endif
    }

    let core: CoreServices
    @State private var flow: SetupRerunFlow
    @State private var path = HomeScreen.initialPath()
    /// The profile when the session state carries none (server unreachable), read once from the session.
    @State private var fallbackProfile: PlexActiveProfile?
    @State private var resolving: Bool

    init(core: CoreServices, onRunSetupAgain: @escaping () -> Void) {
        self.core = core
        _flow = State(initialValue: SetupRerunFlow(core: core, onRunSetupAgain: onRunSetupAgain))
        if case .ready = core.plexSignIn.snapshot.state {
            _resolving = State(initialValue: false)
        } else {
            _resolving = State(initialValue: HomeStore.shared.current == nil)
        }
    }

    private static func initialPath() -> NavigationPath {
        var path = NavigationPath()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PerchDesignGallery") { path.append(Route.gallery) }
        #endif
        return path
    }

    private var activeProfile: PlexActiveProfile? {
        if case .ready(let profile, _) = core.plexSignIn.snapshot.state { return profile }
        return fallbackProfile ?? HomeStore.shared.current?.home.profile
    }

    var body: some View {
        let entry = activeProfile.map { HomeStore.shared.entry(for: $0, core: core) }
        NavigationStack(path: $path) {
            Group {
                if let entry {
                    HomeView(
                        core: core, home: entry.home, model: entry.model,
                        onSwitchProfile: { path.append(Route.picker) },
                        onRunSetup: { Task { await flow.open(profile: entry.home.profile) } },
                        onGallery: galleryAction
                    )
                    .id(entry.home.profile.id)
                } else if resolving {
                    Color.clear
                } else {
                    HomeView(
                        core: core, home: nil, model: HomeStore.shared.noProfileModel(core: core),
                        onSwitchProfile: { path.append(Route.picker) }, onRunSetup: {}, onGallery: galleryAction)
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .picker:
                    ProfilePickerView(core: core, onBack: { popPicker() }, onDone: { popPicker() })
                #if DEBUG
                case .gallery:
                    DesignGallery()
                #endif
                }
            }
        }
        .setupRerunFlow(flow, name: activeProfile?.displayName)
        .environment(\.perchStyle, entry?.home.isKid == true ? .kids : .standard)
        .task(id: core.plexSignIn.snapshot.state) {
            if case .ready = core.plexSignIn.snapshot.state {
                resolving = false
                return
            }
            if let profile = await core.plexSignIn.session.currentProfile() { fallbackProfile = profile }
            resolving = false
        }
    }

    private var galleryAction: (() -> Void)? {
        #if DEBUG
        { path.append(Route.gallery) }
        #else
        nil
        #endif
    }

    private func popPicker() {
        if !path.isEmpty { path.removeLast() }
    }
}

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
