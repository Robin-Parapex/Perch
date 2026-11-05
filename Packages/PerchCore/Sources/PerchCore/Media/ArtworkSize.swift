import Foundation

/// The size classes artwork is requested at. Plex scales to these on the server so the Apple TV
/// decodes small images instead of full-size posters.
public enum ArtworkSize: String, Sendable, CaseIterable, Codable {
    case poster, landscape, backdrop, logo, placeholder

    /// Pixels, not points: twice the largest point size each renders at (tvOS draws at 2x on 4K), e.g. poster
    /// 480x720 for the 240x360 pt grid card.
    public var pixelSize: (width: Int, height: Int) {
        switch self {
        case .poster: (480, 720)
        case .landscape: (672, 380)
        case .backdrop: (3840, 2160)
        case .logo: (1200, 464)
        case .placeholder: (64, 64)
        }
    }
}
