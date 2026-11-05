import Foundation
import PerchCore
import PerchPlex
import UIKit

/// The library art behind the picker and the PIN screens. The last chosen image's cache key is remembered
/// (App Group defaults, a `perch.` key that `-PerchResetSetup` clears), so the next launch paints the cached
/// image at once and a screen never flashes flat black.
@MainActor
enum LibraryBackdrop {
    nonisolated static let defaultsKey = "perch.artwork.lastBackdrop"

    static func cached(artwork: ArtworkService) -> UIImage? {
        guard let key = CoreServices.plexDefaults().string(forKey: defaultsKey) else { return nil }
        return artwork.cachedImage(key: key)
    }

    static func fetch(session: PlexSession, artwork: ArtworkService) async -> UIImage? {
        // Kid screens show this art too, so only titles the strictest profile may see (U without settings).
        let ceiling = await session.householdArtCeiling()
        guard let path = try? await session.libraryArt(limit: 6, ceiling: ceiling).randomElement(),
            let request = await artwork.resolvedRequest(path: path, size: .backdrop),
            let image = await artwork.image(request)
        else { return nil }
        if let serverID = artwork.serverID {
            CoreServices.plexDefaults().set(
                ArtworkCacheKey.server(serverID: serverID, path: path, size: .backdrop), forKey: defaultsKey)
        }
        return image
    }
}
