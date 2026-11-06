import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI

/// One collection's titles as a poster grid (WP-10), pushed on the tab's stack. The rating ceiling applies as on
/// the section grid: the content-rating set when Perch's ceiling is lowered, then `RowContext.admits` on the
/// result. Back pops to the collection card (the shell's `PushedScreen`).
struct CollectionGridScreen: View {
    let core: CoreServices
    let home: HomeProfile
    let route: LibraryCollectionRoute

    @Environment(\.perchStyle) private var style
    @FocusState private var focus: LibraryFocus?
    @State private var items: [MediaSummary] = []
    @State private var phase: LibraryGridModel.Phase = .starting
    @State private var pendingRestore: LibraryFocus?

    private var playerActive: Bool { core.playback.activeSession != nil }
    private var sessionReady: Bool {
        if case .ready = core.plexSignIn.snapshot.state { true } else { false }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PerchSpacing.rowGap) {
                Text(route.title)
                    .font(.system(size: PerchFont.size(48, for: style), weight: .bold))
                    .foregroundStyle(PerchColor.textPrimary)
                    .padding(.leading, PerchSpacing.horizontalMargin)
                    .accessibilityIdentifier("collection.title")
                switch phase {
                case .starting:
                    LibraryPlaceholderGrid(count: 6)
                case .content:
                    LazyVGrid(columns: LibraryGridScreen.columns, alignment: .leading, spacing: 48) {
                        ForEach(items) { item in
                            LibraryPoster(item: item, focus: $focus) { select(item) } onWatched: { watched in
                                Task { await setWatched(watched, item: item) }
                            }
                        }
                    }
                    .padding(.leading, PerchSpacing.horizontalMargin)
                    .focusSection()
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("collection.grid")
                case .empty:
                    LibraryMessage(title: LibraryStrings.collectionEmpty, message: "")
                case .failed:
                    LibraryMessage(
                        title: LibraryStrings.failedTitle, message: LibraryStrings.failedMessage,
                        action: .init(LibraryStrings.tryAgain, identifier: "collection.retry") {
                            Task { await load() }
                        })
                }
            }
            .padding(.top, PerchSpacing.topMargin)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollClipDisabled()
        .ignoresSafeArea()
        .defaultFocus($focus, items.first.map { .item($0.id) })
        .onChange(of: focus) { _, new in
            if case .item(let id) = new, let item = items.first(where: { $0.id == id }) { core.artworkTint.focus(item) }
        }
        .onChange(of: playerActive) { _, active in
            guard !active, let target = pendingRestore else { return }
            pendingRestore = nil
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                focus = target
            }
        }
        .task(id: sessionReady) { if sessionReady, phase != .content { await load() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("collection.root")
    }

    private func load() async {
        let context = home.context
        let library = core.library
        let route = route
        let admitted = await LibraryQueryBuilder.admittedRatings(for: context) {
            try await library.admittedContentRatings(sectionID: route.sectionID, ceiling: context.ceiling)
        }
        let query = PlexSectionQuery(sectionID: route.sectionID, kind: route.kind, contentRatings: admitted)
        do {
            let found = try await library.collectionItems(collectionID: route.collectionID, query: query)
            items = LibraryQueryBuilder.guardPage(found, context: context, existing: [])
            phase = items.isEmpty ? .empty : .content
            core.artworkPrefetcher.prefetch(row: Array(items.dropFirst(18)), size: .poster)
        } catch {
            phase = .failed
        }
    }

    private func select(_ item: MediaSummary) {
        pendingRestore = .item(item.id)
        Task { await LibraryPlayback.play(item, core: core) }
    }

    private func setWatched(_ watched: Bool, item: MediaSummary) async {
        guard (try? await core.library.setWatched(watched, itemID: item.id)) != nil,
            let index = items.firstIndex(where: { $0.id == item.id })
        else { return }
        items[index].viewCount = watched ? max(1, items[index].viewCount) : 0
        items[index].viewOffsetMs = nil
    }
}
