import SwiftUI

/// One entry in the profile picker.
public struct ProfilePickerItem: Identifiable {
    public let id: String
    public let name: String
    public let image: AnyView?
    public let isLocked: Bool
    public let isCurrent: Bool

    /// `id` is the caller's profile id, handed back on selection.
    public init(id: String, name: String, image: (any View)? = nil, isLocked: Bool = false, isCurrent: Bool = false) {
        self.id = id
        self.name = name
        self.image = image.map { AnyView($0) }
        self.isLocked = isLocked
        self.isCurrent = isCurrent
    }
}

/// Centred row of avatars (two rows beyond six), as on the Apple TV "Who's watching?" screen.
public struct ProfilePickerRow: View {
    private let items: [ProfilePickerItem]
    private let defaultFocusID: String?
    private let avatarSize: CGFloat
    private let onSelect: (String) -> Void
    @Namespace private var focusNamespace

    /// `defaultFocusID` is the profile that has focus when the row appears.
    public init(
        items: [ProfilePickerItem], defaultFocusID: String? = nil, avatarSize: CGFloat = 200,
        onSelect: @escaping (String) -> Void
    ) {
        self.items = items
        self.defaultFocusID = defaultFocusID
        self.avatarSize = avatarSize
        self.onSelect = onSelect
    }

    /// Items per line: everything on one line up to six, otherwise two balanced lines.
    nonisolated public static func lineLengths(count: Int) -> [Int] {
        guard count > 6 else { return count > 0 ? [count] : [] }
        let first = (count + 1) / 2
        return [first, count - first]
    }

    public var body: some View {
        VStack(spacing: 48) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 56) {
                    ForEach(line) { item in
                        ProfileAvatar(
                            name: item.name, size: avatarSize, image: item.image,
                            isLocked: item.isLocked, isCurrent: item.isCurrent
                        ) { onSelect(item.id) }
                        .prefersDefaultFocus(item.id == defaultFocusID, in: focusNamespace)
                        .accessibilityIdentifier("profile.\(item.id)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .focusScope(focusNamespace)
        .focusSection()
    }

    private var lines: [[ProfilePickerItem]] {
        var rest = items[...]
        return Self.lineLengths(count: items.count).map { length in
            defer { rest = rest.dropFirst(length) }
            return Array(rest.prefix(length))
        }
    }
}
