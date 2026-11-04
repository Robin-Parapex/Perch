import AVKit
import Observation
import SwiftUI
import UIKit

// MARK: player chrome style (shared with the app's player overlays)

/// Measurements of AVKit's own tvOS 26 chrome (3840 px captures, v2-after-continue): title and transport
/// start 80 pt from the screen edge, the title is ~57 pt bold with its baseline ~855 pt down, the line above
/// it ~24 pt, the Info pill 61 pt tall with ~30 pt side padding and a ~29 pt medium label. The app's player
/// overlays and the up-next card use these so they sit on the same lines as Apple's player.
public enum PlayerChrome {
    /// Counted from the screen edge (a window's safe area would add a second 80 pt).
    public static let leadingInset: CGFloat = 80
    /// Top of the title's line box; puts the title baseline on AVKit's (~855 pt on a 1080 pt screen).
    public static let titleTop: CGFloat = 801
    public static let titleFont = Font.system(size: 57, weight: .bold)
    public static let secondaryFont = Font.system(size: 24, weight: .medium)
    public static let secondaryColor = Color.white.opacity(0.9)
    public static let buttonFont = Font.system(size: 29, weight: .medium)
    public static let pillHeight: CGFloat = 61
    public static let pillPadding: CGFloat = 30
    public static let pillGap: CGFloat = 24
    /// Space from the title's line box to the row of pills.
    public static let buttonsGap: CGFloat = 40
    public static let fadeIn: Double = 0.4
}

/// The pill inside the player, matching AVKit's Info pill: glass with a darker fill and a hairline so it
/// reads over bright footage; white with dark text when focused. `progress` (1 down to 0) draws a draining
/// fill, for a countdown.
public struct PlayerPillButtonStyle: ButtonStyle {
    let progress: Double?

    public init(progress: Double? = nil) { self.progress = progress }

    public func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, progress: progress)
    }

    private struct Pill: View {
        let configuration: Configuration
        let progress: Double?
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(PlayerChrome.buttonFont)
                .lineLimit(1)
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .padding(.horizontal, PlayerChrome.pillPadding)
                .frame(height: PlayerChrome.pillHeight)
                .background { background }
                .scaleEffect(isFocused && !reduceMotion ? 1.06 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.3 : 0), radius: 14, y: 6)
                .animation(.easeOut(duration: 0.2), value: isFocused)
        }

        @ViewBuilder private var background: some View {
            if isFocused {
                Capsule().fill(Color.white.opacity(progress == nil ? 1 : 0.62))
                    .overlay(alignment: .leading) { fill(Color.white) }
            } else {
                Capsule().fill(Color.black.opacity(0.28))
                    .glassEffect(.regular, in: Capsule())
                    .overlay(alignment: .leading) { fill(Color.white.opacity(0.22)) }
                    .overlay { Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5) }
            }
        }

        @ViewBuilder private func fill(_ color: Color) -> some View {
            if let progress {
                GeometryReader { proxy in
                    Rectangle().fill(color).frame(width: proxy.size.width * max(0, min(1, progress)))
                }
                .clipShape(Capsule())
            }
        }
    }
}

/// The soft bottom gradient the player chrome sits on.
public struct PlayerChromeGradient: View {
    public init() {}
    public var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0), .init(color: .black.opacity(0.5), location: 0.45),
                .init(color: .black.opacity(0.82), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 620)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The bottom-left block, anchored on the title so its baseline matches AVKit's whatever sits above it:
/// `above` (context, e.g. "Next: …") is stacked upwards from the title, `below` (explanation, buttons)
/// downwards.
public struct PlayerTitleBlock<Above: View, Below: View>: View {
    let title: String
    let titleID: String
    let above: Above
    let below: Below

    public init(
        title: String, titleID: String, @ViewBuilder above: () -> Above, @ViewBuilder below: () -> Below
    ) {
        self.title = title
        self.titleID = titleID
        self.above = above()
        self.below = below()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(PlayerChrome.titleFont)
                .foregroundStyle(.white)
                .lineLimit(1)
                .accessibilityIdentifier(titleID)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) { above }
                        .fixedSize()
                        .alignmentGuide(.top) { $0[.bottom] + 10 }
                }
            below
        }
        .padding(.leading, PlayerChrome.leadingInset)
        .padding(.top, PlayerChrome.titleTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: up-next card

/// AVKit's content proposal screen for the next item: the video shrinks to the top right, our card (SwiftUI,
/// the player chrome style) fills the rest. `.timed` drains Play Now and accepts at 0; `.manual` waits.
/// Watch Credits and Menu reject. Pattern from Swiftfin (MPL-2.0).
@MainActor
final class UpNextProposalViewController: AVContentProposalViewController {
    let proposal: UpNextProposal
    let mode: UpNextMode
    /// How it was accepted; read by the engine in `didAccept`.
    private(set) var acceptance: UpNextAcceptance = .user
    var onVisibilityChange: ((Bool) -> Void)?

    private let model: UpNextCardModel
    /// Built in init: AVKit asks for `preferredFocusEnvironments` before the view loads, and an empty answer
    /// then leaves focus behind in the player (nothing on the card focused, Menu never reaching us).
    private var host: UIHostingController<UpNextCard>!
    private var countdownTask: Task<Void, Never>?
    private var finished = false

    init(proposal: UpNextProposal, mode: UpNextMode) {
        self.proposal = proposal
        self.mode = mode
        if case .timed(let seconds) = mode {
            model = UpNextCardModel(total: seconds)
        } else {
            model = UpNextCardModel(total: nil)
        }
        super.init(nibName: nil, bundle: nil)
        let card = UpNextCard(
            proposal: proposal, model: model,
            onPlay: { [weak self] in self?.finish(.accept, acceptance: .user) },
            onCredits: { [weak self] in self?.finish(.reject, acceptance: .user) })
        host = UIHostingController(rootView: card)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// 640 x 360 at the top right, 60 pt in from the edges.
    override var preferredPlayerViewFrame: CGRect {
        let bounds = view.window?.bounds ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        return CGRect(x: bounds.width - 60 - 640, y: 60, width: 640, height: 360)
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] { [host] }

    override func viewDidLoad() {
        super.viewDidLoad()
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onVisibilityChange?(true)
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        guard case .timed(let seconds) = mode, countdownTask == nil else { return }
        model.startDraining()
        countdownTask = Task { @MainActor [weak self] in
            var remaining = seconds
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, !self.finished else { return }
                remaining -= 1
                self.model.remaining = remaining
            }
            self?.finish(.accept, acceptance: .countdown)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        countdownTask?.cancel()
        onVisibilityChange?(false)
    }

    // Menu rejects the proposal (the same as Watch Credits); swallow both phases so nothing else acts on it.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .menu }) { return }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .menu }) {
            finish(.reject, acceptance: .user)
            return
        }
        super.pressesEnded(presses, with: event)
    }

    private func finish(_ action: AVContentProposalAction, acceptance: UpNextAcceptance) {
        guard !finished else { return }
        finished = true
        countdownTask?.cancel()
        self.acceptance = acceptance
        dismissContentProposal(for: action, animated: true, completion: nil)
    }

    /// Hide without a decision (the session withdrew the proposal).
    func withdraw() {
        guard !finished else { return }
        finished = true
        countdownTask?.cancel()
        dismissContentProposal(for: .reject, animated: true, completion: nil)
    }
}

/// The countdown state the card shows. `progress(at:)` drains from 1 to 0 over the countdown, read every
/// frame by a TimelineView (an implicit animation of the model value did not run in the proposal's host).
@MainActor @Observable
final class UpNextCardModel {
    let total: Int?
    var remaining: Int
    private(set) var startedAt: Date?

    init(total: Int?) {
        self.total = total
        remaining = total ?? 0
    }

    func startDraining() { startedAt = .now }

    func progress(at date: Date) -> Double {
        guard let total, total > 0, let startedAt else { return 1 }
        return max(0, 1 - date.timeIntervalSince(startedAt) / Double(total))
    }
}

/// The up-next card: the preview, softened, behind a bottom gradient; bottom left "Up Next", the series
/// line, the episode in bold, "Next episode in N" when timed, then Play Now (focused) and Watch Credits.
struct UpNextCard: View {
    let proposal: UpNextProposal
    let model: UpNextCardModel
    let onPlay: () -> Void
    let onCredits: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var playFocused: Bool
    @State private var shown = false

    /// Episodes: the series is the title and "S1, E6 · Name" the subtitle; films have the title only.
    private var seriesLine: String? { proposal.subtitle == nil ? nil : proposal.title }
    private var boldLine: String { proposal.subtitle ?? proposal.title }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            PlayerChromeGradient()
            PlayerTitleBlock(title: boldLine, titleID: "upnext.title") {
                Text("Up Next")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(PlayerChrome.secondaryColor)
                    .textCase(.uppercase)
                    .kerning(1.2)
                if let seriesLine {
                    Text(seriesLine)
                        .font(PlayerChrome.secondaryFont)
                        .foregroundStyle(PlayerChrome.secondaryColor)
                }
            } below: {
                if model.total != nil {
                    Text("Next episode in \(model.remaining)")
                        .font(PlayerChrome.secondaryFont)
                        .monospacedDigit()
                        .foregroundStyle(PlayerChrome.secondaryColor)
                        .padding(.top, 6)
                        .accessibilityIdentifier("upnext.countdown")
                }
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: model.total == nil)) { context in
                    HStack(spacing: PlayerChrome.pillGap) {
                        Button("Play Now", action: onPlay)
                            .buttonStyle(
                                PlayerPillButtonStyle(progress: model.total == nil ? nil : model.progress(at: context.date)))
                            .focused($playFocused)
                            .accessibilityIdentifier("upnext.play")
                        Button("Watch Credits", action: onCredits)
                            .buttonStyle(PlayerPillButtonStyle())
                            .accessibilityIdentifier("upnext.back")
                    }
                }
                .padding(.top, PlayerChrome.buttonsGap - (model.total == nil ? 0 : 10))
            }
        }
        .opacity(shown ? 1 : 0)
        .ignoresSafeArea()
        .defaultFocus($playFocused, true)
        // Menu is Watch Credits (the controller's own Menu handling covers focus outside SwiftUI).
        .onExitCommand(perform: onCredits)
        .onAppear {
            playFocused = true
            withAnimation(.easeOut(duration: reduceMotion ? 0.25 : PlayerChrome.fadeIn)) { shown = true }
        }
    }

    /// The preview, large, blurred and dimmed, so the card carries the next episode's colours; nothing
    /// without one. Never over the shrunk video (cut out at the player frame).
    @ViewBuilder private var background: some View {
        if let data = proposal.previewImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: 50)
                .opacity(0.45)
                .clipped()
                .mask { VideoCutout().fill(style: FillStyle(eoFill: true)) }
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

/// The whole screen minus the shrunk video's frame (640 x 360, 60 pt from the top right).
private struct VideoCutout: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(
            in: CGRect(x: rect.maxX - 60 - 640, y: 60, width: 640, height: 360), cornerSize: CGSize(width: 12, height: 12))
        return path
    }
}
