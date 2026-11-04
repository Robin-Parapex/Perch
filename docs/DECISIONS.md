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

## 2026-11-02 App Store name: Perch TV
- The App Store Connect app record is named "Perch TV" because "Perch" was taken as a store name. The bundle ID, the in-app name and the home screen name stay Perch.
- Alternatives rejected: "Perch" (taken). Decided by Robin.

## 2026-11-02 Role defaults and ceiling scale
- Owner and unrestricted Plex Home users default to parent, restricted users to kid; teen only by assignment. The "others teen" wording in `docs/PERMISSIONS.md` is corrected.
- Ceilings use U, PG, 12A, 15, 18; a 12 certificate counts as 12A (`docs/ARCHITECTURE.md` corrected). A restricted Plex user with custom ratings Perch cannot read gets U (fail closed). An unknown title certificate stays 15.
- Alternatives rejected: a separate 12 step; unknown custom ratings mapped to 15. Decided by the lead in the WP-02 plan Robin approved.

## 2026-11-02 Admin PIN rules
- Source: a Perch PIN, when set, overrides; otherwise the owner's Plex Home PIN; otherwise setup is required and the wizard must set a Perch PIN. Removing the Perch PIN is refused while the owner has no Plex PIN.
- Perch PIN: 4 to 8 digits, PBKDF2-SHA256 (CommonCrypto, 600k iterations, 16-byte salt), stored in the Keychain.
- Lockout: five wrong PINs lock for 60 s; each further lockout doubles, capped at 1 h; a correct PIN resets it. The state survives relaunch (App Group defaults) and covers Plex and Perch PINs alike. plex.tv being unreachable is not a failed attempt.
- PIN-fresh lasts 5 minutes and is held in memory only. Opening Admin needs the parent role and a fresh Admin PIN.
- Alternatives rejected: an uncapped doubling lockout; a lockout that resets on relaunch. Decided by the lead in the WP-02 plan Robin approved.

## 2026-11-02 Module permissions and tabs
- `Module.policy(for:) -> ActionPolicy?` replaces `requiredRole(for:) -> Role`: a role alone cannot say PIN-fresh, queued or limited. Unknown actions are denied. The core matrix lives in `PerchCore`.
- New `TabProvider` extension point so modules add sidebar tabs (Requests, Music, House).
- Alternatives rejected: keeping `requiredRole`. Decided by the lead in the WP-02 plan Robin approved.

## 2026-11-02 Local storage and Keychain sharing
- tvOS only promises about 500 KB of persistent local storage, through UserDefaults; Apple's tvOS guide says all other local data must be purgeable (App Programming Guide for tvOS, "Local Storage for Your App Is Limited"). So the settings document (JSON with a schema version; keys never go in it), the audit log (capped at 500 entries, not part of a config export) and app-local state (lockout, last profile) are all stored in the App Group defaults suite. Storage sits behind `KeyValueStore`, so a file or iCloud backend can replace it.
- Budget: the settings document plus the audit log stay well under 500 KB. Later WPs that add bulky data (per-title memory, artwork overrides) must check the budget or bring the iCloud sync forward.
- The Keychain is shared by using the App Group ID as the access group, which the existing `application-groups` entitlement allows; no `keychain-access-groups` entitlement is added.
- Alternatives rejected: JSON files in the App Group container (not guaranteed to persist on tvOS; this was the first WP-02 plan, changed after review); an iCloud key-value mirror now (needs iCloud and an entitlement; kept for the "Later" sync item); Core Data or SwiftData. Decided by the lead during WP-02 after the review; Robin to confirm.

## 2026-11-02 Dark only
- Perch sets `UIUserInterfaceStyle` to Dark. `docs/DESIGN.md` defines a dark palette only.
- Alternatives rejected: following the system appearance (DESIGN has no light palette). Decided by the WP-03 lead (Claude) in the WP-03 plan Robin approved.

## 2026-11-02 Liquid Glass always
- tvOS 26 is the minimum, so chrome uses `glassEffect` with no fallback materials.
- Alternatives rejected: fallback materials (no device below tvOS 26). Decided by the WP-03 lead (Claude) in the WP-03 plan Robin approved.

## 2026-11-02 Focus look
- Focus uses the system highlight effect (lift, shadow and parallax, as in the TV app), plus DESIGN's white ring at 3 pt. Labels under artwork do not scale. The focus scale token is 1.06. Card focus scale is set by the system highlight effect. DESIGN's 1.05 to 1.08 card scale is checked by eye on the Apple TV; the 1.06 token applies to buttons.
- Alternatives rejected: a custom scale-and-shadow ButtonStyle (loses native parallax). Decided by the WP-03 lead (Claude) in the WP-03 plan Robin approved.

## 2026-11-02 Reduce Motion
- With Reduce Motion on, scale, Ken Burns and slides become 0.3 s crossfades, and the row lift becomes dim only. One testable function, `PerchMotion.resolve`, decides this.
- Alternatives rejected: per-component ad hoc checks. Decided by the WP-03 lead (Claude) in the WP-03 plan Robin approved.

## 2026-11-02 PerchDesign takes artwork as generic views
- PerchDesign takes artwork as generic views and has no image library. Nuke arrives with WP-08 without PerchDesign depending on it.
- Alternatives rejected: adding Nuke now. Decided by the WP-03 lead (Claude) in the WP-03 plan Robin approved.

## 2026-11-02 Availability wording lives in PerchCore
- Availability wording lives in `PerchCore` (`TitleAvailability`), because feature modules may import `PerchCore` only. PerchDesign renders it.
- Alternatives rejected: wording in PerchDesign (feature modules could not reach it). Decided by the WP-03 lead (Claude) in the WP-03 plan Robin approved.

## 2026-11-02 Design gallery is debug only
- The design gallery is compiled only in DEBUG and never ships in TestFlight. It opens from the placeholder screen or with `-PerchDesignGallery`.
- Alternatives rejected: a hidden Settings switch in release builds. Decided by the WP-03 lead (Claude) in the WP-03 plan Robin approved.

## 2026-11-02 Overlays are containers only in WP-03
- Overlays in WP-03 are SwiftUI containers only. The overlay `UIWindow` host is WP-07 (`PerchPlayer`). The `FocusCoordinator` and remembered focus per screen come with the first real screen.
- Alternatives rejected: building the overlay window now. Decided by the WP-03 lead (Claude) in the WP-03 plan Robin approved.

## 2026-11-02 Layout values fixed in code
- Some layout values have no `docs/DESIGN.md` number and are fixed in code until hardware review: hero height 80% of the screen (heightFraction), logo box 600x140, synopsis width 900, panel corner radius 24. Pages ignore the system safe area and apply the DESIGN margins once.
- Alternatives rejected: guessing DESIGN numbers. Decided by the WP-03 lead (Claude) in the WP-03 plan Robin approved.

## 2026-11-02 Overlays that take focus use a clear full-screen cover
- The side panel, top sheet and corner pill are shown in a `.fullScreenCover` with a clear presentation background and the system animation off. The overlay animates itself in and out.
- tvOS then moves focus into the overlay, keeps the host out of reach and returns focus to the exact element focused before. Menu closes the overlay, not the screen behind it. The corner notice stays passive and does not take focus.
- Proven by UI tests in `PerchUITests/DesignGalleryUITests.swift`.
- Known limits, to revisit with the WP-07 overlay window: the corner pill blocks the host (and a player's transport controls) while it shows, and only one such overlay can be up at a time.
- Alternatives rejected: disabling the host and pulling focus into the overlay (it lost the focused element, so focus could not be restored, and Menu popped the screen). Decided by the WP-03 lead (Claude) in the WP-03 plan Robin approved.

## 2026-11-02 Plex link flow is a short code
- Sign-in links with a short code at plex.tv/link (non-strong `POST /api/v2/pins`), as ROADMAP says. The app polls `GET /api/v2/pins/{id}` every 2 s and shows a new code automatically on expiry. No QR code in WP-04.
- Decided by the WP-04 lead (Claude) in the WP-04 plan Robin approved.

## 2026-11-02 Plex endpoints
- Endpoints (Dusk `marvinvr/dusk-player`, MIT, confirmed against python-plexapi): `GET /api/v2/user` (validate token), `GET /api/v2/home/users`, legacy `POST /api/home/users/{id}/switch?pin=` with the owner token, `GET clients.plex.tv/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1`, server `/identity` and `/library/sections`. JSON everywhere (`Accept: application/json`); the switch response accepts `authToken` or `authenticationToken`.
- Decided by the WP-04 lead (Claude) in the WP-04 plan Robin approved.

## 2026-11-02 Wrong PIN versus unreachable
- A wrong profile PIN is a 401 or 403 on a protected user. Transport errors and timeouts mean unreachable and never count as a failed attempt.
- Decided by the WP-04 lead (Claude) in the WP-04 plan Robin approved.

## 2026-11-02 Profile PIN lockout reuses PINLockout
- Profile switching reuses `PINLockout` (5 tries, 60 s doubling to 1 h), as one lockout for all profile switching, stored under `plex.profilePINLockout` in the App Group defaults. The owner PIN for Admin keeps AdminPIN's own lockout.
- Decided by the WP-04 lead (Claude) in the WP-04 plan Robin approved.

## 2026-11-02 Plex token storage
- The owner account token is in `SecretKey.plexOwnerToken`; each switched profile's account token in `plexUserToken(id)`; each profile's server access token in `SecretKey.module("plex", "server.<userID>")`, so relaunch works when plex.tv is down. The client identifier (not secret) is in App Group defaults `plex.clientIdentifier`; the last profile ID in `plex.lastProfileID`.
- Decided by the WP-04 lead (Claude) in the WP-04 plan Robin approved.

## 2026-11-02 Server choice kept in module config
- Server choice (machine ID, name, last good URI, manual URL) is stored in `settings.modules["plex"].config`, non-secret keys only, so it passes `validate()`.
- Decided by the WP-04 lead (Claude) in the WP-04 plan Robin approved.

## 2026-11-02 Connection choice by probing
- The app probes `/identity` concurrently on every connection. Local beats remote beats relay, with a 1.5 s grace for a better tier; timeouts are 5 s local and 8 s remote (idea from Dusk ServerProbe). The last good URI is tried first. Manual servers are checked by `machineIdentifier` (Dusk does not; we do).
- Decided by the WP-04 lead (Claude) in the WP-04 plan Robin approved.

## 2026-11-02 Manual route: address and token
- The manual route takes an address (IP or host, optional scheme, default port 32400, IPv6 in brackets) plus a token. The token is stored as the owner token. Home users and switching then work if it is an account token; otherwise the app runs as one profile and says profile switching is unavailable (refined by the "Manual route fallback" decision below).
- Decided by the WP-04 lead (Claude) in the WP-04 plan Robin approved.

## 2026-11-02 Plex profiles sync into the settings document
- New Home users get `ProfileSettings.defaults` (owner is an unrestricted parent, a restricted user is a kid). Existing entries keep roles and overrides, but `plexRestriction` is refreshed from Plex, which is the source of truth. An unknown `restrictionProfile` with `restricted == true` becomes `.custom([])`, which maps to U (fail closed). `household.ownerPlexUserID` is set from `/api/v2/user`, and `AdminPIN.setOwnerHasPlexPIN` from the owner's Home user `protected` flag.
- Decided by the WP-04 lead (Claude) in the WP-04 plan Robin approved.

## 2026-11-02 Owner PIN verifier built before AdminPIN
- The owner PIN verifier is built before `AdminPIN` in `CoreServices`. It reads the token at call time, so PerchCore needs no change.
- Decided by the WP-04 lead (Claude) in the WP-04 plan Robin approved.

## 2026-11-02 Unreachable wording
- Signed-in screens say "Can't reach your library right now" with Try again. When plex.tv is down they say "Profile PINs can't be checked right now"; the current profile stays and PIN-protected switches are locked. "Plex" appears only in the sign-in screens (setup context), per GLOSSARY.
- Decided by the WP-04 lead (Claude) in the WP-04 plan Robin approved.

## 2026-11-02 Sign-in screens live in the app target
- The screens live in the app target, reachable in debug from the placeholder ("Plex sign-in" button) and with the launch argument `-PerchPlexSignIn`. PerchPlex stays UI-free apart from its `Module` conformance.
- Decided by the WP-04 lead (Claude) in the WP-04 plan Robin approved.

## 2026-11-02 Debug fault switches
- The launch arguments `-PerchFakePlexTVDown` and `-PerchFakeServerDown` wrap the transport in the app so plex.tv calls, or server calls, fail as unreachable. They exist only in DEBUG builds and let the unreachable states be shown in the simulator.
- Decided by the WP-04 lead (Claude) in the WP-04 plan Robin approved.

## 2026-11-02 The household owner is the Plex Home admin
- Only the Plex Home admin can sign in. Any other Plex account is refused with "Sign in with the account that manages your Plex Home".
- Alternatives rejected: treating whoever links as the owner (a restricted teen with their own account would become an unrestricted parent). Decided by the WP-04 lead (Claude) after review.

## 2026-11-02 Restrictions fail closed
- Any Home user with a restriction profile is treated as restricted even if Plex's `restricted` flag is missing or false. Unknown profiles map to the U ceiling.
- Decided by the WP-04 lead (Claude) after review.

## 2026-11-02 Manual route fallback
- The manual route falls back to a single "Me" profile only when plex.tv rejects the token as an account token. Any other failure fails sign-in. In that mode the Perch Admin PIN is set in the app.
- Decided by the WP-04 lead (Claude) after review.

## 2026-11-02 Profile PIN lockout scope
- The profile PIN lockout applies only when switching to a PIN-protected profile, and switches are serialised.
- Decided by the WP-04 lead (Claude) after review.

## 2026-11-02 WP-04 PIN screen stays simple
- WP-04 ships a centred phone-keypad PIN screen (dots, 3x3 keys with 0 below, outcome line) in the debug sign-in flow. The two-column layout from Dusk's tvOS Home PIN screen (avatar and text left, keypad right) is left for the real profile picker in WP-05. Dusk's behaviour is used now: the fourth digit submits, input pauses while checking, a spinner shows.
- Home users are cached in memory only, so after a relaunch with plex.tv down the profile list is empty; WP-05 should keep the last list so locked profiles still show.
- Alternatives rejected: restyling to Dusk's layout in WP-04 (first-run design belongs to WP-05). Decided by the WP-04 lead (Claude); Robin confirmed the remote path works.

## 2026-11-03 Root routing derives from state
- `AppRoot` shows the wizard until setup is complete, then the profile picker when no profile resumes, otherwise the home. Setup-complete is an app-local flag in App Group defaults (`perch.setupComplete`), next to `plex.lastProfileID`; the settings document schema does not change. Being signed out after setup reopens the wizard at Connect Plex. The idea is from Dusk's ContentView (MIT).
- Decided by the WP-05 lead (Claude) in the WP-05 plan; Robin reviews.

## 2026-11-03 Setup steps
- Welcome, Connect Plex (code, or address and token; confirms with the server name and library count), Choose server (only when more than one), Admin PIN, Profiles and roles, Add later, Done. Connect Plex and Admin PIN cannot be skipped; the others have "Skip for now". Step order, which steps apply, can-skip and can-finish are pure code in `PerchCore` (`SetupProgress`), tested.
- Add later lists entries registered by modules (Requests, Library refresh, Trakt, Home Assistant, Tautulli, AI) as "Coming soon" and writes nothing, so later work packages plug in.
- Decided by the WP-05 lead (Claude) in the WP-05 plan; the critic pass added module registration.

## 2026-11-03 Setup Admin PIN rules
- Setup cannot finish while the Admin PIN source is setup-required or unavailable. Both routes verify through `AdminPIN.verify`: "Use your Plex PIN" (enter it once), or "Set a Perch PIN" (verify the Plex PIN first if the owner has one, then set and confirm by entering it twice). An owner with no Plex PIN must set a Perch PIN. Wizard PINs are 4 digits; longer PINs (up to 8) come with Settings. If plex.tv has not been reached the step shows a wait and Try again, never a way past. Lockout shows in the wizard.
- Profiles and roles: roles change freely, ceilings only downwards, kids default to PIN-to-exit. Edits and re-run use a new `CoreAction.editSetup` (parent only, fresh Admin PIN, audited), with a kid-denied test.
- Decided by the WP-05 lead (Claude) in the WP-05 plan; the critic pass made verification mandatory on both routes.

## 2026-11-03 Leaving a kid profile
- The rule lives in `PerchCore` (`ProfileSwitchPolicy`) and keys on `role == .kid`, not on `pinRequiredToExit`, so a profile changed to kid in setup is covered. Leaving a kid profile for a non-kid needs the target adult's Plex PIN, or the Admin PIN when that adult has none. Otherwise a protected target needs its own Plex PIN; else none.
- When nothing resumed, the "from" profile falls back to the role of the stored `plex.lastProfileID`, so a kid last on the TV cannot pick an adult freely after a failed resume.
- Alternatives rejected: keying on `pinRequiredToExit` (can be switched off). Decided by the WP-05 lead (Claude) after the critic pass.

## 2026-11-03 One profile switching route
- `PlexSession.switchProfile` is internal behind a public entry that needs the policy decision, and the app's `ProfileSwitcher` asks the policy first, so no screen can switch around it. Tested.
- Decided by the WP-05 lead (Claude) after the critic pass.

## 2026-11-03 Offline picker and cached avatars
- PlexSession keeps the last Home user list (id, name, thumb URL, protected, restricted, admin; nothing secret) in App Group defaults, and avatars are cached to disk in a small purgeable cache, so locked profiles show and avatars do not pop in when plex.tv is down. Switching needs plex.tv: offline the current profile stays and the picker says "Can't switch profiles right now" with Try again. This closes the WP-04 note about the in-memory list.
- Decided by the WP-05 lead (Claude) in the WP-05 plan; the critic pass added the avatar cache.

## 2026-11-03 Re-run keeps setup complete until Done
- "Run setup again" is on the temporary home, behind the Admin PIN through the Authoriser, until Settings exists (WP-18). `setupComplete` stays true during a re-run until Done; Back at Welcome during a re-run returns home. A kid sees "Ask a parent to change setup".
- Decided by the WP-05 lead (Claude) after the critic pass.

## 2026-11-03 Network scan and QR code out of scope
- Local network discovery (Bonjour `_plexmediasvr._tcp` or GDM) and a QR code on the link screen are not in WP-05. Both need a check on tvOS and add little while sign-in uses plex.tv. Bonjour is the low-risk route if Robin wants a scan.
- Decided by the WP-05 lead (Claude); Robin to confirm.

## 2026-11-03 DEBUG fake households
- `-PerchFakeHousehold withPINs` (owner with a PIN, a protected adult, a kid) and `-PerchFakeHousehold noPINs` (owner without a PIN, an adult without a PIN, a kid) swap in a canned plex.tv and server transport, with bundled sample art, so both "cannot finish without an Admin PIN" and "leaving a kid asks for a PIN when adults have none" are shown. `-PerchFakeSignedOut` and `-PerchResetSetup` support the signed-out and clean-install cases. DEBUG only; the fake PIN is fixed in the fake. The WP-04 debug sign-in screens are removed; the fault switches stay.
- Decided by the WP-05 lead (Claude) after the critic pass.

## 2026-11-03 One white primary per setup step
- Each setup step has one white primary button; everything else is a glass secondary such as "Skip for now".
- Decided by the WP-05 lead (Claude).

## 2026-11-03 Lock badge and "Watching now"
- In the picker the lock badge marks protected profiles and is the same for every viewer. The current profile shows "Watching now".
- Decided by the WP-05 lead (Claude).

## 2026-11-03 Welcome and Connect have no artwork yet
- Welcome and Connect Plex stay without artwork until a bundled art set exists, because there is no server art before sign-in. From Choose server on, the background is blurred, dimmed library art from the connected server, fetched with the token in a header, never in a URL.
- Alternatives rejected: a gradient background (DESIGN has none). Decided by the WP-05 lead (Claude).

## 2026-11-03 UI tests build signed on a pinned simulator
- The gate builds UI tests signed and runs them on simulator 11ACEAE4 (Apple TV 4K, 3rd generation), because the Keychain needs the entitlement, and fails if any test is skipped. Robin's live simulator is never used.
- Decided by the WP-05 lead (Claude).

## 2026-11-03 Design gallery opens whatever the setup state
- `-PerchDesignGallery` opens the gallery whatever the setup state.
- Decided by the WP-05 lead (Claude).

## 2026-11-03 Library actor and profile generation
- A `PlexLibrary` actor in `PerchPlex/Library/` sits next to `PlexSession`. It gets the base URL, server token, profile ID, machine ID and generation from an internal `PlexSession.libraryContext()`, so the token never leaves PerchPlex. `PlexSession` bumps the generation in `setState` whenever the profile, machine ID or base URL changes or the state leaves `.ready` (activate, switch, `resume()`, sign-out). `PlexLibrary` drops any response with a stale generation by throwing `CancellationError`, so a switch mid-request never shows one profile's rows to another. Switching still goes only through `PlexSession.switchProfile`.
- Decided by the WP-06 lead (Claude); plan approved by Robin, 3 Nov 2026.

## 2026-11-03 Neutral media types in PerchCore
- Plex JSON decodes into internal `PlexWire*` envelopes with every field optional; `librarySectionID`, `extraType` and `index` accept an int or a string. A stream, marker or chapter that fails to decode is dropped, not the whole item. Public results are PerchCore types: `MediaSummary`, `MediaRow`, `MediaDetail` (with `MediaMarker`, `MediaChapter`, `MediaExtra` and `MediaVersion`) and `PlaybackProgress`, so Home, the player and later modules need nothing Plex-shaped.
- Decided by the WP-06 lead (Claude); plan approved by Robin, 3 Nov 2026.

## 2026-11-03 RowProvider and PlaybackReporting shapes
- `RowProvider` has a synchronous `cachedRow(in:)` and an async `refreshRow(in:)`. `RowContext` carries the profile ID, the effective ceiling and an optional subject (rating key). One `RowContext.admit(_:)` filter is applied by the registry to every provider's row, so modules never filter separately. `PlexModule` contributes three Home rows: Continue watching, Up next in your series, Recently added. `PlaybackReporting` (`sessionID`, `report(state:positionMs:)`, `stop(positionMs:)`) lets PerchPlayer report through PerchCore only. The playable source and `PlayerHook` are left for WP-07.
- Decided by the WP-06 lead (Claude); plan approved by Robin, 3 Nov 2026.

## 2026-11-03 Plex library endpoints
- JSON only, token in a header, paging by `X-Plex-Container-Start/Size`. Video sections only, from `/library/sections`; items from `/library/sections/{id}/all`, 50 then 100 per page, stopping on an empty page. Continue watching and Up next come from `/hubs/continueWatching` (items with an offset go to Continue watching, episodes without go to Up next, `/library/onDeck` as fallback, a series in one row only). Recently added comes from `/hubs` (movie, show, season and episode hubs whose identifier contains `recent`, merged by `addedAt`), falling back to `/library/recentlyAdded`. Metadata is `/library/metadata/{rk}` with markers, chapters, extras and guids; `checkFiles=1` only in a separate `metadataForPlayback`. The next episode is found by index and never steps back into season 0. Every path is checked against the live server before merge.
- Decided by the WP-06 lead (Claude); plan approved by Robin, 3 Nov 2026.

## 2026-11-03 Timeline reporting
- `PlexLibrary.startPlayback(item:sessionID:)` returns a `PlexPlaybackReporter` actor that sends `/:/timeline` every 10 s and on every state change. One request is in flight at a time, the newest pending report replaces older ones, and sends go out in order. Seeking back is reported as is; buffering repeats the last known time. `stop()` sends `stopped`. After a generation change the reporter goes inert. The clock is injected for tests.
- Decided by the WP-06 lead (Claude); plan approved by Robin, 3 Nov 2026.

## 2026-11-03 Watched state
- `markWatched` and `markUnwatched` call `/:/scrobble` and `/:/unscrobble`. At `stop()`, a position of at least 90% of a sane duration also scrobbles. Updates are optimistic in memory and reconciled by a refresh; each item carries a revision so a late read cannot undo a newer toggle. Reporter progress updates Continue watching in memory.
- Decided by the WP-06 lead (Claude); plan approved by Robin, 3 Nov 2026.

## 2026-11-03 Watched state under the play permission
- All profiles, kids included, may mark their own titles watched or unwatched, under the existing play permission (`CoreAction.play`: parent, teen and kid yes, Top Shelf no). Watch state is per Plex user. No new matrix row.
- Decided by Robin, 3 Nov 2026.

## 2026-11-03 Home snapshot cache
- The last good rows are kept in memory by profile and server; a failed refresh keeps them and marks the module degraded. On disk, one small JSON snapshot file per profile, with the server's machine id inside it (not one file per profile and server), holds the three Home rows with light fields only, capped at 40 items per row, in the App Group Caches directory (purgeable, outside the 500 KB persistent budget). It is read synchronously at launch, passed through `RowContext.admit` on every read, and rewritten after each good refresh. Sign-out deletes all snapshots. Top Shelf never reads them.
- Decided by the WP-06 lead (Claude); plan approved by Robin, 3 Nov 2026.

## 2026-11-03 Rating ceiling in rows and TV ratings
- Plex already filters managed users' libraries. WP-06 carries each item's certificate, and `admit` drops an item only when the profile's Perch ceiling is below the Plex restriction. Ceilings across all rows and search stay in WP-18.
- `RatingCeiling(certificate:)` learns US TV ratings: TV-Y, TV-Y7 and TV-G become U; TV-PG becomes PG; TV-MA becomes 18; NR and unknown stay 15. TV-14 rounds up to 15 for titles (fail closed) and down to 12A in allowed-rating lists.
- Decided by the WP-06 lead (Claude). Robin confirmed that US TV-14 counts as UK 15, 3 Nov 2026.

## 2026-11-03 Durations the server gets wrong
- Remaining time and progress use the part duration, then the item duration. If either is missing or shorter than the offset (the debrid quirk), remaining is nil and Home shows no "min left".
- Decided by the WP-06 lead (Claude); plan approved by Robin, 3 Nov 2026.

## 2026-11-03 Fake household library
- The DEBUG `-PerchFakeHousehold` canned transport gains library fixtures: sections, continueWatching, hubs, an episode with intro and credits markers, chapters and a trailer, so later work packages can build and UI-test without Plex.
- Decided by the WP-06 lead (Claude); plan approved by Robin, 3 Nov 2026.

## 2026-11-03 Library check (debug only)
- A DEBUG "Library check" button on the placeholder screen lists sections, the three rows' counts and first titles, and, for the first Continue watching item, its markers, chapter count, extras and media summary. It is read-only by default; an opt-in write check (`-PerchLibraryWriteCheck`) and a response dump (`-PerchLibraryDump`) exist. It is removed when WP-09 lands.
- Decided by the WP-06 lead (Claude); plan approved by Robin, 3 Nov 2026.

## 2026-11-03 Live checks against the household server
- A read-only library check (V4) from a signed debug build on Robin's live simulator, and timeline, scrobble and progress calls (V5) on one test title, with watch state restored afterwards. Robin approved both, 3 Nov 2026.
- Decided by Robin, 3 Nov 2026.

## 2026-11-03 Separate WP-06 test simulator
- Package and UI tests during WP-06 development ran on a separate simulator, "Perch WP-06 unit tests" (5341203D, Apple TV 4K 3rd generation, tvOS 27.2), so the shared test simulator 11ACEAE4 stayed free for the other session. The gate still runs on 11ACEAE4.
- Decided by the WP-06 lead (Claude).

## 2026-11-04 Native player kept, with an engine seam
- AVPlayerViewController stays the player in 1.x for native feel, behind a swappable engine seam. Skip and up next use AVKit contextual actions and content proposals. An overlay window carries app overlays.
- Decided by Robin, 4 Nov 2026 ("proceed" after the recommendation).

## 2026-11-04 2.0 second engine only if needed
- WP-36 and WP-37 become "only if real use shows we need it" (4K image subtitles, lossless audio). Plex converts the audio meanwhile.
- Approved by Robin, 4 Nov 2026.

## 2026-11-04 Token transport
- The token is sent as an `X-Plex-Token` header via `AVURLAssetHTTPHeaderFieldsKey`, never in URLs. Proven live for direct play and HLS, including child playlists and segments, with no resource loader needed.
- Decided by the WP-07 lead (Claude).

## 2026-11-04 Transcode profile
- Plex rejected `X-Plex-Client-Profile-Name=Generic` with decision 4005. `X-Plex-Client-Profile-Extra=add-transcode-target(...)` works. Flow: decision, then start.m3u8 with the same items, then stop at teardown.
- Decided by the WP-07 lead (Claude).

## 2026-11-04 Resume
- Offset transcodes open at the resume point (copyts). No client seek when the playhead is within -3/+2 s; direct play still seeks exactly. Warm resume about 0.9 s, first launch about 1.4 s.
- Decided by the WP-07 lead (Claude).

## 2026-11-04 Behaviour defaults until WP-18
- Auto-skip off; autoplay next on, 10 s countdown; "Are you still watching?" after 3 automatic advances with no remote input; estimated credits (duration minus clamp(4%, 45 s, 120 s)) are manual only (Dusk approach); subtitles off unless forced text; no proposal at the chain limit.
- Decided by the WP-07 lead (Claude).

## 2026-11-04 Back in the player
- Back during the up-next countdown cancels the next episode (endAction stop). Measured counts: 1 press with no chrome; 2 when the transport bar or Skip is showing (native AVKit behaviour, kept).
- Decided by the WP-07 lead (Claude).

## 2026-11-04 Player copy
- Headlines are in sentence case, per GLOSSARY. Buttons inside the player use AVKit Title Case (Continue Watching, Try Again, Play Now, Watch Credits, Stop, Back), to sit beside native chrome. Failure lines: parents "It may be a network hiccup. Try again, or come back later."; kids "Ask a grown-up to try again."; others "Try again later, or ask a parent." Raw errors go to the log only.
- Decided by the WP-07 lead (Claude).

## 2026-11-04 Playback log
- About 500 entries, under 200 KB, in App Group Caches `playback-log.jsonl`. `method` is optional (unknown before a decision). Profile ID recorded. URLs scrubbed from errors.
- Decided by the WP-07 lead (Claude).

## 2026-11-04 Fixtures
- Generated clips in one folder, added as a Plex "Other Videos" library (optional for Robin). Dolby Vision, DTS:X, Atmos and PGS are covered by unit tests only.
- Decided by the WP-07 lead (Claude).

## 2026-11-04 Known environment issue: Plex connections
- The remembered Plex address is the public plex.direct:8443 endpoint, which intermittently resets TLS handshakes (seen 4 Nov). LAN connections fail from the simulator (-1003/-1004, possibly DNS rebind protection). Follow-up: prefer local connections and revisit the sticky `lastURI`.
- Recorded by the WP-07 lead (Claude).

## Open decisions (resolve in the named work package)
- Recovery when the stored Perch PIN cannot be read (Admin is locked out by design): confirm the owner through Plex, audited, then allow a new Perch PIN (WP-05).
- Assistant name (placeholder Pip) (WP-19).
- Feedback endpoint hosting: Dokploy VPS or Cloudflare Worker (perch-site, later).
- Whether to install on a locked kids' device via Xcode development signing (one-year validity) rather than TestFlight (90 days) (1.3).
- Second engine: KSPlayer vs VLCKit, after reading current licences. Conditional on 2.0 happening at all (only if real use shows we need it, 4 Nov 2026).
- Whether to supervise one Apple TV for Single App Mode (1.3; user approval needed because it erases the device).
