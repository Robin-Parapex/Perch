import PerchCore
import PerchDesign
import PerchPlex
import SwiftUI

/// One collection's titles (WP-10), pushed on the tab's stack: a backdrop hero (the collection's art, else its
/// first title's) with the name, the summary when the server has one and the title count, then the poster grid.
/// The rating ceiling applies as on the section grid: the content-rating set when Perch's ceiling is lowered, then
/// `RowContext.admits`, and for a kid the certificate check against the profile ceiling. Back pops to the
/// collection card (the shell's `PushedScreen`).
struct CollectionGridScreen: View {
    let core: CoreServices
    let home: HomeProfile
    let route: LibraryCollectionRoute
    /// Pushes a title or series page on the tab's stack (WP-11).
    let onOpen: (ShellRoute) -> Void

    @Environment(\.perchStyle) private var style
    @FocusState private var focus: LibraryFocus?
    @State private var items: [MediaSummary] = []
    @State private var phase: LibraryGridModel.Phase = .starting
    @State private var pendingRestore: LibraryFocus?
    /// False while a pushed page covers the grid.
    @State private var onScreen = true

    private var playerActive: Bool { core.playback.activeSession != nil }
    private var sessionReady: Bool {
        if case .ready = core.plexSignIn.snapshot.state { true } else { false }
    }

    static let heroHeight: CGFloat = 560
    private let layout = LibraryGridLayout(showsRail: false)

    private var backdropPath: String? {
        route.artPath ?? items.first?.artworkPath(for: .backdrop) ?? route.thumbPath
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PerchSpacing.rowGap) {
                hero
                switch phase {
                case .starting:
                    LibraryPlaceholderGrid(count: 6, layout: layout)
                case .content:
                    LazyVGrid(columns: layout.columns, alignment: .leading, spacing: 48) {
                        ForEach(items) { item in
                            LibraryPoster(item: item, focus: $focus) { select(item) } onPlay: { play(item) } onWatched: { watched in
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
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollClipDisabled()
        .ignoresSafeArea()
        .defaultFocus($focus, items.first.map { .item($0.id) })
        .onChange(of: focus) { _, new in
            if case .item(let id) = new, let item = items.first(where: { $0.id == id }) { core.artworkTint.focus(item) }
        }
        // A page pushed over the grid plays from there: the grid restores only when it is on screen again.
        .onChange(of: playerActive) { _, active in if !active, onScreen { restorePending() } }
        .onAppear {
            onScreen = true
            restorePending()
        }
        .onDisappear { onScreen = false }
        .task(id: sessionReady) { if sessionReady, phase != .content { await load() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("collection.root")
    }

    /// Full-bleed backdrop, faded into the page at the bottom and on the left behind the text. Fixed sizes (no
    /// container-relative frames inside the scroll view).
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkImage(path: backdropPath, size: .backdrop)
                .frame(width: LibraryGridLayout.screenWidth, height: Self.heroHeight)
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: PerchColor.base.opacity(0.8), location: 0),
                            .init(color: PerchColor.base.opacity(0), location: 0.6),
                        ], startPoint: .leading, endPoint: .trailing)
                }
                // Faded out by a mask, not painted over, so it melts into the tinted page with no edge.
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.35),
                            .init(color: .black.opacity(0.35), location: 0.72),
                            .init(color: .clear, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                }
            VStack(alignment: .leading, spacing: 14) {
                Text(route.title)
                    .font(.system(size: PerchFont.size(56, for: style), weight: .bold))
                    .foregroundStyle(PerchColor.textPrimary)
                    .lineLimit(2)
                    .accessibilityIdentifier("collection.title")
                if let summary = route.summary {
                    Text(summary)
                        .font(PerchFont.body(style))
                        .foregroundStyle(PerchColor.textBody)
                        .lineLimit(3)
                        .accessibilityIdentifier("collection.summary")
                }
                if phase == .content, let count = LibraryStrings.collectionCount(items.count) {
                    Text(count)
                        .font(PerchFont.metadata(style))
                        .foregroundStyle(PerchColor.textSecondary)
                        .accessibilityIdentifier("collection.count")
                }
            }
            .frame(width: 1000, alignment: .leading)
            .padding(.leading, PerchSpacing.horizontalMargin)
            .padding(.bottom, 24)
        }
        .frame(width: LibraryGridLayout.screenWidth, height: Self.heroHeight, alignment: .bottomLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("collection.hero")
    }

    private func restorePending() {
        guard let target = pendingRestore else { return }
        pendingRestore = nil
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            focus = target
        }
    }

    /// A failed ratings lookup requests nothing and shows the failure with a retry (which looks the ratings up again).
    private func load() async {
        let context = home.context
        let library = core.library
        let route = route
        let isKid = home.isKid
        do {
            let admitted: Set<String>? =
                LibraryQueryBuilder.isCeilingLowered(context)
                ? try await library.admittedContentRatings(sectionID: route.sectionID, ceiling: context.ceiling)
                : nil
            let query = PlexSectionQuery(sectionID: route.sectionID, kind: route.kind, contentRatings: admitted)
            let found = try await library.collectionItems(collectionID: route.collectionID, query: query)
            items = LibraryQueryBuilder.guardCollectionItems(found, context: context, isKid: isKid)
            phase = items.isEmpty ? .empty : .content
            core.artworkPrefetcher.prefetch(row: Array(items.dropFirst(18)), size: .poster)
        } catch {
            phase = .failed
        }
    }

    /// Select opens the title or series page; Back lands on the same poster.
    private func select(_ item: MediaSummary) {
        pendingRestore = .item(item.id)
        if let page = TitleRoute.page(for: item) {
            onOpen(page)
        } else {
            play(item)
        }
    }

    private func play(_ item: MediaSummary) {
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
