import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI
import UIKit

/// "Who's watching?" in the style of the Apple TV app (centred row of round avatars, DESIGN:43; structure
/// after Dusk's Home user picker). Switching goes through `ProfileSwitcher` only.
/// `onBack` is nil when there is nothing to go back to (no profile resumed): Back then stays here.
struct ProfilePickerView: View {
    let core: CoreServices
    var onBack: (() -> Void)?
    /// Called after a successful switch. The gate version needs nothing: the root re-routes by itself.
    var onDone: (() -> Void)?

    @State private var users: [PlexHomeUser] = []
    @State private var loaded = false
    @State private var offline = false
    @State private var avatars: [String: UIImage] = [:]
    @State private var backdrop: UIImage?
    @State private var currentID: String?
    @State private var lastSelectedID: String?

    @State private var pinTarget: PlexHomeUser?
    @State private var pinKind: SwitchRequirement = .targetPlexPIN
    @State private var pin = ""
    @State private var failures = 0
    @State private var isChecking = false
    @State private var errorMessage: String?
    @State private var isSwitching = false
    @State private var notice: String?

    private var session: PlexSession { core.plexSignIn.session }

    var body: some View {
        ZStack {
            if let target = pinTarget {
                pinScreen(target)
                    .transition(.opacity)
            } else {
                pickerScreen
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: PerchMotion.crossfadeDuration), value: pinTarget?.id)
        .onExitCommand { handleBack() }
        .task { await load() }
    }

    // MARK: Screens

    private var pickerScreen: some View {
        ZStack {
            SetupBackdrop(art: backdrop.map { AnyView(Image(uiImage: $0).resizable()) })
                .animation(.easeInOut(duration: PerchMotion.heroBackdropFade), value: backdrop != nil)
            VStack(spacing: 64) {
                Text("Who's watching?")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(PerchColor.textPrimary)
                    .perchStagedEntrance(stage: 0)
                    .accessibilityIdentifier("picker.title")
                if loaded && users.isEmpty {
                    emptyState
                } else {
                    ProfilePickerRow(
                        items: items, defaultFocusID: lastSelectedID ?? currentID ?? lastProfileID ?? users.first?.id,
                        onSelect: select
                    )
                    .id(users.map(\.id))  // a fresh focus scope when the list first arrives
                    .perchStagedEntrance(stage: 1)
                    .disabled(isSwitching)
                }
                noticeLine
                    .frame(height: 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if isSwitching { ProgressView().scaleEffect(1.6) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("picker.screen")
    }

    private func pinScreen(_ target: PlexHomeUser) -> some View {
        PINEntryScreen(
            name: target.displayName,
            image: avatars[target.id].map { Image(uiImage: $0).resizable() },
            prompt: pinKind == .adminPIN ? "Enter the Admin PIN" : "Enter \(target.displayName)'s PIN",
            pin: $pin, failures: failures, isChecking: isChecking, errorMessage: errorMessage,
            onComplete: { entered in Task { await attempt(target, pin: entered) } }
        )
        .onChange(of: pin) { _, value in if !value.isEmpty { errorMessage = nil } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("picker.pin")
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Text("No profiles to show yet")
                .font(PerchFont.body(.standard))
                .foregroundStyle(PerchColor.textSecondary)
            if offline {
                Text("Check that your Apple TV is online, then try again")
                    .font(PerchFont.metadata(.standard))
                    .foregroundStyle(PerchColor.textSecondary)
            }
            Button("Try again") { Task { await load() } }
                .buttonStyle(.perchSecondary)
                .accessibilityIdentifier("picker.retry")
        }
    }

    @ViewBuilder
    private var noticeLine: some View {
        if let notice {
            Text(notice)
                .font(PerchFont.body(.standard))
                .foregroundStyle(PerchColor.textBody)
                .transition(.opacity)
                .accessibilityIdentifier("picker.notice")
        } else if offline && !users.isEmpty {
            Text(ProfileSwitcher.cannotSwitch)
                .font(PerchFont.body(.standard))
                .foregroundStyle(PerchColor.textSecondary)
                .accessibilityIdentifier("picker.offline")
        }
    }

    // MARK: Data

    private var items: [ProfilePickerItem] {
        users.map { user in
            ProfilePickerItem(
                id: user.id, name: user.displayName,
                image: avatars[user.id].map { Image(uiImage: $0).resizable() },
                isLocked: user.protected, isCurrent: user.id == currentID)
        }
    }

    private var lastProfileID: String? {
        UserDefaults(suiteName: PerchConstants.appGroupID)?.string(forKey: PlexSession.DefaultsKey.lastProfileID)
    }

    private func load() async {
        currentID = await session.currentProfile()?.id.rawValue
        let cached = await session.cachedHomeUsers()
        if users.isEmpty, !cached.isEmpty {
            users = cached
            loaded = true
            await loadAvatars()
        }
        do {
            users = try await session.homeUsers()
            offline = false
        } catch {
            offline = true
            if users.isEmpty { users = cached }
        }
        loaded = true
        async let artwork: Void = loadBackdrop()
        await loadAvatars()
        await artwork
    }

    /// Cached bytes first so nothing pops in when offline, then a fresh fetch (C7).
    private func loadAvatars() async {
        let cache = ImageDiskCache.shared
        for user in users {
            let key = "avatar-\(user.id)"
            if avatars[user.id] == nil, let data = cache.data(for: key), let image = UIImage(data: data) {
                avatars[user.id] = image
            }
        }
        for user in users {
            guard let thumb = user.thumb, !thumb.isEmpty, let data = await fetchAvatar(thumb),
                let image = UIImage(data: data)
            else { continue }
            ImageDiskCache.shared.store(data, for: "avatar-\(user.id)")
            avatars[user.id] = image
        }
    }

    /// A server path goes through the session (token in a header); a plex.tv avatar address is fetched plainly.
    private func fetchAvatar(_ thumb: String) async -> Data? {
        if thumb.hasPrefix("/") { return try? await session.imageData(for: thumb) }
        guard let url = URL(string: thumb), url.scheme == "https" else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }

    private func loadBackdrop() async {
        let key = "picker-backdrop"
        if let data = ImageDiskCache.shared.data(for: key), let image = UIImage(data: data) {
            backdrop = image
        }
        guard let path = try? await session.libraryArt(limit: 6).randomElement(),
            let data = try? await session.imageData(for: path), let image = UIImage(data: data)
        else { return }
        ImageDiskCache.shared.store(data, for: key)
        backdrop = image
    }

    // MARK: Actions

    private func select(_ id: String) {
        guard let user = users.first(where: { $0.id == id }) else { return }
        lastSelectedID = id
        notice = nil
        if id == currentID {
            onBack?()
            return
        }
        if offline {
            notice = ProfileSwitcher.cannotSwitch
            return
        }
        Task {
            isSwitching = true
            let result = await core.profileSwitcher.switchTo(user, pin: nil)
            isSwitching = false
            handle(result, for: user, fromPINScreen: false)
        }
    }

    private func attempt(_ user: PlexHomeUser, pin entered: String) async {
        isChecking = true
        let result = await core.profileSwitcher.switchTo(user, pin: entered)
        isChecking = false
        handle(result, for: user, fromPINScreen: true)
    }

    private func handle(_ result: ProfileSwitcher.Result, for user: PlexHomeUser, fromPINScreen: Bool) {
        switch result {
        case .switched:
            pinTarget = nil
            pin = ""
            currentID = user.id
            onDone?()
        case .needsPIN(let kind):
            pinKind = kind
            pin = ""
            failures = 0
            errorMessage = nil
            pinTarget = user
        case .rejected(let message):
            pin = ""
            failures += 1
            errorMessage = message
        case .failed(let message):
            if fromPINScreen {
                pin = ""
                errorMessage = message
            } else {
                notice = message
            }
        }
    }

    private func handleBack() {
        if pinTarget != nil {
            guard !isChecking else { return }
            pinTarget = nil
            pin = ""
            errorMessage = nil
        } else {
            onBack?()
        }
    }
}
