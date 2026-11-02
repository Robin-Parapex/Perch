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
    private let backdrop: AnyView?
    private let content: Content
    @Environment(\.perchStyle) private var style

    /// `step` is 1-based; pass `skipAction` to show the secondary "Skip for now"; `backdrop` is shown blurred and dimmed.
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
        self.backdrop = backdrop.map { AnyView($0) }
        self.content = content()
    }

    /// Widest the centred column gets.
    public static var maxColumnWidth: CGFloat { 1000 }

    public var body: some View {
        ZStack {
            SetupBackdrop(art: backdrop)
            column
                .frame(maxWidth: Self.maxColumnWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .perchPageMargins([.horizontal, .vertical])
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
                .font(titleSize == .hero ? PerchFont.hero(style) : PerchFont.section(style).weight(.bold))
                .foregroundStyle(PerchColor.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .perchStagedEntrance(stage: 0)
            VStack(spacing: 28) {
                if let helper {
                    Text(helper)
                        .font(PerchFont.body(style))
                        .foregroundStyle(PerchColor.textBody)
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
public struct SetupBackdrop: View {
    private let art: AnyView?

    /// Pass nil for the plain page background.
    public init(art: AnyView?) { self.art = art }

    public var body: some View {
        // Art sits in an overlay so its overflow cannot change the size of the page.
        PerchColor.base
            .overlay {
                if let art {
                    ZStack {
                        art
                            .scaledToFill()
                            .blur(radius: 40)
                            .scaleEffect(1.1)  // hides the soft edge the blur leaves
                        Color.black.opacity(0.55)
                    }
                }
            }
        .clipped()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
