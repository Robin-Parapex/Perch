import PerchCore
import SwiftUI

/// Small status or format capsule.
public struct Pill: View {
    public enum Kind: Sendable, Hashable {
        case format(String)
        case new
        case availability(TitleAvailability, kids: Bool)
    }

    @Environment(\.perchStyle) private var style
    private let kind: Kind

    public init(_ kind: Kind) { self.kind = kind }

    public var body: some View {
        switch kind {
        case .format(let text):
            Text(text)
                .font(PerchFont.badge(style))
                .foregroundStyle(PerchColor.textBody)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .overlay(Capsule().strokeBorder(PerchColor.textBody, lineWidth: 1))
        case .new:
            Text("NEW")
                .font(PerchFont.badge(style))
                .foregroundStyle(PerchColor.base)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Capsule().fill(Color.white))
        case .availability(let availability, let kids):
            VStack(spacing: 4) {
                Text(availability.label(forKids: kids))
                    .font(PerchFont.badge(style))
                    .foregroundStyle(PerchColor.textPrimary)
                if let progress = availability.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .glassEffect(.regular, in: Capsule())
        }
    }
}
