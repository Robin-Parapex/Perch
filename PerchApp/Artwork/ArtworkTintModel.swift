import Nuke
import Observation
import PerchCore
import PerchDesign
import SwiftUI
import UIKit

/// The page tint that follows focus (WP-08): the focused item's backdrop stand-in, averaged off the main
/// thread (ArtworkTint), cached per image, published for `perchTint` with a 0.4 s crossfade (instant under
/// Reduce Motion). Rapid focus moves are debounced so only the item focus settles on is measured.
@MainActor @Observable
final class ArtworkTintModel {
    private(set) var tint: Color?
    /// The focused backdrop's average luminance (0 dark to 1 bright), so a page can strengthen its text scrim on
    /// bright art (WP-11). Nil until measured.
    private(set) var luminance: Double?

    @ObservationIgnored private let service: ArtworkService
    @ObservationIgnored private var cache: [String: (tint: ArtworkRGB, luminance: Double)] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var current: ArtworkRGB?

    static let debounce = Duration.milliseconds(150)
    static let crossfade = 0.4

    init(service: ArtworkService) { self.service = service }

    func focus(_ item: MediaSummary?) {
        task?.cancel()
        guard let item, let path = item.artworkPath(for: .backdrop),
            let request = service.request(path: path, size: .placeholder)
        else { return }
        // The full cache key (server, path, size), so another server's image never lends its tint.
        guard let key = service.cacheKey(path: path, size: .placeholder) else { return }
        let pipeline = service.pipeline
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            if let cached = self.cache[key] {
                self.apply(cached)
                return
            }
            let measured = await Task.detached(priority: .utility) { () -> (tint: ArtworkRGB, luminance: Double)? in
                guard let image = try? await pipeline.image(for: request), let cgImage = image.cgImage,
                    let average = ArtworkTint.average(of: cgImage)
                else { return nil }
                let luminance = 0.2126 * average.red + 0.7152 * average.green + 0.0722 * average.blue
                return (ArtworkTint.tint(from: average), luminance)
            }.value
            guard !Task.isCancelled, let measured else { return }
            self.cache[key] = measured
            self.apply(measured)
        }
    }

    func reset() {
        task?.cancel()
        cache.removeAll()
        current = nil
        tint = nil
        luminance = nil
    }

    private func apply(_ measured: (tint: ArtworkRGB, luminance: Double)) {
        if luminance != measured.luminance { luminance = measured.luminance }
        let rgb = measured.tint
        guard rgb != current else { return }
        current = rgb
        let animation: Animation? = UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: Self.crossfade)
        withAnimation(animation) { tint = rgb.color }
    }
}
