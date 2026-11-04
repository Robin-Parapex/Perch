import Foundation

/// The size classes artwork is requested at. Plex scales to these on the server so the Apple TV
/// decodes small images instead of full-size posters.
public enum ArtworkSize: String, Sendable, CaseIterable, Codable {
    case poster, landscape, backdrop, logo, placeholder

    /// Pixels, not points.
    public var pixelSize: (width: Int, height: Int) {
        switch self {
        case .poster: (300, 450)
        case .landscape: (640, 360)
        case .backdrop: (1920, 1080)
        case .logo: (800, 310)
        case .placeholder: (64, 64)
        }
    }
}
