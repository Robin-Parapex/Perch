import Foundation
import Nuke
import OSLog
import PerchCore

/// Warms the caches ahead of focus (WP-08): the next row's cards, and the focused item's backdrop, logo and
/// blurred stand-in. At most two loads at a time at low priority, so what is on screen always wins.
/// Logs counts only, never addresses.
@MainActor
final class ArtworkPrefetcher {
    private let service: ArtworkService
    private let prefetcher: ImagePrefetcher
    private var focusRequests: [ImageRequest] = []
    private var focusedID: String?
    private var lastRowSignature: String?

    init(service: ArtworkService) {
        self.service = service
        prefetcher = ImagePrefetcher(pipeline: service.pipeline, destination: .memoryCache, maxConcurrentRequestCount: 2)
    }

    /// The cards of a row about to come into view, with their stand-ins.
    func prefetch(row: [MediaSummary], size: ArtworkSize) {
        let paths = row.compactMap { $0.artworkPath(for: size) }
        let signature = "\(size.rawValue)|" + paths.joined(separator: ",")
        guard !paths.isEmpty, signature != lastRowSignature else { return }
        lastRowSignature = signature
        let requests = paths.flatMap { path in
            [size, .placeholder].compactMap { service.request(path: path, size: $0, priority: .low) }
        }
        start(requests, label: "row \(size.rawValue)")
    }

    /// The focused item's backdrop, logo and the backdrop's stand-in; the previous focus's loads are cancelled.
    func focus(item: MediaSummary?) {
        guard item?.id != focusedID else { return }
        focusedID = item?.id
        if !focusRequests.isEmpty { prefetcher.stopPrefetching(with: focusRequests) }
        focusRequests = []
        guard let item else { return }
        let backdrop = item.artworkPath(for: .backdrop)
        let requests = [
            service.request(path: backdrop, size: .placeholder, priority: .low),
            service.request(path: backdrop, size: .backdrop, priority: .low),
            service.request(path: item.artworkPath(for: .logo), size: .logo, priority: .low),
        ].compactMap { $0 }
        focusRequests = requests
        start(requests, label: "focus")
    }

    func cancelAll() {
        prefetcher.stopPrefetching()
        focusRequests = []
        focusedID = nil
        lastRowSignature = nil
    }

    private func start(_ requests: [ImageRequest], label: String) {
        guard !requests.isEmpty else { return }
        // Started at once (so a later focus can cancel it); the cache count for the log runs off the main
        // actor, since the disk check touches the file system.
        prefetcher.startPrefetching(with: requests)
        let pipeline = service.pipeline
        Task.detached(priority: .utility) {
            let hits = requests.filter { pipeline.cache.containsCachedImage(for: $0, caches: .all) }.count
            ArtworkService.log.info(
                "Artwork prefetch \(label, privacy: .public): \(requests.count, privacy: .public) images, \(hits, privacy: .public) cached"
            )
        }
    }
}
