# Changelog

All notable changes to Perch. Format follows Keep a Changelog; versions follow `docs/ROADMAP.md`.

## [Unreleased]

### Added
- WP-01 skeleton: XcodeGen project, app and Top Shelf targets, UI test target, and ten empty Swift packages.
- Privacy manifest and Info.plist settings.
- Generated placeholder art (wordmark, icon layers, Top Shelf images) until design exports arrive.
- Local gate (`scripts/gate.sh`): package tests and UI smoke test on a tvOS simulator.
- First TestFlight build: 0.1.0 (2) from Xcode Cloud, internal testing (group Household, store name "Perch TV"); installed from TestFlight on the Apple TV 4K and opens to the wordmark (2 November 2026). Xcode Cloud workflow link committed in `Perch.xcodeproj/xcshareddata/xcodecloud/`.
- WP-02 PerchCore: module protocol and extension points (rows, title actions, search, overlays, event sources, player hooks, settings pages, admin panels, sidebar tabs, pollers) with a module registry; modules declare an access policy per action.
- WP-02 PerchCore: event bus for overlays and notices.
- WP-02 PerchCore: roles (parent, teen, kid, Top Shelf) and the permission matrix from PERMISSIONS.md, enforced in code with room and AI-level rules; Authoriser checks Admin PIN freshness and logs every privileged action, allowed or denied, to a local audit log (500 entries).
- WP-02 PerchCore: rating ceilings (U, PG, 12A, 15, 18) mapped from Plex Home restriction profiles; Admin can lower a ceiling, never raise it; Top Shelf uses the household's lowest.
- WP-02 PerchCore: Admin PIN defaults to the Plex owner's Home PIN, or a Perch PIN (4 to 8 digits, PBKDF2 hashed in the Keychain) when the owner has none or as an override; never empty; five wrong attempts lock for 60 s, doubling to a 1 h cap, surviving relaunch; fails closed if the stored PIN cannot be read.
- WP-02 PerchCore: Keychain store shared through the App Group access group, with keys shown masked; settings keyed by Plex user ID and stored with the audit log in the App Group defaults suite; config export never contains keys.
- WP-02 PerchCore: pollers with stepped schedules that run only while the app is active; Debug-only launch self-check of the Keychain and App Group defaults.
- WP-02 PerchCore: decisions recorded (2 November 2026); PERMISSIONS, ARCHITECTURE and MODULES corrected where they disagreed.
- Project document pack (README, CLAUDE.md, spec, roadmap with numbered work packages, modules, architecture, design, integrations, permissions, references, decisions, glossary).
- Decisions through 1 November 2026: name Perch; build from scratch referencing Dusk and Swiftfin; app only with no proxy or hub; Plex PINs for profiles and an Admin PIN; provider-agnostic bring-your-own-key AI with permission levels and no free chat; setup wizard, welcome guide and feedback; Seerr-only polling and user-controlled Plex library refresh.
