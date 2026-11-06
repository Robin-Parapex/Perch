import NukeUI
import PerchCore
import PerchDesign
import SwiftUI

/// Focus targets on a title or series page.
enum TitleFocus: Hashable {
    case primary, synopsis, fromStart, watched
    case season(Int)
    case jumpNext
    case episode(String)
    case cast(String)
}

extension EnvironmentValues {
    /// Set by the shell while a pushed page is not what the viewer sees (another sidebar tab chosen, the profile
    /// picker over the shell): the page stops its theme tune (WP-11).
    @Entry var titlePageCovered = false
}

/// The page's hero: the backdrop faded into the page, the logo or the title, the facts line with its format marks
/// inline, a three-line synopsis that opens in full on Select ("More" only when it is cut), and the actions. Fixed
/// sizes, because container-relative frames inside a scroll view re-laid out every frame on the grids (WP-10). A
/// film's hero is 60% of the height (DESIGN); a series' is taller so the first frame ends inside the episode stills.
struct TitleHero<Actions: View>: View {
    static var filmHeight: CGFloat { 648 }
    /// 1080 less the season row and 115 pt of the stills (WP-11 design pass).
    static var seriesHeight: CGFloat { 832 }

    let height: CGFloat
    let summary: MediaSummary?
    let metadata: String
    let formats: [String]
    let synopsis: String?
    /// The backdrop's luminance (0 to 1) when measured: brighter art gets a stronger scrim behind the text.
    let luminance: Double?
    var focus: FocusState<TitleFocus?>.Binding
    let onMore: () -> Void
    @ViewBuilder let actions: () -> Actions

    @Environment(\.perchStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var textOffset: CGFloat {
        if case .slide(let offset) = PerchMotion.resolve(.slide(offset: PerchMotion.heroTextOffset), reduceMotion: reduceMotion) {
            return shown ? 0 : offset
        }
        return 0
    }

    /// 0.85 on dark art up to 0.95 on bright art at the left edge, and it reaches further across.
    private var scrim: (edge: Double, mid: Double, end: Double) {
        let light = min(1, max(0, ((luminance ?? 0.35) - 0.2) / 0.5))
        return (0.85 + 0.1 * light, 0.55 + 0.25 * light, 0.62 + 0.13 * light)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkImage(path: summary?.artworkPath(for: .backdrop), size: .backdrop)
                .frame(width: LibraryGridLayout.screenWidth, height: height)
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: PerchColor.base.opacity(scrim.edge), location: 0),
                            .init(color: PerchColor.base.opacity(scrim.mid), location: 0.3),
                            .init(color: PerchColor.base.opacity(0), location: scrim.end),
                        ], startPoint: .leading, endPoint: .trailing)
                }
                // Faded out by a mask, not painted over, so it melts into the tinted page (as the collection hero).
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.4),
                            .init(color: .black.opacity(0.4), location: 0.78),
                            .init(color: .clear, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                }
                .opacity(shown ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: luminance)
            VStack(alignment: .leading, spacing: 0) {
                titleBlock
                    .frame(height: 140, alignment: .bottomLeading)
                    .accessibilityIdentifier("title.name")
                VStack(alignment: .leading, spacing: 0) {
                    if !metadata.isEmpty || !formats.isEmpty {
                        FactsLine(metadata, formats: formats, textIdentifier: "title.metadata")
                            .padding(.top, 20)
                    }
                    if let synopsis, !synopsis.isEmpty {
                        Button(action: onMore) { SynopsisText(text: synopsis) }
                            .buttonStyle(SynopsisButtonStyle())
                            .focused(focus, equals: .synopsis)
                            .accessibilityIdentifier("title.synopsis")
                            .padding(.top, 16)
                    }
                    HStack(alignment: .top, spacing: 24) { actions() }
                        .focusSection()
                        .padding(.top, 28)
                }
                .offset(y: textOffset)
            }
            .opacity(shown ? 1 : 0)
            .padding(.leading, PerchSpacing.horizontalMargin)
            .padding(.bottom, 24)
        }
        .frame(width: LibraryGridLayout.screenWidth, height: height, alignment: .bottomLeading)
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? PerchMotion.crossfadeDuration : PerchMotion.heroBackdropFade)) {
                shown = true
            }
        }
    }

    @ViewBuilder
    private var titleBlock: some View {
        let title = summary?.title ?? ""
        if let logo = summary?.logoPath {
            HeroLogo(path: logo, title: title)
        } else {
            Text(title)
                .font(PerchFont.hero(style))
                .foregroundStyle(PerchColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 2)
                .frame(maxWidth: 1200, alignment: .bottomLeading)
        }
    }
}

/// The hero synopsis: three lines at 760 pt. When the text is cut, "More" sits at the end of the last line and the
/// line fades out just before it (as the Apple TV app); when it all fits there is no "More". Focus brightens the
/// text itself.
private struct SynopsisText: View {
    static let width: CGFloat = 760
    let text: String
    @Environment(\.perchStyle) private var style
    @Environment(\.isFocused) private var focused
    @State private var fullHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0

    private var truncated: Bool { fullHeight > shownHeight + 1 }

    var body: some View {
        Text(text)
            .font(PerchFont.body(style))
            .foregroundStyle(focused ? PerchColor.textPrimary : PerchColor.textBody)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .frame(width: Self.width, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
            .background(alignment: .topLeading) {
                Text(text)
                    .font(PerchFont.body(style))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: Self.width, alignment: .leading)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
            }
            .mask { if truncated { lastLineFade } else { Rectangle() } }
            .overlay(alignment: .bottomTrailing) {
                if truncated {
                    Text(TitleStrings.more)
                        .font(PerchFont.body(style).weight(.bold))
                        .foregroundStyle(PerchColor.textPrimary)
                        .accessibilityIdentifier("title.more")
                }
            }
            .animation(PerchMotion.spring, value: focused)
    }

    /// Clears the last line's end so "More" reads on its own: three lines tall, the last fading out before it.
    private var lastLineFade: some View {
        let line = shownHeight / 3
        return VStack(spacing: 0) {
            Rectangle().frame(height: max(0, shownHeight - line))
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 60)
                Color.clear.frame(width: 84)
            }
            .frame(height: line)
        }
    }
}

/// The synopsis as a quiet focusable block: a soft platter and a small lift when focused.
private struct SynopsisButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Styled(configuration: configuration) }

    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(focused ? 0.12 : 0)))
                .scaleEffect(focused ? 1.02 : 1, anchor: .leading)
                .padding(.horizontal, -20)
                .padding(.vertical, -12)
                .animation(PerchMotion.spring, value: focused)
        }
    }
}

/// A season chip's label: the chosen season reads by weight and brightness only; the pill is focus alone.
struct SeasonChipLabel: View {
    let title: String
    let selected: Bool
    @Environment(\.perchStyle) private var style
    @Environment(\.isFocused) private var focused

    var body: some View {
        Text(title)
            .font(PerchFont.metadata(style).weight(selected ? .bold : .medium))
            .lineLimit(1)
            .opacity(focused || selected ? 1 : 0.6)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The full synopsis over the page (Select on the synopsis); Back or Select closes it.
struct SynopsisPanel: View {
    let title: String
    let text: String
    let onClose: () -> Void
    @Environment(\.perchStyle) private var style

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            Button(action: onClose) {
                VStack(alignment: .leading, spacing: 24) {
                    Text(title)
                        .font(PerchFont.section(style).weight(.bold))
                        .foregroundStyle(PerchColor.textPrimary)
                    Text(text)
                        .font(PerchFont.body(style))
                        .foregroundStyle(PerchColor.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(48)
                .frame(width: 1100, alignment: .leading)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
            .buttonStyle(PlainPanelStyle())
            .accessibilityIdentifier("title.synopsisPanel")
        }
        .onExitCommand(perform: onClose)
    }

    private struct PlainPanelStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { configuration.label }
    }
}

/// A static cast rail (no person pages yet): 150 pt portraits, name and part beneath. Focus lifts the portrait
/// and rings it, as the design language's cards do.
struct CastRail: View {
    let cast: [MediaCastMember]
    var focus: FocusState<TitleFocus?>.Binding
    @Environment(\.perchStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(TitleStrings.cast)
                .font(PerchFont.section(style))
                .foregroundStyle(PerchColor.textPrimary)
                .padding(.leading, PerchSpacing.horizontalMargin)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(cast.prefix(24)) { member in
                        Button {} label: { CastCircle(member: member) }
                            .buttonStyle(CastButtonStyle())
                            .focused(focus, equals: .cast(member.id))
                            .accessibilityIdentifier("title.cast.\(member.id)")
                    }
                }
                .padding(.vertical, 28)
            }
            .contentMargins(.horizontal, PerchSpacing.horizontalMargin, for: .scrollContent)
            .scrollClipDisabled()
            .focusSection()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("title.cast")
    }

    private struct CastButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { configuration.label }
    }
}

private struct CastCircle: View {
    let member: MediaCastMember
    @Environment(\.isFocused) private var focused
    @Environment(\.perchStyle) private var style

    var body: some View {
        VStack(spacing: 14) {
            CastPortrait(member: member)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: focused ? PerchSize.focusRingWidth : 0))
                .scaleEffect(focused ? 1.1 : 1)
                .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 18, y: 10)
                .animation(PerchMotion.spring, value: focused)
            VStack(spacing: 4) {
                Text(member.name)
                    .font(PerchFont.metadata(style).weight(.semibold))
                    .foregroundStyle(PerchColor.textPrimary)
                if let role = member.role {
                    Text(role)
                        .font(PerchFont.metadata(style))
                        .foregroundStyle(PerchColor.textSecondary)
                }
            }
            .lineLimit(1)
            .frame(width: 190)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A portrait: a server path through the artwork service, an https address as a public image, initials until then.
private struct CastPortrait: View {
    static let size: CGFloat = 150
    let member: MediaCastMember
    @Environment(ArtworkService.self) private var service: ArtworkService?

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.12))
            Text(initials)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(PerchColor.textSecondary)
            if let path = member.thumbPath {
                if path.hasPrefix("/") {
                    ArtworkImage(path: path, size: .poster)
                } else if let url = URL(string: path), url.scheme == "https", let service,
                    let request = service.publicRequest(url)
                {
                    LazyImage(request: request, transaction: Transaction(animation: .easeInOut(duration: 0.3))) { state in
                        if let image = state.image { image.resizable().scaledToFill().transition(.opacity) }
                    }
                    .pipeline(service.pipeline)
                }
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(Circle())
    }

    private var initials: String {
        member.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

/// DEBUG: the theme tune's state as an invisible element, so UI tests can tell playing from off.
struct ThemeMarker: View {
    let state: ThemeMusicPlayer.State

    var body: some View {
        #if DEBUG
        Text(state.rawValue)
            .font(.system(size: 2))
            .opacity(0.02)
            .frame(width: 4, height: 4)
            .allowsHitTesting(false)
            .accessibilityIdentifier("title.theme")
            .accessibilityLabel(state.rawValue)
        #else
        EmptyView()
        #endif
    }
}
