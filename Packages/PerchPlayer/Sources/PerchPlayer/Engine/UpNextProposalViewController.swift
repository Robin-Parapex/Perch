import AVKit
import UIKit

/// AVKit's content proposal screen for the next item: the video shrinks to the top right, the next
/// title, preview and buttons fill the rest. `.timed` shows "Next episode in N" and accepts at 0;
/// `.manual` shows Play and Back. Back (button or Menu) rejects. Pattern from Swiftfin (MPL-2.0).
@MainActor
final class UpNextProposalViewController: AVContentProposalViewController {
    let proposal: UpNextProposal
    let mode: UpNextMode
    /// How it was accepted; read by the engine in `didAccept`.
    private(set) var acceptance: UpNextAcceptance = .user
    var onVisibilityChange: ((Bool) -> Void)?

    private let playButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let countdownLabel = UILabel()
    private var countdownTask: Task<Void, Never>?
    private var finished = false

    init(proposal: UpNextProposal, mode: UpNextMode) {
        self.proposal = proposal
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// 640 x 360 at the top right, 60 pt in from the edges.
    override var preferredPlayerViewFrame: CGRect {
        let bounds = view.window?.bounds ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        return CGRect(x: bounds.width - 60 - 640, y: 60, width: 640, height: 360)
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] { [playButton] }

    override func viewDidLoad() {
        super.viewDidLoad()
        let caption = UILabel()
        caption.text = "Up Next"
        caption.font = .preferredFont(forTextStyle: .headline)
        caption.textColor = .secondaryLabel

        let image = UIImageView(image: proposal.previewImageData.flatMap(UIImage.init(data:)))
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.layer.cornerRadius = 12
        image.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        image.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 560),
            image.heightAnchor.constraint(equalToConstant: 315),
        ])

        let title = UILabel()
        title.text = proposal.title
        title.font = .preferredFont(forTextStyle: .title2)
        title.numberOfLines = 2

        let subtitle = UILabel()
        subtitle.text = proposal.subtitle
        subtitle.font = .preferredFont(forTextStyle: .body)
        subtitle.textColor = .secondaryLabel
        subtitle.isHidden = proposal.subtitle == nil

        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 29, weight: .medium)
        countdownLabel.accessibilityIdentifier = "upnext.countdown"

        playButton.setTitle("Play", for: .normal)
        playButton.accessibilityIdentifier = "upnext.play"
        playButton.addAction(UIAction { [weak self] _ in self?.finish(.accept, acceptance: .user) }, for: .primaryActionTriggered)
        backButton.setTitle("Back", for: .normal)
        backButton.accessibilityIdentifier = "upnext.back"
        backButton.addAction(UIAction { [weak self] _ in self?.finish(.reject, acceptance: .user) }, for: .primaryActionTriggered)

        let buttons = UIStackView(arrangedSubviews: [playButton, backButton])
        buttons.spacing = 40
        switch mode {
        case .timed(let seconds):
            countdownLabel.text = Self.countdownText(seconds)
            backButton.isHidden = true
        case .manual:
            countdownLabel.isHidden = true
        }

        let stack = UIStackView(arrangedSubviews: [caption, image, title, subtitle, countdownLabel, buttons])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.setCustomSpacing(32, after: countdownLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 60),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -(640 + 60 + 60)),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onVisibilityChange?(true)
        guard case .timed(let seconds) = mode, countdownTask == nil else { return }
        countdownTask = Task { @MainActor [weak self] in
            var remaining = seconds
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, !self.finished else { return }
                remaining -= 1
                self.countdownLabel.text = Self.countdownText(remaining)
            }
            self?.finish(.accept, acceptance: .countdown)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        countdownTask?.cancel()
        onVisibilityChange?(false)
    }

    // Menu rejects the proposal; swallow both phases so nothing else acts on it.
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

    private static func countdownText(_ seconds: Int) -> String { "Next episode in \(seconds)" }
}
