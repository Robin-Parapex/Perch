# DECISIONS

Append-only log of decisions and why. Newest at the bottom. Format: date, decision, reasons, alternatives rejected, who. When a stage plan decides something not covered here (proxy language, player library, a dependency), add it.

## 2026-10-26 Keep the Apple TV; don't switch to Android TV or a mini PC
- The family likes the Apple TV; it's used for Plex, Apple TV+ (rare), Apple Music, Fitness+ (rare). Apple Music and Fitness+ have no good equivalent elsewhere.
- Rejected: Google TV Streamer (no proper Apple Music, no Fitness+), Nvidia Shield (2019 hardware, price rose to $299), mini PC (DRM limits for streaming apps, clunky Apple services).

## 2026-10-26 Build our own tvOS app rather than a launcher replacement
- tvOS can't be replaced and apps can't draw over other apps. An app that we live in gets most of the benefit; the only gap is overlays during Apple TV+ (rare).
- HomeKit doorbell remains the fallback for those times.

## 2026-10-29 Native SwiftUI from scratch, not a Plezy fork
- Plezy is Flutter; tvOS support is unofficial and fiddly, and it carries Jellyfin/Emby/desktop code we don't need. Native gives Siri dictation, focus engine, materials, Top Shelf and the system player for free.
- Plezy stays a behavioural reference (GPL-3.0: read, don't copy).

## 2026-10-29 Apple's player (AVPlayerViewController) for 1.x; second engine in 2.0
- Native player gives Dolby Vision, Atmos and the Apple look. Plex remuxes what it can't play.
- Audio sync is addressed first by frame-rate matching and direct play; a manual offset arrives with the FFmpeg engine in 2.0.

## 2026-10-29 Distribution via TestFlight internal testing
- No App Review, builds last 90 days, re-upload at least every 10 weeks. Xcode direct install is the fallback.

## 2026-10-30 Homelab proxy holds all secrets and permissions (SUPERSEDED 2026-11-01: app only)
- Keys never in the app bundle; roles enforced server-side; AI spend capped centrally; webhooks need a server anyway.
- Rejected: app-only architecture (keys on device, permissions by hiding buttons).

## 2026-10-30 Backend stays invisible
- Sonarr, Radarr, Decypharr, Usenet, indexers never appear in the UI. Request states are plain words. Admin (parent PIN) is the only place diagnostics show.

## 2026-10-30 Real-Debrid and Usenet both supported, transparently
- Both feed Plex; the app only watches Seerr status and Plex availability. Repair hook handles expired debrid links.

## 2026-10-30 MVP scope = playback + browse + requests (1.0.0)
- Home Assistant features move to 1.3 so 1.0 lands sooner. Player stays native-only in 1.x. (The "Claude API via the proxy" part is superseded by the 2026-11-01 AI decision.)

## 2026-10-30 Versioning: semver, 0.x pre-MVP, 1.0.0 = MVP, one minor per stage
- See `ROADMAP.md` for the rules and map.

## 2026-10-30 One PIN; the app holds the Plex owner token (SUPERSEDED 2026-11-01: PINs come from Plex)
- The app signs in as the Plex account owner and switches Plex Home users itself; the owner token sits in the device Keychain. Plex Home user PINs stay unset; the proxy's parent PIN is the only PIN. Accepted risk: the Apple TV is a device in the home; the proxy still enforces roles independently.
- Rejected: proxy-brokered Plex auth (adds latency to every Plex call and a second PIN system).

## 2026-10-30 "Ready" is detected from the arr import, not from Seerr (SUPERSEDED 2026-11-01: Seerr polling)
- Seerr marks a title available only after Plex has scanned it, so the chain is arr import webhook -> Plex partial scan -> Seerr available -> push. The proxy may read arr queues and calendars; the app never does.

## 2026-10-30 Sidebar navigation, player embedded, overlays in a separate window
- The Apple TV app uses a collapsible left sidebar; a top bar was the thing Plex got wrong. The player is embedded in our container with a higher-level overlay window so the doorbell can draw over playback; our player additions are info-panel actions, not competing gestures.

## 2026-10-30 Top Shelf is always family-safe
- It sits outside any profile PIN, so it only shows items within the household's lowest rating ceiling.

## 2026-10-30 No two-way talk through the doorbell
- tvOS apps have no microphone access. Unlock and Dismiss only.

## 2026-10-30 Name: Perch
- Balcony seat with the best view; a bird's perch as home. Short, logo-friendly. An unrelated Mac utility called Perch exists on the App Store; for any public release use a fuller name ("Perch Cinema") and run a UK IPO search first.

## 2026-11-01 Build from scratch; reference Dusk and Swiftfin rather than fork
- Dusk for Plex (MIT, native Swift, VLCKit) covers much of our 1.x, and forking it would reach an MVP sooner. Chosen instead: our own codebase, Apple's player first, borrowing approaches (and MIT code with notices) from Dusk and Swiftfin. Reasons: we keep AVPlayer for Dolby Vision and Atmos and the Apple look; we avoid inheriting another architecture and an upstream merge burden; the parts that matter most to us (permissions, Home Assistant, recommendations, AI) are ours either way.
- Trade-off accepted: the MVP arrives later (five to six weekends rather than two to three).
- Dusk's DV profile 7 to 8.1 converter and its VLCKit integration are the reference for 2.0. Dusk may also serve as the interim player while Perch is built.

## 2026-11-01 App only: no proxy, no self-hosted Hub
- Supersedes the 2026-10-30 proxy decisions. Everything runs in the app; integrations are optional modules with keys in the device Keychain; roles and budgets are enforced on the device. Reasons: nothing to maintain, nothing for other users to install, a public release stays possible.
- Consequences accepted: "ready" detection polls Seerr (only while requests are pending) instead of webhooks; no automatic repair (Try again re-requests via Seerr); privileged actions are logged on the device.
- Perch never scans Plex on a timer. Sonarr and Radarr's built-in Plex connection handles partial scans on import. Users without Seerr get refresh-on-start and manual refresh options.

## 2026-11-01 PINs come from Plex
- Profile switching uses Plex Home user PINs verified by plex.tv; nothing stored on the device. The Admin PIN defaults to the Plex owner's Home PIN (verified the same way) with an optional app-specific override hashed in the Keychain for offline use. Supersedes the 2026-10-30 "one PIN held by the proxy" decision.

## 2026-11-01 AI is provider-agnostic, bring-your-own-key, no free chat
- OpenAI-compatible endpoint (OpenRouter, OpenAI, Groq, Ollama, LM Studio) and Anthropic adapters; model name is user input; free and cheap models suggested first. One request, one structured result; no conversation mode. Media-only guardrails. Parent-only with a teen toggle; never kids. Four permission levels per profile (recommend, request, navigate, home actions). Voice is Siri dictation into the Ask field. Personalised per profile.

## 2026-11-01 Setup wizard, welcome guide, feedback
- First-run wizard with Plex (plex.tv link or address), Admin PIN, profiles, then skippable module steps; native text fields so the iPhone keyboard works for keys. Scripted interactive guide after setup, presented by the in-app assistant (placeholder name Pip). Feedback by dictation with optional diagnostics, delivered to the Perch feedback endpoint when it exists, else a QR to a GitHub issue, else a user webhook. Tautulli uses an API key (it has no OAuth); tvOS apps have no microphone, so voice is dictation.

## 2026-11-01 Single device now, multi-device later
- One Apple TV for now. Settings are one serialisable document, keys separate, per-person data keyed by Plex user ID, so iCloud sync is a later minor version.

## 2026-11-01 Work is organised as versions and numbered work packages
- Each WP is one branch and one PR; a minor version is released when its WPs are merged and acceptance passes on hardware. Xcode Cloud builds `main` to TestFlight. See `ROADMAP.md`.

## 2026-11-01 Development runs on Claude Code with Opus as lead and subagents
- Opus plans each WP, delegates slices to builder subagents, reads reference repos with scout, reviews diffs with reviewer, runs builds and tests with verifier. Fable is available for orchestration if a WP needs it. See `CLAUDE.md`.

## Lessons from Plex (inputs to our rules)
- Plex's 2025-26 "new experience" moved navigation to the top, added clicks (users reported two clicks becoming six), slowed poster scrolling, and later moved the menu back to the left after backlash. Sources: https://piunikaweb.com/2026/05/04/plex-fire-tv-redesign-unusable-users-slam-navigation/ , https://androidauthority.com/plex-brings-back-left-side-menu-3700033 , https://forums.plex.tv/t/plex-ui-ux-feedback/944453 , https://forums.plex.tv/t/apple-player-update-beta-testing/872121
- Our rules that come from this: two clicks for nightly actions, Back always returns to position, follow tvOS conventions, never rearrange the user's layout, playback stability first, native keyboard with dictation.

## 2026-11-01 PIN safety rules, roles, ceilings
- The Admin PIN can never be empty: if the Plex owner has no Home PIN the wizard requires a Perch PIN. Leaving a kids' profile always needs a PIN (the adult's Plex PIN, else the Admin PIN). Admin needs the parent role and the PIN. Unrestricted Home users default to parent; teen is assigned manually. Plex restriction profiles are the source of truth for rating ceilings, mapped to BBFC (`PERMISSIONS.md`); Admin may only lower them.
- Owner and per-profile Plex tokens are kept in the Keychain; PINs never are. Relaunch resumes the last profile without a PIN.

## 2026-11-01 Second engine is VLCKit; Plex client is our own thin client
- VLCKit (TVVLCKit) for 2.0, proven on tvOS by Dusk. The Plex client is written in-house in `PerchPlex`, using Dusk and Swiftfin as references.

## 2026-11-01 Apple TV model and ATS
- Target device is the Apple TV 4K 3rd generation (HDR10+ capable); older models supported with HDR10+ shown as HDR10. The private build sets `NSAllowsArbitraryLoads` because users type plain-HTTP addresses; a public release would revisit this.

## 2026-11-01 Identifiers and team
- Team Parapex Ltd, ID 3TWLQK4535. Bundle ID `com.robrolabs.perch`, Top Shelf `com.robrolabs.perch.topshelf`, App Group and Keychain access group `group.com.robrolabs.perch`, URL scheme `perch`. Against the domain robrolabs.com.
- Reasons: confirmed in WP-01. Alternatives rejected: the proposed `uk.familybrown` identifiers. Decided by Robin.

## 2026-11-01 The GitHub repo stays public
- Robin-Parapex/Perch stays public. Consequences accepted: anything committed is world-readable, and feedback issues opened through the WP-19 QR route would be public.
- Alternatives rejected: none recorded. Decided by Robin.

## 2026-11-01 XcodeGen for the Xcode project
- `project.yml` (XcodeGen) is the source and the generated `Perch.xcodeproj` is committed. XcodeGen is a local dev tool only, nothing ships in the app, and Xcode Cloud needs no `ci_scripts`.
- Alternatives rejected: none recorded. Decided by Robin.

## 2026-11-01 ATS wording
- `NSAllowsArbitraryLoads` stays, per the existing ATS decision. The "ATS local-network exception" wording in `docs/KICKOFF.md` step 2 is superseded.
- Alternatives rejected: the local-network exception wording. Decided by the lead in the WP-01 plan Robin approved.

## 2026-11-01 Local network usage key
- Info.plist carries `NSLocalNetworkUsageDescription` because Apple documents the key for tvOS 14 and later. `docs/ARCHITECTURE.md` said tvOS has no Local Network privacy prompt; that is corrected. Real prompt behaviour on tvOS 26 is still to be checked on the Apple TV.
- Alternatives rejected: the earlier claim of no prompt on tvOS. Decided by the lead in the WP-01 plan Robin approved.

## 2026-11-01 Module dependencies
- Every module package depends on `PerchCore` only, following `docs/MODULES.md`.
- Alternatives rejected: none recorded. Decided by the lead in the WP-01 plan Robin approved.

## 2026-11-01 Placeholder art
- Wordmark, icon layers and Top Shelf images are generated placeholders (`scripts/make-placeholder-art.swift`) until design exports are supplied. The wordmark is set in SF Pro. No third-party code ships yet; the Top Shelf placeholder follows Dusk's approach (MIT), idea only, no code copied.
- Alternatives rejected: none recorded. Decided by the lead in the WP-01 plan Robin approved.

## Open decisions (resolve in the named work package)
- Assistant name (placeholder Pip) (WP-19).
- Feedback endpoint hosting: Dokploy VPS or Cloudflare Worker (perch-site, later).
- Whether to install on a locked kids' device via Xcode development signing (one-year validity) rather than TestFlight (90 days) (1.3).
- Second engine: KSPlayer vs VLCKit, after reading current licences (2.0).
- Whether to supervise one Apple TV for Single App Mode (1.3; user approval needed because it erases the device).
