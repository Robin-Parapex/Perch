#if DEBUG
import Observation
import PerchCore
import PerchPlex
import SwiftUI

/// DEBUG-only "Library check" (WP-06): what the Plex library returns for the current profile, shown as
/// plain text so the live checks V3 to V5 and the fake-household UI test can read it. Not a product screen,
/// so service names and raw identifiers are fine here.
struct LibraryCheckView: View {
    let core: CoreServices
    @State private var model: LibraryCheckModel

    init(core: CoreServices) {
        self.core = core
        _model = State(initialValue: LibraryCheckModel(core: core))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Library check").font(.title2).accessibilityIdentifier("libraryCheck.title")
                if let error = model.error {
                    line("Error: \(error)", id: "libraryCheck.error")
                }
                if !model.finished { line("Loading", id: "libraryCheck.loading") }
                sectionsBlock
                rowsBlock
                playBlock
                hubsBlock
                detailBlock
                if LibraryCheckModel.writeCheckEnabled { WriteCheckBlock(model: model) }
            }
            .padding(60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await model.load() }
        .accessibilityIdentifier("libraryCheck.screen")
    }

    private func line(_ text: String, id: String? = nil) -> some View {
        Text(text).focusable().accessibilityIdentifier(id ?? "")
    }

    private var sectionsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sections").font(.headline)
            line("\(model.sections.count)", id: "libraryCheck.count.sections")
            ForEach(model.sections) { section in
                line("\(section.title): \(section.kind.rawValue)\(section.isOtherVideos ? ", other videos" : "")")
            }
        }
    }

    private var rowsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.rows, id: \.id) { row in
                Text(row.title).font(.headline)
                line("\(row.items.count)", id: "libraryCheck.count.\(row.id)")
                line(
                    row.items.prefix(3).map(\.title).joined(separator: ", "),
                    id: "libraryCheck.first.\(row.id)")
            }
        }
    }

    /// WP-07 entry point until Home exists: plays through the PlaybackCoordinator.
    private var playBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Play").font(.headline)
            if let error = core.playback.startError {
                line("Play error: \(error)", id: "libraryCheck.play.error")
            }
            ForEach(model.items.filter { $0.kind == .film || $0.kind == .episode }) { item in
                Button("Play \(item.title)") { core.playback.play(item) }
                    .accessibilityIdentifier("libraryCheck.play.\(item.id)")
            }
        }
    }

    private var hubsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hubs (identifier, type, items)").font(.headline)
            ForEach(model.hubs) { hub in
                line("\(hub.id) | \(hub.type ?? "-") | \(hub.items.count)", id: "libraryCheck.hub.\(hub.id)")
            }
        }
    }

    @ViewBuilder
    private var detailBlock: some View {
        if let detail = model.detail {
            VStack(alignment: .leading, spacing: 8) {
                Text("Detail: \(detail.summary.title) (\(model.detailSource))").font(.headline)
                ForEach(Array(detail.markers.enumerated()), id: \.offset) { _, marker in
                    line(
                        "\(marker.kind.rawValue) \(Self.clock(marker.startMs)) to \(Self.clock(marker.endMs))"
                            + (marker.isFinal ? " final" : ""),
                        id: "libraryCheck.marker.\(marker.kind.rawValue)")
                }
                line("Chapters: \(detail.chapters.count)", id: "libraryCheck.chapters")
                ForEach(detail.extras) { extra in
                    line("Extra: \(extra.kind.rawValue) \(extra.title)", id: "libraryCheck.extra.\(extra.id)")
                }
                ForEach(detail.versions) { version in
                    line(
                        "Version \(version.id): \(version.container ?? "-"), video \(version.videoCodec ?? "-"), "
                            + "\(version.videoResolution ?? "-"), audio \(version.audioCodec ?? "-")",
                        id: "libraryCheck.version.\(version.id)")
                    ForEach(version.parts.flatMap(\.streams)) { stream in
                        line(Self.describe(stream), id: "libraryCheck.stream.\(stream.id)")
                    }
                }
            }
        }
    }

    static func clock(_ ms: Int) -> String {
        let seconds = ms / 1000
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    private static func describe(_ stream: MediaStream) -> String {
        switch stream.kind {
        case .video:
            "Video \(stream.codec ?? "-") \(stream.width ?? 0)x\(stream.height ?? 0), DV profile "
                + (stream.dolbyVisionProfile.map(String.init) ?? "none")
        case .audio:
            "Audio \(stream.codec ?? "-"), \(stream.channels ?? 0) channels"
        case .subtitle:
            "Subtitle \(stream.format ?? stream.codec ?? "-")"
        case .other:
            "Other stream"
        }
    }
}

// MARK: Model

@MainActor @Observable
final class LibraryCheckModel {
    struct StepResult: Identifiable {
        let id = UUID()
        let text: String
    }

    /// `-PerchLibraryWriteCheck`: adds the buttons that change watch state on the live server.
    static var writeCheckEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-PerchLibraryWriteCheck")
    }

    let core: CoreServices
    var sections: [PlexLibrarySection] = []
    var rows: [MediaRow] = []
    var hubs: [PlexHub] = []
    var detail: MediaDetail?
    var detailSource = ""
    var error: String?
    var finished = false

    // Write check
    var results: [StepResult] = []
    var selectedItemID: String?
    var running = false
    private var capturedOffsets: [String: Int] = [:]

    init(core: CoreServices) { self.core = core }

    var items: [MediaSummary] {
        var seen = Set<String>()
        return rows.flatMap(\.items).filter { seen.insert($0.id).inserted }
    }

    func load() async {
        defer { finished = true }
        do {
            guard let profile = await core.plexSignIn.session.currentProfile() else {
                error = "No profile is signed in"
                return
            }
            let context = await rowContext(for: profile)
            sections = try await core.library.sections()
            var fetched: [MediaRow] = []
            for provider in core.modules.rowProviders {
                fetched.append(try await ModuleRegistry.refreshRow(provider, in: context))
            }
            rows = fetched
            hubs = try await core.library.hubs()
            // `-PerchLibraryCheckItem <rating key>` shows that title's detail (read-only live check).
            let arguments = ProcessInfo.processInfo.arguments
            let requested = arguments.firstIndex(of: "-PerchLibraryCheckItem")
                .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            let first =
                rows.first { $0.id == PlexHomeRows.continueWatchingID }?.items.first
                ?? rows.first { $0.id == PlexHomeRows.recentlyAddedID }?.items.first
            if let id = requested ?? first?.id {
                detail = try await core.library.detail(ratingKey: id)
                detailSource = id
            }
            if selectedItemID == nil { selectedItemID = items.first?.id }
            captureOffsets()
        } catch {
            self.error = String(describing: error)
        }
    }

    /// Shows the picked item's detail (markers, chapters, extras, versions) in the detail section.
    /// Does nothing when that item is already shown, so the default stays until something is picked.
    func showDetail(for itemID: String?) async {
        guard let itemID, itemID != detailSource, !running else { return }
        do {
            detail = try await core.library.detail(ratingKey: itemID)
            detailSource = itemID
        } catch {
            record("Detail failed for \(itemID): \(error)")
        }
    }

    private func rowContext(for profile: PlexActiveProfile) async -> RowContext {
        let override = await core.settings.document.profiles[profile.id]?.ceilingOverride
        return RowContext(
            profileID: profile.id.rawValue, serviceCeiling: RatingCeiling(plex: profile.restriction),
            ceiling: RatingCeiling.effective(plex: profile.restriction, adminOverride: override))
    }

    // MARK: write check

    private func captureOffsets() {
        for item in items where capturedOffsets[item.id] == nil {
            capturedOffsets[item.id] = item.viewOffsetMs ?? 0
        }
    }

    private var selected: MediaSummary? { items.first { $0.id == selectedItemID } }

    private func record(_ text: String) { results.append(StepResult(text: text)) }

    /// Plays for 30 s of reports, then stops at the original offset, so the server never sees 90%.
    func simulatePlayback() async {
        guard let item = selected, !running else { return }
        running = true
        defer { running = false }
        let original = capturedOffsets[item.id] ?? (item.viewOffsetMs ?? 0)
        do {
            let reporter = try await core.library.startPlayback(item: item, sessionID: nil)
            record("Started \(item.title) at \(original) ms")
            for second in 0..<30 {
                await reporter.report(.playing, positionMs: original + second * 1000)
                try? await Task.sleep(for: .seconds(1))
            }
            await reporter.stop(positionMs: original)
            record("Stopped at the original offset \(original) ms")
        } catch {
            record("Playback failed: \(error)")
        }
    }

    func markWatched() async {
        await change("Mark watched") { try await self.core.library.markWatched($0) }
    }

    func markUnwatched() async {
        await change("Mark unwatched") { try await self.core.library.markUnwatched($0) }
    }

    func restoreOffset() async {
        guard let item = selected else { return }
        let offset = capturedOffsets[item.id] ?? 0
        await change("Restore offset \(offset) ms") {
            try await self.core.library.restoreProgress(itemID: $0, positionMs: offset)
        }
    }

    private func change(_ name: String, _ action: (String) async throws -> Void) async {
        guard let item = selected, !running else { return }
        running = true
        defer { running = false }
        do {
            try await action(item.id)
            record("\(name): done for \(item.title)")
        } catch {
            record("\(name): failed, \(error)")
        }
    }
}

private struct WriteCheckBlock: View {
    @Bindable var model: LibraryCheckModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Write check (live server)").font(.headline)
            Picker("Item", selection: $model.selectedItemID) {
                ForEach(model.items) { item in
                    Text(item.title).tag(Optional(item.id))
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("libraryCheck.write.item")
            .onChange(of: model.selectedItemID) { _, id in
                Task { await model.showDetail(for: id) }
            }
            HStack(spacing: 24) {
                Button("Simulate 30 s of playback") { Task { await model.simulatePlayback() } }
                Button("Mark watched") { Task { await model.markWatched() } }
                Button("Mark unwatched") { Task { await model.markUnwatched() } }
                Button("Restore offset") { Task { await model.restoreOffset() } }
            }
            .disabled(model.running)
            ForEach(model.results) { result in
                Text(result.text).focusable()
            }
        }
    }
}
#endif
