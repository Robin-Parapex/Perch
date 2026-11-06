import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI
import UIKit

/// The sidebar's tabs for 0.3 (SPEC 3). Requests, Music and House join in later versions.
enum MainTab: String, Hashable, CaseIterable {
    case home, films, series, search, settings
}

/// Screens pushed inside a tab's own stack.
enum ShellRoute: Hashable {
    #if DEBUG
    case gallery
    #endif
}

/// The app once a profile is chosen (WP-13): the Apple TV app's collapsible left sidebar (a sidebar-adaptable
/// `TabView`, DESIGN:44), the profile avatar at its top, one NavigationStack per tab. Back pops inside a tab; at a
/// tab's root it moves focus to the sidebar (the system's behaviour); in the sidebar the first Back shows a hint and
/// a second within two seconds leaves the app; double-tap Back returns to Home's root from anywhere (SPEC 3). The
/// sidebar takes the first focus at launch (tvOS 27; accepted, one Right from the hero). The picker and the Admin PIN keypad are full-screen
/// presentations over the whole shell. Profile resolution and the per-profile Home model moved here from
/// WP-09's HomeScreen.
struct MainShell: View {
    let core: CoreServices
    @State private var flow: SetupRerunFlow
    @State private var selection: MainTab = MainShell.initialTab
    @State private var paths: [MainTab: NavigationPath] = MainShell.initialPaths()
    @State private var pickerShown = false
    /// Bumped by double-tap Back: Home moves focus to its hero.
    @State private var homeRootRequest = 0
    /// Back in the sidebar was pressed once: the next press within `leaveWindow` leaves the app.
    @State private var leaveArmed = false
    @State private var leaveGeneration = 0
    @State private var avatar: UIImage?
    /// The session's profile as last read from it (every state change), for states that carry none.
    @State private var fallbackProfile: PlexActiveProfile?
    /// The session state the last read answered for; until it matches, a state without a usable profile
    /// shows nothing rather than the wrong Home.
    @State private var resolvedFor: PlexSessionState?

    init(core: CoreServices, onRunSetupAgain: @escaping () -> Void) {
        self.core = core
        _flow = State(initialValue: SetupRerunFlow(core: core, onRunSetupAgain: onRunSetupAgain))
    }

    private static var initialTab: MainTab { .home }

    private static func initialPaths() -> [MainTab: NavigationPath] {
        var home = NavigationPath()
        #if DEBUG
        // `-PerchDesignGallery`: the gallery on Home's stack from the first frame, so Back from it lands on Home.
        if ProcessInfo.processInfo.arguments.contains("-PerchDesignGallery") { home.append(ShellRoute.gallery) }
        #endif
        return [.home: home]
    }

    /// Ambient hero motion is off for UI tests (`-PerchUITests`, DEBUG only) so screens settle.
    private static var ambientMotion: Bool {
        #if DEBUG
        !ProcessInfo.processInfo.arguments.contains("-PerchUITests")
        #else
        true
        #endif
    }

    /// Ready carries the profile. Otherwise (connecting, server unreachable) the session's profile is the one it
    /// last committed: `plex.lastProfileID` is written before the profile and before any state that carries it
    /// (`PlexSession.activate` and `resume`). A remembered profile is used only when it is that one, so a switch
    /// from a parent to a kid that fails half way never shows the parent's rows, not even for a frame.
    private var activeProfile: PlexActiveProfile? {
        if case .ready(let profile, _) = core.plexSignIn.snapshot.state { return profile }
        let lastID = CoreServices.plexDefaults().string(forKey: PlexSession.DefaultsKey.lastProfileID)
        guard let lastID else { return nil }
        return [HomeStore.shared.current?.home.profile, fallbackProfile].compactMap { $0 }
            .first { $0.id.rawValue == lastID }
    }

    var body: some View {
        let entry = activeProfile.map { HomeStore.shared.entry(for: $0, core: core) }
        let name = entry?.home.profile.displayName ?? ""
        TabView(selection: $selection) {
            Tab(ShellStrings.home, systemImage: "house", value: MainTab.home) {
                stack(.home) { homeContent(entry) }
            }
            .accessibilityIdentifier("tab.home")
            Tab(ShellStrings.films, systemImage: "film", value: MainTab.films) {
                stack(.films) {
                    placeholder(PerchEmptyState(systemImage: "film", title: ShellStrings.filmsTitle, message: ShellStrings.filmsMessage), id: "films.empty")
                }
            }
            .accessibilityIdentifier("tab.films")
            Tab(ShellStrings.series, systemImage: "tv", value: MainTab.series) {
                stack(.series) {
                    placeholder(PerchEmptyState(systemImage: "tv", title: ShellStrings.seriesTitle, message: ShellStrings.seriesMessage), id: "series.empty")
                }
            }
            .accessibilityIdentifier("tab.series")
            Tab(ShellStrings.search, systemImage: "magnifyingglass", value: MainTab.search) {
                stack(.search) {
                    placeholder(PerchEmptyState(systemImage: "magnifyingglass", title: ShellStrings.searchTitle, message: ShellStrings.searchMessage), id: "search.empty")
                }
            }
            .accessibilityIdentifier("tab.search")
            Tab(ShellStrings.settings, systemImage: "gearshape", value: MainTab.settings) {
                stack(.settings) {
                    SettingsView(
                        name: name, avatar: avatar, isKid: entry?.home.isKid == true,
                        onSwitchProfile: { pickerShown = true },
                        onRunSetup: { Task { await flow.open(profile: entry?.home.profile) } },
                        onGallery: galleryAction)
                }
            }
            .accessibilityIdentifier("tab.settings")
        }
        .tabViewStyle(.sidebarAdaptable)
        .modifier(SidebarProfileHeader(name: name, avatar: avatar, onSelect: { pickerShown = true }))
        .background { BackPressMonitor(onDoubleBack: returnHome) }
        // Back that no screen takes (focus in the sidebar): the first press shows a hint and arms a short window;
        // a second press inside it reaches the system and leaves the app (Robin, 5 Nov 2026). At a tab's root the
        // system moves focus to the sidebar before this runs.
        .onExitCommand(perform: leaveAction)
        .overlay(alignment: .topTrailing) { LeaveHint(visible: leaveArmed) }
        .perchFullScreen(isPresented: $pickerShown) {
            ProfilePickerView(core: core, onBack: { pickerShown = false }, onDone: { pickerShown = false })
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("shell.picker")
        }
        .setupRerunFlow(flow, name: activeProfile?.displayName)
        .environment(\.perchStyle, entry?.home.isKid == true ? .kids : .standard)
        .environment(\.perchAmbientMotion, Self.ambientMotion)
        .task(id: core.plexSignIn.snapshot.state) {
            let state = core.plexSignIn.snapshot.state
            if case .ready(let profile, _) = state {
                fallbackProfile = profile
            } else {
                let profile = await core.plexSignIn.session.currentProfile()
                guard !Task.isCancelled else { return }  // a newer state's read owns the answer
                fallbackProfile = profile
            }
            resolvedFor = state
        }
        .task(id: entry?.home.profile.id) { await loadAvatar(entry?.home.profile) }
    }

    // MARK: Tabs

    /// A tab's own stack. The root sits in an overlay of a clear, greedy view so its size never feeds back into
    /// the stack's: Home's full-bleed scroll view (ignoring the 80 pt leading inset with no trailing one) inside a
    /// sidebar tab's NavigationStack otherwise grew 80 pt wider every layout pass, a blank screen at 100% CPU.
    private func stack<Content: View>(_ tab: MainTab, @ViewBuilder root: () -> Content) -> some View {
        NavigationStack(path: path(tab)) {
            Color.clear
                .overlay { root() }
                .navigationDestination(for: ShellRoute.self) { route in
                    PushedScreen(onBack: { pop(tab) }) { Self.destination(route) }
                }
        }
    }

    private func pop(_ tab: MainTab) {
        guard var path = paths[tab], !path.isEmpty else { return }
        path.removeLast()
        paths[tab] = path
    }

    private func path(_ tab: MainTab) -> Binding<NavigationPath> {
        Binding(get: { paths[tab] ?? NavigationPath() }, set: { paths[tab] = $0 })
    }

    @ViewBuilder
    private static func destination(_ route: ShellRoute) -> some View {
        #if DEBUG
        switch route {
        case .gallery: DesignGallery()
        }
        #else
        EmptyView()
        #endif
    }

    /// A tab with nothing in it yet. The whole page takes focus, without a focus effect: selecting the tab
    /// collapses the sidebar and moves focus into the content, and with nothing focusable there focus was lost
    /// (WP-13). Left or Back returns to the sidebar.
    private func placeholder(_ state: PerchEmptyState, id: String) -> some View {
        state
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .focusable()
            .focusEffectDisabled()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private func homeContent(_ entry: HomeStore.Entry?) -> some View {
        if let entry {
            HomeView(
                core: core, home: entry.home, model: entry.model,
                onSwitchProfile: { pickerShown = true }, rootRequest: homeRootRequest
            )
            .id(entry.home.profile.id)
        } else if resolvedFor != core.plexSignIn.snapshot.state {
            Color.clear
        } else {
            HomeView(
                core: core, home: nil, model: HomeStore.shared.noProfileModel(core: core),
                onSwitchProfile: { pickerShown = true }, rootRequest: homeRootRequest)
        }
    }

    private var galleryAction: (() -> Void)? {
        #if DEBUG
        { paths[.settings, default: NavigationPath()].append(ShellRoute.gallery) }
        #else
        nil
        #endif
    }

    // MARK: Back

    /// Double-tap Back (SPEC 3, DESIGN:20): Home's root, focus on its hero. The player owns its own Back.
    private func returnHome() {
        guard core.playback.activeSession == nil else { return }
        pickerShown = false
        if flow.isActive { flow.back() }
        paths[.home] = NavigationPath()
        selection = .home
        homeRootRequest += 1
    }

    static let leaveWindow: Duration = .seconds(2)

    /// Nil while armed, so the second press goes to the system.
    private var leaveAction: (() -> Void)? {
        leaveArmed ? nil : { armLeave() }
    }

    private func armLeave() {
        leaveArmed = true
        leaveGeneration += 1
        let generation = leaveGeneration
        Task {
            try? await Task.sleep(for: Self.leaveWindow)
            if generation == leaveGeneration { leaveArmed = false }
        }
    }

    // MARK: Avatar

    private func loadAvatar(_ profile: PlexActiveProfile?) async {
        guard let profile else { return }
        let users = await core.plexSignIn.session.cachedHomeUsers()
        guard let user = users.first(where: { $0.id == profile.id.rawValue }),
            let request = await core.artwork.avatarRequest(thumb: user.thumb)
        else { return }
        if let image = core.artwork.cachedImage(request) {
            avatar = image
        } else {
            avatar = await core.artwork.image(request)
        }
    }
}

/// The profile avatar at the top of the sidebar. The sidebar header API is tvOS 27; on tvOS 26 the picker is
/// reached from Settings only.
private struct SidebarProfileHeader: ViewModifier {
    let name: String
    let avatar: UIImage?
    let onSelect: () -> Void
    @Environment(\.perchStyle) private var style

    func body(content: Content) -> some View {
        if #available(tvOS 27.0, *) {
            content.tabViewSidebarHeader {
                SidebarProfileButton(name: name, nameIdentifier: "home.profileName", action: onSelect) {
                    ProfileAvatarImage(
                        name: name, size: SidebarProfileButton<EmptyView>.avatarSize(style),
                        image: avatar.map { Image(uiImage: $0).resizable() })
                }
                .accessibilityIdentifier("sidebar.profile")
            }
        } else {
            content
        }
    }
}

/// A screen pushed on a tab's stack. tvOS 27: after a push inside a sidebar tab nothing had focus (SwiftUI focus
/// requests and `resetFocus` did nothing), so Menu reached the system and left the app instead of popping (WP-13).
/// `FocusRescue` gives the screen its default focus once it is up, and the screen pops itself on Back.
private struct PushedScreen<Content: View>: View {
    let onBack: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .onExitCommand(perform: onBack)
            .background { FocusRescue() }
    }
}

/// When nothing has focus once a pushed screen is up (after the push transition), asks the focus system to update
/// to this view's host, the nearest ancestor that takes it; the focus engine then resolves the screen's default
/// focus.
private struct FocusRescue: UIViewRepresentable {
    func makeUIView(context: Context) -> RescueView { RescueView() }
    func updateUIView(_ view: RescueView, context: Context) {}

    final class RescueView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.rescue() }
        }

        private func rescue() {
            guard let window, let system = UIFocusSystem.focusSystem(for: window), system.focusedItem == nil else { return }
            var view: UIView? = superview
            while let current = view {
                system.requestFocusUpdate(to: current)
                system.updateFocusIfNeeded()
                if system.focusedItem != nil { return }
                view = current.superview
            }
        }
    }
}

/// "Press Back again to leave": a quiet glass card, top right, that fades in and out (a fade only, so Reduce Motion
/// needs nothing else). Never focusable.
private struct LeaveHint: View {
    let visible: Bool
    @Environment(\.perchStyle) private var style

    var body: some View {
        ZStack {
            if visible {
                Text(ShellStrings.backAgainToLeave)
                    .font(PerchFont.body(style))
                    .foregroundStyle(PerchColor.textPrimary)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                    .glassEffect(.regular, in: Capsule())
                    .accessibilityIdentifier("shell.leaveHint")
                    .transition(.opacity)
            }
        }
        .padding(.top, PerchSpacing.topMargin)
        .padding(.trailing, PerchSpacing.horizontalMargin)
        .allowsHitTesting(false)
        .focusable(false)
        .animation(.easeInOut(duration: 0.25), value: visible)
    }
}

/// Copy for the shell, in sentence case (GLOSSARY).
enum ShellStrings {
    static let home = "Home"
    static let films = "Films"
    static let series = "Series"
    static let search = "Search"
    static let settings = "Settings"
    static let filmsTitle = "Films will appear here"
    static let filmsMessage = "Every film in your library, in one place."
    static let seriesTitle = "Series will appear here"
    static let seriesMessage = "Every series, with its seasons and episodes in order."
    static let searchTitle = "Search will appear here"
    static let searchMessage = "Find films and series by title."
    static let backAgainToLeave = "Press Back again to leave"
}


