#if DEBUG
import PerchCore
import SwiftUI

/// Debug-only catalogue of every WP-03 component. Placeholder art is generated gradients and SF Symbols.
public struct DesignGallery: View {
    @State private var kids = false
    @State private var sidePanel = false
    @State private var topSheet = false
    @State private var cornerNotice = false
    @State private var cornerPill = false
    @State private var replay = 0
    @Namespace private var focusNamespace

    public init() {}

    private var style: PerchStyle { kids ? .kids : .standard }

    public var body: some View {
        ScrollViewReader { proxy in
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PerchSpacing.rowGap) {
                Text("Design gallery")
                    .font(PerchFont.section(style))
                    .foregroundStyle(PerchColor.textPrimary)
                    .perchPageMargins(.horizontal)
                    .accessibilityIdentifier("gallery.title")
                overlaysSection
                buttonsSection
                pillsSection
                heroSection
                rowsSection
                setupSection.id("setup")
                kidsSection
            }
            .padding(.vertical, PerchSpacing.topMargin)
        }
        .onAppear { scrollToRequestedSection(proxy) }
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("designGallery")
        .focusScope(focusNamespace)
        .environment(\.perchStyle, style)
        .perchPageBackground()
        .perchSidePanel(isPresented: $sidePanel) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Side panel").font(PerchFont.section(style))
                Text("A glass panel that takes focus while it is shown.").font(PerchFont.metadata(style))
                Button("Close") { sidePanel = false }
                    .buttonStyle(.perchPrimary)
                    .accessibilityIdentifier("sidePanel.close")
            }
            .environment(\.perchStyle, style)
        }
        .perchTopSheet(isPresented: $topSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Top sheet").font(PerchFont.section(style))
                Text("A half-height sheet from the top edge; the page behind it dims.").font(PerchFont.metadata(style))
                Button("Close") { topSheet = false }
                    .buttonStyle(.perchPrimary)
                    .accessibilityIdentifier("topSheet.close")
            }
            .environment(\.perchStyle, style)
        }
        .perchCornerNotice(isPresented: $cornerNotice, autoDismissAfter: .seconds(4)) {
            Label("Added to your list", systemImage: "checkmark.circle")
        }
        .perchCornerPill(isPresented: $cornerPill, title: "Skip intro", systemImage: "forward.fill") {
            cornerPill = false
        }
    }

    // MARK: Sections

    private var overlaysSection: some View {
        section("Overlays") {
            HStack(spacing: 24) {
                Button("Show side panel") { sidePanel = true }
                    .accessibilityIdentifier("gallery.showSidePanel")
                    .prefersDefaultFocus(true, in: focusNamespace)
                Button("Show top sheet") { topSheet = true }
                    .accessibilityIdentifier("gallery.showTopSheet")
                Button("Show corner notice") { cornerNotice = true }
                    .accessibilityIdentifier("gallery.showCornerNotice")
                Button("Show corner pill") { cornerPill = true }
                    .accessibilityIdentifier("gallery.showCornerPill")
            }
            .buttonStyle(.perchSecondary)
        }
    }

    private var buttonsSection: some View {
        section("Buttons") {
            HStack(spacing: 24) {
                Button("Play") {}.buttonStyle(.perchPrimary)
                Button("More info") {}.buttonStyle(.perchSecondary)
                Button("Add") {}.buttonStyle(.perchSecondary)
            }
        }
    }

    private var pillsSection: some View {
        section("Pills and badges") {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Pill(.format("4K"))
                    Pill(.format("Dolby Vision"))
                    Pill(.format("Atmos"))
                    Pill(.format("HDR10+"))
                    Pill(.format("12A"))
                    Pill(.new)
                }
                HStack(spacing: 12) {
                    ForEach(Self.availabilities, id: \.self) { Pill(.availability($0, kids: false)) }
                }
                HStack(spacing: 12) {
                    ForEach(Self.availabilities, id: \.self) { Pill(.availability($0, kids: true)) }
                }
                BadgeStrip([.format("4K"), .format("Dolby Vision"), .format("Atmos"), .format("HDR10+"), .new])
            }
        }
    }

    private static let availabilities: [TitleAvailability] = [
        .requested, .gettingReady(progress: 0.4), .gettingReady(progress: nil),
        .someEpisodesReady, .readyToWatch, .notFound,
    ]

    private var heroSection: some View {
        section("Hero", fullWidth: true) {
            VStack(alignment: .leading, spacing: 24) {
                HeroCard(
                    title: "Sample title",
                    synopsis: "A short made-up synopsis that runs to two lines so the hero layout can be checked. It is placeholder text only.",
                    badges: [.format("4K"), .format("Dolby Vision")],
                    replayKey: replay,
                    backdrop: {
                        LinearGradient(colors: [.indigo, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    },
                    actions: {
                        Button("Play") {}.buttonStyle(.perchPrimary)
                        Button("More info") {}.buttonStyle(.perchSecondary)
                        Button("Add") {}.buttonStyle(.perchSecondary)
                    })
                    // A clear marker the size of the hero, so the test measures layout, not animated artwork.
                    .background {
                        Color.clear.accessibilityElement().accessibilityIdentifier("gallery.hero")
                    }
                Button("Replay") { replay += 1 }.buttonStyle(.perchSecondary)
                    .perchPageMargins(.horizontal)
            }
        }
    }

    private var rowsSection: some View {
        section("Rows", fullWidth: true) {
            RowList {
                Row(title: "Posters") {
                    ForEach(0..<8, id: \.self) { index in
                        PosterCard(
                            title: "Title \(index + 1)", subtitle: "2024",
                            badges: index == 1 ? [.new] : [],
                            availability: index == 2 ? .gettingReady(progress: 0.4) : nil,
                            progress: index == 0 ? 0.4 : nil,
                            action: {}
                        ) { Self.art(index, "film") }
                    }
                }
                Row(title: "Continue watching") {
                    ForEach(0..<6, id: \.self) { index in
                        LandscapeCard(
                            title: "Episode \(index + 1)", subtitle: "31 min left",
                            progress: 0.3 + Double(index) * 0.1, action: {}
                        ) { Self.art(index + 3, "play.rectangle") }
                    }
                }
                Row(title: "Grid size") {
                    ForEach(0..<8, id: \.self) { index in
                        PosterCard(size: .grid, title: "Title \(index + 1)", action: {}) { Self.art(index + 5, "photo") }
                    }
                }
            }
            .frame(height: 1500)
        }
    }

    // MARK: Setup and profiles

    @State private var cover: Cover? = Self.requestedCover()

    private static let sampleProfiles: [ProfilePickerItem] = [
        ProfilePickerItem(id: "sam", name: "Sam", image: sampleArt(.indigo, "person.fill"), isCurrent: true),
        ProfilePickerItem(id: "alex", name: "Alex Brown", isLocked: true),
        ProfilePickerItem(id: "kit", name: "Kit", image: sampleArt(.teal, "star.fill")),
        ProfilePickerItem(id: "guest", name: "Guest", image: sampleArt(.orange, "figure.wave")),
    ]

    private var setupSection: some View {
        section("Setup and profiles") {
            VStack(alignment: .leading, spacing: 36) {
                HStack(spacing: 24) {
                    ProgressDots(current: 2, total: 6)
                    ProgressDots(current: 6, total: 6)
                }
                ProfilePickerRow(items: Self.sampleProfiles, defaultFocusID: "sam") { _ in }
                    .frame(width: 1760)
                    .accessibilityIdentifier("gallery.profilePicker")
                HStack(spacing: 24) {
                    Button("Open step screen") { cover = .step }
                        .accessibilityIdentifier("gallery.openStep")
                    Button("Open PIN screen") { cover = .pin }
                        .accessibilityIdentifier("gallery.openPIN")
                }
                .buttonStyle(.perchSecondary)
            }
        }
        .fullScreenCover(item: $cover) { screen in
            switch screen {
            case .step:
                SetupStepContainer(
                    title: "Connect Plex", helper: "Sign in once and Perch finds your libraries.",
                    step: 2, of: 6, primaryTitle: "Continue", primaryAction: {}, skipAction: {},
                    backdrop: Self.sampleArt(.indigo, "film.stack")
                ) {
                    TextField("Server address", text: .constant("")).perchSetupField()
                }
                .perchPageBackground()
            case .pin:
                PINEntryScreen(name: "Alex Brown", prompt: "Enter your PIN", pin: .constant("12")) { _ in }
            }
        }
    }

    private enum Cover: String, Identifiable {
        case step, pin
        var id: String { rawValue }
    }

    private static func requestedCover() -> Cover? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-PerchDesignGalleryCover"),
              arguments.indices.contains(flag + 1) else { return nil }
        return Cover(rawValue: arguments[flag + 1])
    }

    private func scrollToRequestedSection(_ proxy: ScrollViewProxy) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-PerchDesignGallerySection"),
              arguments.indices.contains(flag + 1) else { return }
        let target = arguments[flag + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo(target, anchor: .top) }
    }

    private static func sampleArt(_ colour: Color, _ symbol: String) -> some View {
        ZStack {
            colour.opacity(0.55)
            Image(systemName: symbol).font(.system(size: 80)).foregroundStyle(.white.opacity(0.85))
        }
    }

    private var kidsSection: some View {
        section("Style") {
            Button(kids ? "Kids style: on" : "Kids style: off") { kids.toggle() }
                .buttonStyle(.perchSecondary)
                .accessibilityIdentifier("gallery.kidsStyle")
        }
    }

    // MARK: Helpers

    /// `fullWidth` sections (hero, rows) span the screen and place their own margins; the rest get the page margins.
    private func section<Content: View>(_ title: String, fullWidth: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(PerchFont.section(style)).foregroundStyle(PerchColor.textSecondary)
                .perchPageMargins(.horizontal)
            if fullWidth {
                content()
            } else {
                content().perchPageMargins(.horizontal)
            }
        }
    }

    private static func art(_ index: Int, _ symbol: String) -> some View {
        let palette: [[Color]] = [[.indigo, .black], [.teal, .black], [.orange, .black], [.purple, .black], [.blue, .black], [.pink, .black]]
        return ZStack {
            LinearGradient(colors: palette[index % palette.count], startPoint: .top, endPoint: .bottom)
            Image(systemName: symbol).font(.system(size: 60)).foregroundStyle(.white.opacity(0.5))
        }
    }
}

#Preview { DesignGallery() }
#endif
