import Nuke
import NukeUI
import PerchCore
import PerchDesign
import SwiftUI

/// A sized server image with a blurred stand-in (WP-08). The tiny `.placeholder` copy of the same path loads
/// first and shows blurred; without even that, the quiet gradient. The full image crossfades in over 0.3 s,
/// instantly under Reduce Motion. Never a grey box or a spinner. Reads `ArtworkService` from the environment.
struct ArtworkImage: View {
    enum Phase: Sendable, Equatable {
        case placeholder, loaded
    }

    @Environment(ArtworkService.self) private var service: ArtworkService?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let path: String?
    let size: ArtworkSize
    var tint: ArtworkRGB?
    var contentMode: ContentMode = .fill
    var onPhaseChange: ((Phase) -> Void)?

    init(
        path: String?, size: ArtworkSize, tint: ArtworkRGB? = nil, contentMode: ContentMode = .fill,
        onPhaseChange: ((Phase) -> Void)? = nil
    ) {
        self.path = path
        self.size = size
        self.tint = tint
        self.contentMode = contentMode
        self.onPhaseChange = onPhaseChange
    }

    var body: some View {
        let full = service?.request(path: path, size: size, priority: .high)
        let pixels = size.pixelSize
        // The ideal size carries the artwork's shape, so a card's `.aspectRatio(contentMode: .fill)` keeps it
        // (without it the card sees a square and zooms the image in).
        Color.clear
            .overlay { content(full) }
            .frame(idealWidth: CGFloat(pixels.width), idealHeight: CGFloat(pixels.height))
            .clipped()
    }

    @ViewBuilder
    private func content(_ full: ImageRequest?) -> some View {
        if let service, let full {
            LazyImage(
                request: full,
                transaction: Transaction(animation: reduceMotion ? nil : .easeInOut(duration: 0.3))
            ) { state in
                let loaded = state.image != nil
                // The stand-in leaves the tree once the image is in (crossfading out), so nothing of it
                // can show at the edges or through a transparent logo.
                ZStack {
                    if !loaded { placeholder(service).transition(.opacity) }
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: contentMode).transition(.opacity)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(loaded ? "artwork.loaded" : "artwork.placeholder")
                .onChange(of: loaded, initial: true) { _, now in onPhaseChange?(now ? .loaded : .placeholder) }
            }
            .pipeline(service.pipeline)
        } else {
            fallback
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("artwork.placeholder")
                .onAppear { onPhaseChange?(.placeholder) }
        }
    }

    /// A clearLogo is transparent: never an opaque stand-in behind it, just nothing until it arrives.
    @ViewBuilder
    private var fallback: some View {
        if size == .logo || size == .placeholder { Color.clear } else { ArtworkPlaceholder(image: nil, tint: tint) }
    }

    @ViewBuilder
    private func placeholder(_ service: ArtworkService) -> some View {
        if size == .logo || size == .placeholder {
            Color.clear
        } else if let small = service.request(path: path, size: .placeholder, priority: .veryHigh) {
            LazyImage(request: small) { state in
                ArtworkPlaceholder(image: state.imageContainer?.image.cgImage, tint: tint)
            }
            .pipeline(service.pipeline)
        } else {
            ArtworkPlaceholder(image: nil, tint: tint)
        }
    }
}

extension MediaSummary {
    /// The image path a card or background of this size shows: a series poster for an episode's poster
    /// card, the episode still for a landscape card, the backdrop art (else the thumb) behind a page.
    func artworkPath(for size: ArtworkSize) -> String? {
        switch size {
        case .poster: kind == .episode ? (seriesThumbPath ?? thumbPath) : thumbPath
        case .landscape: thumbPath ?? artPath
        case .backdrop, .placeholder: artPath ?? thumbPath
        case .logo: logoPath
        }
    }
}
