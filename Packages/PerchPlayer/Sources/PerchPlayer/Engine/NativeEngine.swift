import AVKit
import OSLog
import PerchCore
import UIKit
import UIKit.UIGestureRecognizerSubclass

public enum NativeEngineError: Error, Equatable, Sendable, CustomStringConvertible {
    case failed(String)

    public var description: String {
        switch self { case .failed(let text): text }
    }
}

/// The 1.x engine: Apple's `AVPlayerViewController` and `AVPlayer`, with AVKit's own chrome for Skip
/// (contextual actions) and up next (content proposals).
/// Generation counter drops stale async work after a reload or teardown, approach from Swiftfin (MPL-2.0).
@MainActor
public final class NativeEngine: NSObject, PlaybackEngine {
    public let name = "native"
    public let player = AVPlayer()
    public let playerViewController = AVPlayerViewController()
    public let events: AsyncStream<EngineEvent>

    /// Diagnostics for the debug harness: what AVKit is actually showing.
    public private(set) var isShowingSkip = false
    public private(set) var isShowingUpNext = false

    private let continuation: AsyncStream<EngineEvent>.Continuation
    private let displayMatcher = DisplayCriteriaMatcher()
    private var generation = 0
    private var isTornDown = false
    private var lastState: EngineEvent?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var itemTokens: [any NSObjectProtocol] = []
    private var readyContinuation: CheckedContinuation<Void, any Error>?

    private struct UpNextRequest {
        var proposal: UpNextProposal
        var mode: UpNextMode
        var onAccept: @MainActor (UpNextAcceptance) -> Void
        var onDismiss: @MainActor () -> Void
    }
    private var upNext: UpNextRequest?
    private weak var proposalController: UpNextProposalViewController?

    override public init() {
        let (stream, continuation) = AsyncStream.makeStream(of: EngineEvent.self, bufferingPolicy: .bufferingNewest(128))
        events = stream
        self.continuation = continuation
        super.init()
        playerViewController.player = player
        // We set the display criteria ourselves before the asset loads (DisplayCriteriaMatcher).
        playerViewController.appliesPreferredDisplayCriteriaAutomatically = false
        playerViewController.delegate = self
        playerViewController.view.addGestureRecognizer(
            InputObserver { [weak self] in self?.continuation.yield(.userInput) })
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.timeControlChanged() }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 2), queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isTornDown, self.player.currentItem != nil else { return }
                self.continuation.yield(.positionTick(self.positionMs))
            }
        }
    }

    isolated deinit {
        teardown()
    }

    public var viewController: UIViewController { playerViewController }

    public var positionMs: Int {
        let time = player.currentTime()
        guard time.isValid, time.isNumeric else { return 0 }
        return max(0, Int((time.seconds * 1000).rounded()))
    }

    // MARK: loading

    public func load(_ source: PlaybackSource, metadata: PlayerItemMetadata) async throws {
        guard !isTornDown else { throw CancellationError() }
        generation += 1
        let gen = generation
        cancelReady()
        clearItemObservers()
        hideChrome()
        player.pause()

        // Display mode first, so the switch happens while the asset loads.
        let matched = displayMatcher.apply(source.decision, window: playerViewController.view.window)
        if !matched, DisplayCriteriaMatcher.criteria(for: source.decision) == nil {
            // Frame rate unknown: let AVKit match from the asset itself.
            playerViewController.appliesPreferredDisplayCriteriaAutomatically = true
        } else {
            playerViewController.appliesPreferredDisplayCriteriaAutomatically = false
        }

        // The token travels only in these headers, on every request the asset makes (WP-07 spike).
        var options: [String: Any] = [:]
        if !source.headers.isEmpty { options["AVURLAssetHTTPHeaderFieldsKey"] = source.headers }
        let asset = AVURLAsset(url: source.url, options: options)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 20
        item.externalMetadata = Self.metadataItems(metadata)
        observe(item, generation: gen)
        player.replaceCurrentItem(with: item)
        lastState = nil

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            if item.status == .readyToPlay {
                continuation.resume()
            } else {
                readyContinuation = continuation
            }
        }
        guard gen == generation, !isTornDown else { throw CancellationError() }
        if source.startMs > 0 {
            await seek(toMs: source.startMs)
            guard gen == generation, !isTornDown else { throw CancellationError() }
        }
    }

    public func play() {
        guard !isTornDown else { return }
        player.play()
    }

    public func pause() {
        guard !isTornDown else { return }
        player.pause()
    }

    public func seek(toMs ms: Int) async {
        guard !isTornDown else { return }
        let target = CMTime(value: CMTimeValue(ms), timescale: 1000)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                continuation.resume()
            }
        }
    }

    private func observe(_ item: AVPlayerItem, generation gen: Int) {
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.itemStatusChanged(generation: gen) }
        }
        let center = NotificationCenter.default
        itemTokens.append(
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, gen == self.generation, !self.isTornDown else { return }
                    self.continuation.yield(.ended)
                }
            })
        itemTokens.append(
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) {
                [weak self] note in
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
                let text = Self.describe(error)
                MainActor.assumeIsolated {
                    guard let self, gen == self.generation, !self.isTornDown else { return }
                    self.continuation.yield(.failed(text))
                }
            })
    }

    private func itemStatusChanged(generation gen: Int) {
        guard gen == generation, !isTornDown, let item = player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            readyContinuation?.resume()
            readyContinuation = nil
        case .failed:
            let text = Self.describe(item.error as NSError?)
            if let readyContinuation {
                self.readyContinuation = nil
                readyContinuation.resume(throwing: NativeEngineError.failed(text))
            } else {
                continuation.yield(.failed(text))
            }
        default:
            break
        }
    }

    private func timeControlChanged() {
        guard !isTornDown, player.currentItem != nil else { return }
        let state: EngineEvent
        switch player.timeControlStatus {
        case .playing: state = .playing
        case .paused: state = .paused
        case .waitingToPlayAtSpecifiedRate: state = .buffering
        @unknown default: return
        }
        guard state != lastState else { return }
        lastState = state
        continuation.yield(state)
    }

    // MARK: chrome

    public func showSkip(_ offer: SkipOffer?, onSkip: @escaping @MainActor () -> Void) {
        guard !isTornDown, let offer else {
            playerViewController.contextualActions = []
            isShowingSkip = false
            return
        }
        let title = offer.kind == .intro ? "Skip Intro" : "Skip Credits"
        playerViewController.contextualActions = [
            UIAction(title: title, image: UIImage(systemName: "forward.end.fill")) { _ in onSkip() }
        ]
        isShowingSkip = true
    }

    public func showUpNext(
        _ proposal: UpNextProposal?, mode: UpNextMode,
        onAccept: @escaping @MainActor (UpNextAcceptance) -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        guard !isTornDown, let proposal, let item = player.currentItem else {
            withdrawUpNext()
            return
        }
        upNext = UpNextRequest(proposal: proposal, mode: mode, onAccept: onAccept, onDismiss: onDismiss)
        // AVKit presents a proposal when playback crosses its transition time; the session decides
        // when, so the transition is a moment from now.
        let transition = CMTimeAdd(player.currentTime(), CMTime(value: 1, timescale: 4))
        let content = AVContentProposal(
            contentTimeForTransition: transition, title: proposal.title,
            previewImage: proposal.previewImageData.flatMap(UIImage.init(data:)))
        item.nextContentProposal = content
    }

    private func withdrawUpNext() {
        upNext = nil
        player.currentItem?.nextContentProposal = nil
        proposalController?.withdraw()
    }

    private func hideChrome() {
        playerViewController.contextualActions = []
        isShowingSkip = false
        withdrawUpNext()
    }

    // MARK: teardown

    public func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        generation += 1
        cancelReady()
        hideChrome()
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        clearItemObservers()
        player.replaceCurrentItem(with: nil)
        displayMatcher.reset()
        continuation.finish()
    }

    private func cancelReady() {
        readyContinuation?.resume(throwing: CancellationError())
        readyContinuation = nil
    }

    private func clearItemObservers() {
        itemObservation?.invalidate()
        itemObservation = nil
        for token in itemTokens { NotificationCenter.default.removeObserver(token) }
        itemTokens = []
    }

    // MARK: helpers

    private static func metadataItems(_ metadata: PlayerItemMetadata) -> [AVMetadataItem] {
        func item(_ identifier: AVMetadataIdentifier, _ value: any NSCopying & NSObjectProtocol) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value
            item.extendedLanguageTag = "und"
            return item
        }
        var items = [item(.commonIdentifierTitle, metadata.title as NSString)]
        if let subtitle = metadata.subtitle { items.append(item(.iTunesMetadataTrackSubTitle, subtitle as NSString)) }
        if let summary = metadata.summary { items.append(item(.commonIdentifierDescription, summary as NSString)) }
        if let artwork = metadata.artworkData {
            let art = AVMutableMetadataItem()
            art.identifier = .commonIdentifierArtwork
            art.value = artwork as NSData
            art.dataType = kCMMetadataBaseDataType_JPEG as String
            art.extendedLanguageTag = "und"
            items.append(art)
        }
        return items
    }

    /// Domain, code and description only; the session strips anything URL-like before logging.
    nonisolated static func describe(_ error: NSError?) -> String {
        guard let error else { return "Unknown playback error" }
        var text = "\(error.domain) \(error.code): \(error.localizedDescription)"
        if let inner = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " (underlying \(inner.domain) \(inner.code))"
        }
        return text
    }
}

extension NativeEngine: @MainActor AVPlayerViewControllerDelegate {
    public func playerViewController(
        _ playerViewController: AVPlayerViewController, shouldPresent proposal: AVContentProposal
    ) -> Bool {
        guard let request = upNext else { return false }
        let controller = UpNextProposalViewController(proposal: request.proposal, mode: request.mode)
        controller.onVisibilityChange = { [weak self] visible in self?.isShowingUpNext = visible }
        playerViewController.contentProposalViewController = controller
        proposalController = controller
        Logger.player.notice("Up next presented")
        return true
    }

    public func playerViewController(
        _ playerViewController: AVPlayerViewController, didAccept proposal: AVContentProposal
    ) {
        guard let request = upNext else { return }
        upNext = nil
        request.onAccept(proposalController?.acceptance ?? .user)
    }

    public func playerViewController(
        _ playerViewController: AVPlayerViewController, didReject proposal: AVContentProposal
    ) {
        guard let request = upNext else { return }
        upNext = nil
        request.onDismiss()
    }
}

/// Sees every remote press and touch, then fails at once, so it never takes input from AVKit.
final class InputObserver: UIGestureRecognizer {
    private let onInput: @MainActor () -> Void

    init(onInput: @escaping @MainActor () -> Void) {
        self.onInput = onInput
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        onInput()
        state = .failed
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onInput()
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
