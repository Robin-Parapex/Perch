import NukeUI
import PerchCore
import PerchDesign
import SwiftUI

/// Focus targets on a title or series page.
enum TitleFocus: Hashable {
    case primary, synopsis, fromStart, watched
    case season(Int)
    case playNext
    case episode(String)
    case cast(String)
}

/// The page's hero (DESIGN: 60% of the height): the backdrop faded into the page, the logo or the title, the facts
/// line, format badges, a three-line synopsis that opens in full on Select, and the actions. Fixed sizes, because
/// container-relative frames inside a scroll view re-laid out every frame on the grids (WP-10).
struct TitleHero<Actions: View>: View {
    static var height: CGFloat { 648 }

    let summary: MediaSummary?
    let metadata: String
    let badges: [Pill.Kind]
    let synopsis: String?
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

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkImage(path: summary?.artworkPath(for: .backdrop), size: .backdrop)
                .frame(width: LibraryGridLayout.screenWidth, height: Self.height)
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: PerchColor.base.opacity(0.8), location: 0),
                            .init(color: PerchColor.base.opacity(0), location: 0.62),
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
            VStack(alignment: .leading, spacing: 0) {
                titleBlock
                    .frame(height: 140, alignment: .bottomLeading)
                    .accessibilityIdentifier("title.name")
                VStack(alignment: .leading, spacing: 0) {
                    if !metadata.isEmpty {
                        Text(metadata)
                            .font(PerchFont.metadata(style))
                            .foregroundStyle(PerchColor.textSecondary)
                            .lineLimit(1)
                            .padding(.top, 20)
                            .accessibilityIdentifier("title.metadata")
                    }
                    if !badges.isEmpty { BadgeStrip(badges).padding(.top, 14) }
                    if let synopsis, !synopsis.isEmpty {
                        Button(action: onMore) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(synopsis)
                                    .font(PerchFont.body(style))
                                    .foregroundStyle(PerchColor.textBody)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                                if synopsis.count > 160 {
                                    Text(TitleStrings.more)
                                        .font(PerchFont.metadata(style).weight(.semibold))
                                        .foregroundStyle(PerchColor.textPrimary)
                                }
                            }
                            .frame(width: 900, alignment: .leading)
                        }
                        .buttonStyle(SynopsisButtonStyle())
                        .focused(focus, equals: .synopsis)
                        .accessibilityIdentifier("title.synopsis")
                        .padding(.top, 14)
                    }
                    HStack(spacing: 24) { actions() }
                        .focusSection()
                        .padding(.top, 28)
                }
                .offset(y: textOffset)
            }
            .opacity(shown ? 1 : 0)
            .padding(.leading, PerchSpacing.horizontalMargin)
            .padding(.bottom, 24)
        }
        .frame(width: LibraryGridLayout.screenWidth, height: Self.height, alignment: .bottomLeading)
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
                        .fill(Color.white.opacity(focused ? 0.14 : 0)))
                .scaleEffect(focused ? 1.02 : 1, anchor: .leading)
                .padding(.horizontal, -20)
                .padding(.vertical, -12)
                .animation(PerchMotion.spring, value: focused)
        }
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
