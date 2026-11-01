# CLAUDE.md

Project: **Perch**, a private native tvOS media and home app for one household. Read `README.md` for the map of this pack. This file is the standing brief for every session.

## What we are building

A SwiftUI tvOS app that replaces Plezy as the family's daily Plex client and becomes the screen the Apple TV lives in. Plex playback, Seerr requests, discovery and recommendations, Apple Music, and Home Assistant (doorbell overlay, lights, scenes, cameras). Installed through TestFlight internal testing; not submitted for App Review in this plan (a public release is a separate, later decision).

Full spec: `docs/SPEC.md`. Version plan: `docs/ROADMAP.md`.

## Stack (fixed unless DECISIONS.md says otherwise)

- **Platform:** tvOS 26 minimum, Apple TV 4K (3rd generation, 2022, the household's device; 2nd generation supported but HDR10+ then plays as HDR10). Swift 6, SwiftUI first, UIKit only where tvOS needs it (focus edge cases, AVPlayerViewController wrapping, Top Shelf).
- **Identifiers (team Parapex Ltd, ID 3TWLQK4535):** bundle ID `com.robrolabs.perch`, Top Shelf `com.robrolabs.perch.topshelf`, App Group `group.com.robrolabs.perch`, Keychain access group the same, URL scheme `perch`. Repo on GitHub.
- **Player:** AVPlayerViewController (Apple's native player) in 1.x. A second FFmpeg-based engine (KSPlayer or VLCKit) is planned for 2.0, with manual audio offset. Do not add it earlier.
- **Dependencies:** keep them few. Approved: Nuke (images). Everything else (Plex, Seerr, Trakt, Home Assistant, TMDB, fanart.tv, Tautulli, AI providers) is a thin client of our own in its module. Any new package needs a line in `docs/DECISIONS.md` first.
- **Navigation:** collapsible left sidebar like the Apple TV app (tabs per version in `docs/SPEC.md` 3). Player embedded in our own container with a separate overlay window above it (`docs/ARCHITECTURE.md`).
- **App only, no server of ours.** The app works with only a Plex server; integrations (Seerr, Home Assistant, Frigate, Tautulli, AI) are optional modules configured in the app with keys in the device Keychain. There is no proxy and no self-hosted Hub; anything that needs a server (webhooks, push) is done by polling instead. See `docs/MODULES.md` (overrides `ARCHITECTURE.md` where they differ).
- **PINs:** profile switching uses Plex Home PINs verified by plex.tv (nothing stored). The Admin PIN defaults to the Plex owner's Home PIN, with an optional app-specific override hashed in the Keychain.
- **AI:** provider-agnostic, bring your own key, model name never hardcoded (OpenAI-compatible endpoint or Anthropic), free and cheap models suggested first. No free chat: one request, one structured result. Budgets and settings sit behind the Admin PIN.
- **Media pipeline (do not expose in UI):** Seerr -> Sonarr/Radarr -> Decypharr (Real-Debrid) and Usenet -> Plex. The app sees Seerr status and Plex availability only.

## Building from scratch, with references

We write our own code. Before implementing any of the following, read how the reference projects did it (`docs/REFERENCES.md`) and borrow the approach, not the files:
- Plex auth, Plex Home switching, hubs, markers, timeline reporting: **Dusk** (MIT) and **Swiftfin** (MPL-2.0, Jellyfin but the same shape). MIT code may be adapted with its licence notice kept in `THIRD_PARTY_NOTICES.md`; MPL files that are copied must stay under MPL and be noted. **Plezy** (GPL-3.0) is read for behaviour only; never paste from it.
- tvOS focus handling, poster rows, Top Shelf: **Swiftfin**.
- Second engine integration (2.0), TrueHD decoding caveats, Dolby Vision profile 7 to 8.1 conversion: **Dusk**.
Every borrowed idea gets a one-line comment naming the source.

## Non-negotiables

1. **Feels like Apple made it.** Native materials, native focus behaviour, native player, native keyboard with Siri dictation. Read `docs/DESIGN.md` before building any screen. If a tvOS convention exists, follow it.
2. **Two clicks or fewer** for anything done nightly (resume, play next episode, request a title, show cameras).
3. **Back always returns to where you were.** No navigation that drops the user somewhere else.
4. **Playback stability before features.** Direct play first, frame-rate and dynamic-range matching on, never a spinner on Home.
5. **No backend jargon in the UI.** Users see "Requested", "Getting it ready", "Some episodes ready", "Ready to watch". Never Sonarr, Radarr, indexer, debrid, symlink. Service names (Plex, Seerr, Trakt, Home Assistant, Tautulli, the AI provider) may appear only in the setup wizard, Settings > Integrations, Help guides and Admin. See `docs/GLOSSARY.md`.
6. **Permissions enforced in code, not by hiding buttons.** `PerchCore` checks the matrix on every privileged action. Kids' profile can never unlock a door regardless of what the UI shows. See `docs/PERMISSIONS.md`.
7. **No secrets in the repo or the app bundle.** User keys live in the Keychain only.
8. **Private build.** No analytics SDKs, no crash reporting that leaves the house unless we add Sentry self-hosted later.

## How work runs

Work is organised as versions made of numbered **work packages** (WP-01, WP-02, ...) in `docs/ROADMAP.md`. One WP = one branch (`wp-15-seerr`) = one pull request. No issue tracker.

1. The user names a WP ("do WP-04"), or says "next", which means the lowest unmerged WP.
2. **Plan first.** Enter plan mode. Read the WP's line in `ROADMAP.md` and the sections of `SPEC.md`, `MODULES.md`, `ARCHITECTURE.md`, `DESIGN.md`, `INTEGRATIONS.md`, `PERMISSIONS.md` it touches. Plan **this WP only**: files, types, screens, tests, and how each related acceptance check will be shown. Present the plan, wait for approval.
3. **Build** on the WP branch in small conventional commits mentioning the WP (`feat(WP-04): plex.tv link flow`). Keep `CHANGELOG.md` current under `Unreleased`.
4. **Hardware before done.** Every screen runs on the real Apple TV (Xcode over the network). The simulator is for layout only.
5. **Finish** with: tests green, the WP's acceptance items demonstrated and listed in the PR description, `DECISIONS.md` appended if anything was decided, PR opened against `main`. Xcode Cloud builds the merge and uploads to TestFlight.
6. Do not start the next WP. Report and stop.
7. **Release** when a version's last WP merges: bump the marketing version, cut the `CHANGELOG.md` section, tag `vX.Y.Z`, confirm the TestFlight build.

## Orchestration

Opus is the lead for each WP and uses subagents: **scout** to read reference repos and docs before planning; **builder** for bounded, fully specified slices; **reviewer** on every diff before the PR; **verifier** for builds, tests and long runs; **tester** to add tests the plan calls for. The lead plans, integrates, judges and reports; it does not re-read every helper's output, it reads the reviewer's verdict and the integrated result. Fable may be used as orchestrator for an unusually large WP if the user asks.

## Versioning

Semantic versioning, `MAJOR.MINOR.PATCH`, with `0.x` for pre-MVP milestones and **1.0.0 = MVP** (the first build the family uses every night instead of Plezy or Dusk). Rules, versions and WPs are in `docs/ROADMAP.md`. Marketing version lives in the Xcode project; Xcode Cloud sets the build number.

## Working with the user

- Robin is technical, runs a homelab (Home Assistant, Frigate, Plex, Seerr, Sonarr/Radarr, Decypharr, Tautulli) and has a Mac with Xcode, Xcode Cloud, App Store Connect and a paid Apple Developer account.
- He wants concise replies, no essays, and no em dashes in written output.
- Ask before: adding a dependency, changing the permission model, anything that resets or supervises the Apple TV, anything that costs money (AI spend, services).
- Don't ask about: file layout within the agreed architecture, naming, test structure, commit granularity. Decide and note it.

## Repo layout (target)

```
Perch/
  CLAUDE.md  README.md  CHANGELOG.md  THIRD_PARTY_NOTICES.md
  docs/                  this pack
  project.yml            XcodeGen source; generated Perch.xcodeproj is committed
  Perch.xcodeproj
  scripts/               local gate and helper scripts
  Packages/              Swift packages, one per module (see docs/MODULES.md)
    PerchCore/  PerchDesign/  PerchPlex/  PerchPlayer/  PerchSeerr/  PerchTrakt/
    PerchHome/  PerchFrigate/ PerchAI/    PerchTautulli/
  PerchApp/              tvOS app target: shell, module composition, Features/ (screens), Resources/
  PerchTopShelf/         Top Shelf extension
  PerchUITests/          focus and navigation smoke tests
```

## Definition of done (every stage)

- Builds clean with no warnings we introduced.
- Runs on the Apple TV 4K; focus moves predictably with the Siri Remote; Back behaves.
- Acceptance checks for the stage pass and are written in the stage report.
- No secrets committed.
- `CHANGELOG.md` updated. TestFlight build uploaded.
