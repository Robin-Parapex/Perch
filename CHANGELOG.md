# Changelog

All notable changes to Perch. Format follows Keep a Changelog; versions follow `docs/ROADMAP.md`.

## [Unreleased]

### Added
- WP-01 skeleton: XcodeGen project, app and Top Shelf targets, UI test target, and ten empty Swift packages.
- Privacy manifest and Info.plist settings.
- Generated placeholder art (wordmark, icon layers, Top Shelf images) until design exports arrive.
- Local gate (`scripts/gate.sh`): package tests and UI smoke test on a tvOS simulator.
- First TestFlight build: 0.1.0 (2) from Xcode Cloud, internal testing (group Household, store name "Perch TV"); installed from TestFlight on the Apple TV 4K and opens to the wordmark (2 November 2026). Xcode Cloud workflow link committed in `Perch.xcodeproj/xcshareddata/xcodecloud/`.
- Project document pack (README, CLAUDE.md, spec, roadmap with numbered work packages, modules, architecture, design, integrations, permissions, references, decisions, glossary).
- Decisions through 1 November 2026: name Perch; build from scratch referencing Dusk and Swiftfin; app only with no proxy or hub; Plex PINs for profiles and an Admin PIN; provider-agnostic bring-your-own-key AI with permission levels and no free chat; setup wizard, welcome guide and feedback; Seerr-only polling and user-controlled Plex library refresh.
