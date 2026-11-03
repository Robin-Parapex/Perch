import Observation
import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI
import UIKit

/// One Home user as the profiles step shows it.
struct SetupProfileRow: Identifiable, Equatable {
    let id: PlexUserID
    let name: String
    let role: Role
    let ceiling: RatingCeiling
    let isOwner: Bool
}

/// State and actions of the first-run wizard. The step order and gates live in `SetupProgress`
/// (PerchCore); this class feeds it facts and does the I/O (Plex, Admin PIN, settings).
@Observable @MainActor
final class SetupFlowModel {
    /// Sub-screens of the Connect Plex step.
    enum ConnectStage: String { case choice, code, address, connected }

    /// What the full-screen PIN entry is for. Associated values are never logged or shown.
    enum PINMode {
        case usePlexPIN, enterPerchPIN, verifyPlexForPerch, newPIN, confirmPIN(first: String), reauthorise

        var key: String {
            switch self {
            case .usePlexPIN: "usePlexPIN"
            case .enterPerchPIN: "enterPerchPIN"
            case .verifyPlexForPerch: "verifyPlexForPerch"
            case .newPIN: "newPIN"
            case .confirmPIN: "confirmPIN"
            case .reauthorise: "reauthorise"
            }
        }

        var prompt: String {
            switch self {
            case .usePlexPIN: "Enter your Plex PIN"
            case .enterPerchPIN: "Enter the Admin PIN"
            case .verifyPlexForPerch: "Enter your Plex PIN first"
            case .newPIN: "Choose a 4-digit PIN"
            case .confirmPIN: "Enter it again to confirm"
            case .reauthorise: "Enter the Admin PIN to make this change"
            }
        }
    }

    private let core: CoreServices
    private let onFinish: () -> Void
    private let plex: PlexSignInModel

    // Flow
    private(set) var progress: SetupProgress
    private(set) var direction: StepDirection = .forward
    private(set) var connectStage: ConnectStage = .choice

    // Connect Plex
    private(set) var linkCode: String?
    private(set) var linkError: String?
    private(set) var linkAttempt = 0
    var address = ""
    var token = ""
    private(set) var addressError: String?
    private(set) var connecting = false
    private(set) var summary: String?

    // Choose server
    private(set) var servers: [PlexServer] = []
    var selectedServerID: String?
    private(set) var serverChosen = false
    private(set) var serverError: String?

    // Admin PIN
    private(set) var pinMode: PINMode?
    var pin = ""
    private(set) var pinFailures = 0
    private(set) var pinChecking = false
    private(set) var pinError: String?
    private(set) var adminMessage: String?
    private(set) var adminChecking = false
    /// The Plex owner, shown on the PIN screens. Nil name until the Home list has been read.
    private(set) var adminName = "Admin"
    private(set) var adminAvatar: UIImage?
    /// While in the future the PIN keypad is dimmed and a countdown shows.
    private(set) var pinLockedUntil: Date?

    // Profiles
    private(set) var profileRows: [SetupProfileRow] = []
    private(set) var profileMessage: String?
    @ObservationIgnored private var pendingEdit: (@Sendable (inout SettingsDocument) -> Void)?

    // Add later
    let addLater = AddLaterRegistry()

    // Backdrop
    private(set) var backdrop: UIImage?
    @ObservationIgnored private var backdropLoading = false

    /// `startAtConnect`: a re-run that begins at Connect Plex (setup is complete but the Plex sign-in is gone).
    init(core: CoreServices, isRerun: Bool, startAtConnect: Bool = false, onFinish: @escaping () -> Void) {
        self.core = core
        self.onFinish = onFinish
        plex = core.plexSignIn
        progress = SetupProgress(isRerun: isRerun, current: startAtConnect ? .connectPlex : .welcome)
        registerAddLaterEntries()
    }

    // MARK: Derived

    var stepNumber: Int { (progress.steps.firstIndex(of: progress.current) ?? 0) + 1 }
    var stepCount: Int { progress.steps.count }
    var isRerun: Bool { progress.isRerun }

    /// Identity of what is on screen, so a change of step or sub-screen plays the step transition.
    var screenID: String {
        if let pinMode { return "pin.\(pinMode.key)" }
        if progress.current == .connectPlex { return "connect.\(connectStage.rawValue)" }
        return "step.\(progress.current.rawValue)"
    }

    /// Back is left to the system only at Welcome on a first run (top level: it leaves the app).
    var interceptsBack: Bool {
        pinMode != nil || progress.current != .welcome || isRerun
    }

    var showsBackdrop: Bool {
        progress.current > .connectPlex || (progress.current == .connectPlex && connectStage == .connected)
    }

    var backdropView: (any View)? {
        guard showsBackdrop, let backdrop else { return nil }
        return SetupBackdropArt(image: backdrop)
    }

    var isSignedIn: Bool { plex.isReady }

    // MARK: Navigation

    /// Sets the direction first and lets one frame render, so the outgoing step leaves the right way.
    private func go(_ next: StepDirection, _ change: @escaping @MainActor () -> Void) async {
        direction = next
        try? await Task.sleep(for: .milliseconds(16))
        withAnimation(PerchMotion.spring) { change() }
    }

    func advance() async {
        guard progress.canAdvance(from: progress.current) else { return }
        await go(.forward) { self.progress.advance() }
        await entered()
    }

    func skip() async {
        guard progress.canSkip(progress.current) else { return }
        await go(.forward) { self.progress.skip() }
        await entered()
    }

    func back() async {
        if pinMode != nil {
            cancelPIN()
            return
        }
        if progress.current == .connectPlex, connectStage == .code || connectStage == .address {
            await go(.backward) { self.connectStage = .choice }
            return
        }
        if progress.current == .welcome {
            if progress.backAtStart == .returnHome { onFinish() }
            return
        }
        await go(.backward) { self.progress.goBack() }
        await entered()
    }

    /// Work a step needs when it comes on screen.
    private func entered() async {
        switch progress.current {
        case .connectPlex:
            connectStage = await sessionReady() ? .connected : .choice
            if connectStage == .connected { await loadSummary() }
        case .adminPIN:
            await refreshAdminSource()
        case .profiles:
            await loadProfiles()
        default:
            break
        }
        await loadBackdropIfNeeded()
    }

    func finish() {
        SetupCompletion(store: core.keyValues).setComplete(true)
        onFinish()
    }

    // MARK: Connect Plex

    func showCode() async {
        linkCode = nil
        linkError = nil
        await go(.forward) { self.connectStage = .code }
    }

    func showAddress() async {
        addressError = nil
        await go(.forward) { self.connectStage = .address }
    }

    func newCode() { linkAttempt += 1 }

    /// Shows the plex.tv/link code, renews it by itself and signs in once the phone has linked
    /// (approach after Dusk SignInView, MIT).
    func runLink() async {
        linkError = nil
        let flow = PlexLinkFlow(transport: plex.transport, endpoints: plex.endpoints)
        for await state in flow.start() {
            switch state {
            case .code(let value, _):
                linkCode = value
            case .failed(let error):
                linkError = PlexSignInModel.message(for: error)
                return
            case .linked(let accountToken):
                // Unstructured: the code screen goes away once connected, which cancels its own task.
                Task { await self.signIn(accountToken: accountToken) }
                return
            }
        }
    }

    private func signIn(accountToken: String) async {
        do {
            let found = try await plex.session.signIn(accountToken: accountToken)
            servers = found
            progress.serverCount = found.count
            if found.isEmpty {
                linkError = "No Plex server found on this account"
            } else if found.count > 1 {
                serverChosen = false
                serverError = nil
                selectedServerID = found.first?.machineID
                await advance()
            } else {
                await showConnected()
            }
        } catch {
            linkError = PlexSignInModel.message(for: error)
        }
    }

    func connectManually() async {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !token.isEmpty else {
            addressError = "Enter the address and the token"
            return
        }
        connecting = true
        addressError = nil
        defer { connecting = false }
        do {
            try await plex.session.signInManually(address: trimmed, token: token)
            token = ""
            servers = []
            progress.serverCount = 1
            await showConnected()
        } catch {
            addressError = PlexSignInModel.message(for: error)
        }
    }

    private func showConnected() async {
        await go(.forward) { self.connectStage = .connected }
        await loadSummary()
        await refreshAdminSource()
        await loadBackdropIfNeeded()
    }

    /// "Connected to <server>, <n> libraries" (SPEC 1a).
    func loadSummary() async {
        guard case .ready(_, let server) = await plex.session.snapshot().state else {
            summary = nil
            return
        }
        guard let library = try? await plex.session.librarySummary() else {
            summary = "Connected to \(server.name)"
            return
        }
        let count = library.sectionCount
        summary = "Connected to \(server.name), \(count) \(count == 1 ? "library" : "libraries")"
    }

    // MARK: Choose server

    func chooseSelectedServer() async {
        guard let server = servers.first(where: { $0.machineID == selectedServerID }) else { return }
        serverError = nil
        do {
            try await plex.session.choose(server: server)
            withAnimation(PerchMotion.spring) { serverChosen = true }
            await loadSummary()
            await refreshAdminSource()
            await loadBackdropIfNeeded()
        } catch {
            serverError = PlexSignInModel.message(for: error)
        }
    }

    // MARK: Admin PIN

    var adminSource: AdminPINSource { progress.adminPINSource }

    func refreshAdminSource() async {
        adminChecking = true
        defer { adminChecking = false }
        var source = await core.adminPIN.source
        if source == .unavailable, await sessionReady() {
            // plex.tv may not have told us about the owner's PIN yet: ask once.
            _ = try? await plex.session.homeUsers()
            source = await core.adminPIN.source
        }
        progress.adminPINSource = source
        await loadOwner()
        let lockout = await core.adminPIN.lockoutState()
        if lockout.isLocked(at: Date()), let until = lockout.lockedUntil {
            adminMessage = lockedMessage(until)
        } else if adminMessage?.hasPrefix("Too many") == true {
            adminMessage = nil
        }
    }

    /// The owner's name and picture for the Admin PIN screens (cached bytes first, then a fresh fetch).
    private func loadOwner() async {
        var users = await plex.session.cachedHomeUsers()
        if !users.contains(where: { $0.admin }), await sessionReady() {
            users = (try? await plex.session.homeUsers()) ?? users
        }
        guard let owner = users.first(where: { $0.admin }) else { return }
        adminName = owner.displayName
        let cache = ImageDiskCache.shared
        let key = "avatar-\(owner.id)"
        if adminAvatar == nil, let data = cache.data(for: key), let image = UIImage(data: data) { adminAvatar = image }
        guard let thumb = owner.thumb, !thumb.isEmpty else { return }
        var data: Data?
        if thumb.hasPrefix("/") {
            data = try? await plex.session.imageData(for: thumb)
        } else if let url = URL(string: thumb), url.scheme == "https" {
            data = try? await URLSession.shared.data(from: url).0
        }
        if let data, let image = UIImage(data: data) {
            cache.store(data, for: key)
            adminAvatar = image
        }
    }

    private func lockedMessage(_ until: Date) -> String {
        "Too many tries. Try again in \(PlexSignInModel.duration(until))"
    }

    func retryAdminCheck() async {
        adminMessage = nil
        await refreshAdminSource()
    }

    func startPIN(_ mode: PINMode) async {
        pin = ""
        pinError = nil
        pinFailures = 0
        let lockout = await core.adminPIN.lockoutState()
        pinLockedUntil = lockout.isLocked(at: Date()) ? lockout.lockedUntil : nil
        await go(.forward) { self.pinMode = mode }
    }

    private func cancelPIN() {
        direction = .backward
        pendingEdit = nil
        pin = ""
        pinLockedUntil = nil
        withAnimation(PerchMotion.spring) { pinMode = nil }
    }


    func submitPIN(_ entered: String) async {
        guard let mode = pinMode, !pinChecking else { return }
        switch mode {
        case .usePlexPIN, .enterPerchPIN, .verifyPlexForPerch, .reauthorise:
            await verify(entered, mode: mode)
        case .newPIN:
            pin = ""
            pinError = nil
            await go(.forward) { self.pinMode = .confirmPIN(first: entered) }
        case .confirmPIN(let first):
            guard entered == first else {
                pin = ""
                pinFailures += 1
                // The message is set in the same change as the screen, so the new screen never shows without it.
                await go(.backward) {
                    self.pinMode = .newPIN
                    self.pinError = "Those PINs don't match"
                }
                return
            }
            await savePerchPIN(entered)
        }
    }

    private func verify(_ entered: String, mode: PINMode) async {
        pinChecking = true
        pinError = nil
        let result = await core.adminPIN.verify(entered)
        pinChecking = false
        pin = ""
        switch result {
        case .accepted:
            await accepted(mode)
        case .rejected:
            pinFailures += 1
            pinError = "That PIN isn't right"
        case .lockedOut(let until):
            adminMessage = lockedMessage(until)
            pendingEdit = nil
            direction = .backward
            withAnimation(PerchMotion.spring) { pinMode = nil }
            if mode.isReauthorise { profileMessage = lockedMessage(until) }
        case .setupRequired:
            direction = .backward
            withAnimation(PerchMotion.spring) { pinMode = nil }
            await refreshAdminSource()
        case .plexUnreachable:
            pinError = "Can't reach Plex right now"
        case .unavailable:
            pinError = "Something went wrong. Try again"
        }
    }

    private func accepted(_ mode: PINMode) async {
        switch mode {
        case .usePlexPIN, .enterPerchPIN:
            progress.markAdminPINVerified()
            await finishPIN()
            await advance()
        case .verifyPlexForPerch:
            pinFailures = 0
            await go(.forward) { self.pinMode = .newPIN }
        case .reauthorise:
            await finishPIN()
            if let edit = pendingEdit {
                pendingEdit = nil
                await authorisedEdit(edit)
            }
        case .newPIN, .confirmPIN:
            break
        }
    }

    private func finishPIN() async {
        direction = .forward
        withAnimation(PerchMotion.spring) { pinMode = nil }
        try? await Task.sleep(for: .milliseconds(16))
    }

    private func savePerchPIN(_ newPIN: String) async {
        pinChecking = true
        defer { pinChecking = false }
        do {
            try await core.adminPIN.setPerchPIN(newPIN)
        } catch {
            pin = ""
            pinError = "Couldn't save that PIN. Try again"
            await go(.backward) { self.pinMode = .newPIN }
            return
        }
        // Setting the PIN is not the same as proving it: check it once, as every route does.
        if case .accepted = await core.adminPIN.verify(newPIN) {
            progress.adminPINSource = await core.adminPIN.source
            progress.markAdminPINVerified()
            pin = ""
            await finishPIN()
            await advance()
        } else {
            pin = ""
            pinError = "Couldn't save that PIN. Try again"
            await go(.backward) { self.pinMode = .newPIN }
        }
    }

    // MARK: Profiles and roles

    func loadProfiles() async {
        await loadOwner()
        let cached = await plex.session.cachedHomeUsers()
        let users = (try? await plex.session.homeUsers()) ?? cached
        let document = await core.settings.document
        profileRows = users.map { user in
            let id = PlexUserID(user.id)
            let stored = document.profiles[id]
            return SetupProfileRow(
                id: id, name: user.displayName,
                role: stored?.role ?? (user.admin ? .parent : .kid),
                ceiling: stored?.ceiling ?? RatingCeiling(plex: user.restriction),
                isOwner: user.admin)
        }
    }

    /// Parent, Teen, Kid, round again. The owner stays a parent so the house always has one.
    func cycleRole(_ row: SetupProfileRow) async {
        guard !row.isOwner else { return }
        let next: Role =
            switch row.role {
            case .parent: .teen
            case .teen: .kid
            default: .parent
            }
        let id = row.id
        await authorisedEdit { document in
            document.profiles[id]?.role = next
            document.profiles[id]?.pinRequiredToExit = next == .kid
        }
    }

    /// One step down the rating scale; from U back to what Plex allows. Never raises it.
    func lowerLimit(_ row: SetupProfileRow) async {
        let lower = RatingCeiling(rawValue: row.ceiling.rawValue - 1)
        let id = row.id
        await authorisedEdit { document in
            document.profiles[id]?.setCeilingOverride(lower)
        }
    }

    /// Profile edits go through the Authoriser: parent role and a fresh Admin PIN (PERMISSIONS.md).
    private func authorisedEdit(_ edit: @escaping @Sendable (inout SettingsDocument) -> Void) async {
        profileMessage = nil
        let document = await core.settings.document
        let context = PermissionContext(role: .parent, plexUserID: document.household.ownerPlexUserID)
        let decision = await core.authoriser.authorise(.editSetup, context: context, entity: "profiles")
        switch decision {
        case .allowed, .limited, .queued:
            do {
                try await core.settings.update(edit)
                await loadProfiles()
            } catch {
                profileMessage = "Couldn't save that change. Try again"
            }
        case .needsPIN, .needsFreshPIN:
            pendingEdit = edit
            await startPIN(.reauthorise)
        case .denied:
            profileMessage = "Only a parent can change profiles"
        }
    }

    // MARK: Add later

    /// Entries the later work packages replace with real steps (module-registered, plan C10).
    private func registerAddLaterEntries() {
        let entries: [(String, String, Int)] = [
            ("seerr", "Requests (Seerr)", 10),
            ("library-refresh", "Library refresh", 20),
            ("trakt", "Trakt", 30),
            ("homeassistant", "Home Assistant", 40),
            ("tautulli", "Tautulli", 50),
            ("ai", "AI suggestions", 60),
        ]
        for (id, title, order) in entries {
            addLater.register(AddLaterEntry(moduleID: ModuleID(id), title: title, order: order))
        }
    }

    // MARK: Backdrop

    private func sessionReady() async -> Bool {
        if case .ready = await plex.session.snapshot().state { true } else { false }
    }

    /// One piece of library art, fetched with the token in a header (never in a URL), shown blurred behind the steps.
    func loadBackdropIfNeeded() async {
        guard showsBackdrop, backdrop == nil, !backdropLoading else { return }
        guard await sessionReady() else { return }
        backdropLoading = true
        defer { backdropLoading = false }
        guard let path = try? await plex.session.libraryArt(limit: 6).first,
            let data = try? await plex.session.imageData(for: path),
            let image = UIImage(data: data)
        else { return }
        backdrop = image
    }
}

extension SetupFlowModel.PINMode {
    var isReauthorise: Bool {
        if case .reauthorise = self { true } else { false }
    }
}

/// The backdrop picture: fades in when first shown, so it never pops.
struct SetupBackdropArt: View {
    let image: UIImage
    @State private var shown = false

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.easeInOut(duration: PerchMotion.heroBackdropFade)) { shown = true } }
    }
}
