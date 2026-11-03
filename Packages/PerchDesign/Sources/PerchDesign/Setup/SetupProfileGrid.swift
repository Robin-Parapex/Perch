import SwiftUI

/// Rows for the profiles-and-roles step with fixed columns so every row lines up:
/// avatar (96 pt), leading-aligned name, fixed-width role pill, fixed-width rating pill.
/// Generic over the caller's row data; the pills are buttons that call the closures.
public struct SetupProfileGrid<Row: Identifiable>: View {
    public static var avatarSize: CGFloat { 96 }
    public static var pillWidth: CGFloat { 250 }
    /// Compact centred block: avatar, name (flexible, capped by this width), then two pills.
    public static var gridWidth: CGFloat { 1000 }

    private let rows: [Row]
    private let name: (Row) -> String
    private let image: (Row) -> AnyView?
    private let roleTitle: (Row) -> String
    private let ratingTitle: (Row) -> String
    private let onRole: (Row) -> Void
    private let onRating: (Row) -> Void
    @Environment(\.perchStyle) private var style

    public init(
        rows: [Row],
        name: @escaping (Row) -> String,
        image: @escaping (Row) -> (any View)? = { _ in nil },
        roleTitle: @escaping (Row) -> String,
        ratingTitle: @escaping (Row) -> String,
        onRole: @escaping (Row) -> Void,
        onRating: @escaping (Row) -> Void
    ) {
        self.rows = rows
        self.name = name
        self.image = { row in image(row).map { AnyView($0) } }
        self.roleTitle = roleTitle
        self.ratingTitle = ratingTitle
        self.onRole = onRole
        self.onRating = onRating
    }

    public var body: some View {
        VStack(spacing: 20) {
            ForEach(rows) { row in
                HStack(spacing: PerchSpacing.itemGap) {
                    ProfileAvatarImage(name: name(row), size: Self.avatarSize, image: image(row))
                        .padding(.trailing, 4)
                    Text(name(row))
                        .font(PerchFont.section(style).weight(.semibold))
                        .foregroundStyle(PerchColor.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    pill(roleTitle(row), id: "setup.profile.\(String(describing: row.id)).role") { onRole(row) }
                    pill(ratingTitle(row), id: "setup.profile.\(String(describing: row.id)).limit") { onRating(row) }
                }
            }
        }
        .frame(maxWidth: Self.gridWidth)
        .frame(maxWidth: .infinity)
        .focusSection()
    }

    private func pill(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).lineLimit(1).frame(width: Self.pillWidth - 80) // the button style adds 40 pt either side
        }
        .buttonStyle(.perchSecondary)
        .frame(width: Self.pillWidth)
        .accessibilityIdentifier(id)
    }
}
