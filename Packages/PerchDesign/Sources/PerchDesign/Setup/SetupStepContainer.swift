import SwiftUI

/// One wizard step: a centred column (title, helper line, content, one primary action and an
/// optional "Skip for now"), progress dots top-right, and an optional blurred, dimmed backdrop.
public struct SetupStepContainer<Content: View>: View {
    /// Title size: `.hero` for welcome and finish screens, `.section` for working steps.
    public enum TitleSize: Sendable { case hero, section }

    private let title: String
    private let helper: String?
    private let titleSize: TitleSize
    private let step: Int
    private let totalSteps: Int
    private let primaryTitle: String
    private let primaryAction: () -> Void
    private let skipTitle: String
    private let skipAction: (() -> Void)?
    private let backdrops: [AnyView]
    private let content: Content
    @Environment(\.perchStyle) private var style

    /// `step` is 1-based; pass `skipAction` to show the secondary "Skip for now"; `backdrop` (or several `backdrops`, crossfaded) is shown blurred and dimmed.
    public init(
        title: String,
        helper: String? = nil,
        titleSize: TitleSize = .section,
        step: Int,
        of totalSteps: Int,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        skipTitle: String = "Skip for now",
        skipAction: (() -> Void)? = nil,
        backdrop: (any View)? = nil,
        backdrops: [any View] = [],
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.helper = helper
        self.titleSize = titleSize
        self.step = step
        self.totalSteps = totalSteps
        self.primaryTitle = primaryTitle
        self.primaryAction = primaryAction
        self.skipTitle = skipTitle
        self.skipAction = skipAction
        self.backdrops = backdrops.isEmpty ? backdrop.map { [AnyView($0)] } ?? [] : backdrops.map { AnyView($0) }
        self.content = content()
    }

    /// Widest the centred column gets.
    public static var maxColumnWidth: CGFloat { 1000 }

    public var body: some View {
        ZStack {
            SetupBackdrop(arts: backdrops)
            column
                .frame(maxWidth: Self.maxColumnWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .perchPageMargins([.horizontal, .vertical])
                .padding(.bottom, 90)  // sits a little above the vertical centre, as on the Apple TV app
        }
        .overlay(alignment: .topTrailing) {
            ProgressDots(current: step, total: totalSteps)
                .padding(.top, PerchSpacing.topMargin)
                .padding(.trailing, PerchSpacing.horizontalMargin)
        }
        .ignoresSafeArea()
        .focusSection()
    }

    private var column: some View {
        VStack(spacing: 28) {
            Text(title)
                .font(titleSize == .hero ? PerchFont.hero(style) : PerchFont.stepTitle(style))
                .foregroundStyle(PerchColor.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .perchStagedEntrance(stage: 0)
            VStack(spacing: 28) {
                if let helper {
                    Text(helper)
                        .font(PerchFont.body(style))
                        .foregroundStyle(PerchColor.textHelper)
                        .multilineTextAlignment(.center)
                }
                content
            }
            .perchStagedEntrance(stage: 1)
            VStack(spacing: 16) {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.perchPrimary)
                    .accessibilityIdentifier("setup.primary")
                if let skipAction {
                    Button(skipTitle, action: skipAction)
                        .buttonStyle(.perchSecondary)
                        .accessibilityIdentifier("setup.skip")
                }
            }
            .padding(.top, 12)
            .perchStagedEntrance(stage: 2)
        }
    }
}

/// Flat base colour, or art blurred and dimmed under a scrim so text stays readable. No gradients.
/// The art drifts slowly (Ken Burns, docs/DESIGN.md); several images crossfade every `interval` seconds.
/// With Reduce Motion there is no drift, only the crossfade.
public struct SetupBackdrop: View {
    private let arts: [AnyView]
    private let interval: Double
    @State private var index = 0
    @State private var drifting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Pass nil for the plain page background.
    public init(art: AnyView?) { self.init(arts: art.map { [$0] } ?? []) }

    /// Several images crossfade in turn; an empty list is the plain page background.
    public init(arts: [AnyView], interval: Double = 12) {
        self.arts = arts
        self.interval = interval
    }

    /// Blur radius and dim opacity of the backdrop.
    public static let blurRadius: CGFloat = 20
    public static let dimOpacity: Double = 0.4

    public var body: some View {
        // Art sits in an overlay so its overflow cannot change the size of the page.
        PerchColor.base
            .overlay {
                if !arts.isEmpty {
                    ZStack {
                        ForEach(arts.indices, id: \.self) { position in
                            arts[position]
                                .scaledToFill()
                                .blur(radius: Self.blurRadius)
                                .scaleEffect(1.1 * (drifting ? 1 + PerchMotion.kenBurnsAmount : 1))  // 1.1 hides the soft edge the blur leaves
                                .offset(x: drifting ? -24 : 24, y: drifting ? 8 : -8)
                                .opacity(position == index ? 1 : 0)
                        }
                        Color.black.opacity(Self.dimOpacity)
                    }
                    .animation(.easeInOut(duration: 1.2), value: index)
                }
            }
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion, PerchMotion.resolve(.kenBurns(amount: PerchMotion.kenBurnsAmount), reduceMotion: reduceMotion) != .none else { return }
                withAnimation(.easeInOut(duration: PerchMotion.kenBurnsDuration).repeatForever(autoreverses: true)) { drifting = true }
            }
            .task(id: arts.count) {
                guard arts.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval))
                    if Task.isCancelled { break }
                    index = (index + 1) % arts.count
                }
            }
    }
}
