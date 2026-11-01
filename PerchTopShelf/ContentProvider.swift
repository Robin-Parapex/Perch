@preconcurrency import TVServices

// Approach from Dusk (MIT): return nil so tvOS falls back to the static Top Shelf image.
final class ContentProvider: TVTopShelfContentProvider {
    nonisolated(nonsending) override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        nil
    }
}
