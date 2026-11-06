import PerchDesign
import SwiftUI
import UIKit

/// The Settings tab for 0.3 (WP-13): who is watching with Switch profile, and Run setup again behind the Admin PIN
/// (a kid sees why there is none). These moved here from WP-09's top-right profile menu; the full Settings screen
/// is WP-18.
struct SettingsView: View {
    let name: String
    let avatar: UIImage?
    let isKid: Bool
    let onSwitchProfile: () -> Void
    let onRunSetup: () -> Void
    let onGallery: (() -> Void)?

    @Environment(\.perchStyle) private var style
    private enum Focus: Hashable { case switchProfile, runSetup, gallery }
    @FocusState private var focus: Focus?

    var body: some View {
        VStack(alignment: .leading, spacing: 56) {
            Text(ShellStrings.settings)
                .font(PerchFont.stepTitle(style))
                .foregroundStyle(PerchColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            section(SettingsStrings.profile) {
                HStack(spacing: 32) {
                    ProfileAvatarImage(name: name, size: 96, image: avatar.map { Image(uiImage: $0).resizable() })
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        Text(name)
                            .font(PerchFont.section(style).weight(.semibold))
                            .foregroundStyle(PerchColor.textPrimary)
                            .accessibilityIdentifier("settings.profileName")
                        Text(SettingsStrings.watchingNow)
                            .font(PerchFont.metadata(style))
                            .foregroundStyle(PerchColor.textSecondary)
                    }
                    Spacer(minLength: 32)
                    Button(SettingsStrings.switchProfile, action: onSwitchProfile)
                        .buttonStyle(.perchPrimary)
                        .focused($focus, equals: .switchProfile)
                        .accessibilityIdentifier("settings.switchProfile")
                }
            }
            section(SettingsStrings.setup) {
                if isKid {
                    // A kid sees why there is no setup control (spec 6, kid profile).
                    Text(HomeStrings.askParent)
                        .font(PerchFont.body(style))
                        .foregroundStyle(PerchColor.textSecondary)
                        .accessibilityIdentifier("settings.setupRefused")
                } else {
                    HStack(spacing: 24) {
                        Button(SettingsStrings.runSetup, action: onRunSetup)
                            .buttonStyle(.perchSecondary)
                            .focused($focus, equals: .runSetup)
                            .accessibilityIdentifier("settings.runSetup")
                        if let onGallery {
                            Button("Design gallery", action: onGallery)
                                .buttonStyle(.perchSecondary)
                                .focused($focus, equals: .gallery)
                                .accessibilityIdentifier("settings.gallery")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 1200, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, PerchSpacing.topMargin)
        .padding(.horizontal, PerchSpacing.horizontalMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        // Right from the sidebar enters on Switch profile (WP-13).
        .defaultFocus($focus, .switchProfile, priority: .userInitiated)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.root")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(PerchFont.section(style))
                .foregroundStyle(PerchColor.textSecondary)
            content()
        }
        // Each section is a full-width focus section, so Down from Switch profile (alone at the right) reaches
        // the setup buttons at the left (WP-13).
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}

enum SettingsStrings {
    static let profile = "Profile"
    static let watchingNow = "Watching now"
    static let switchProfile = "Switch profile"
    static let setup = "Setup"
    static let runSetup = "Run setup again"
}
