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
- WP-03 PerchDesign: design tokens (colour, type, spacing, radius, sizes, motion) taken from DESIGN.md, with a kids style (16 pt radius, larger type) and an artwork tint for the page background.
- WP-03 PerchDesign: focus and button styles (card highlight with a white focus ring, white primary pill, glass secondary), Pill and BadgeStrip (at most three badges).
- WP-03 PerchDesign: PosterCard, LandscapeCard, Row (snapping, focus section), RowList (focused row lifts, others dim), HeroCard (staged entrance with a slow pan).
- WP-03 PerchDesign: overlay containers: side panel, top sheet, corner notice, corner pill. These are views only; the overlay window comes with the player.
- WP-03 PerchDesign: Reduce Motion turns scale, slide and pan into fades.
- WP-03 PerchCore: TitleAvailability with the glossary wording ("Requested", "Waiting for a parent" for kids, "Getting it ready", "Some episodes ready", "Ready to watch", "Couldn't find this yet").
- WP-03 App: a design gallery in debug builds only, opened from the placeholder screen or with the launch argument `-PerchDesignGallery`. The app is now dark only.
- WP-04 PerchPlex: sign in with a code at plex.tv/link, or with a server address and token.
- WP-04 PerchPlex: server choice, probing connections and using the best one (local, then remote, then relay).
- WP-04 PerchPlex: Plex Home profiles with PIN-checked switching and lockout; restrictions synced from Plex and treated as restricted if in doubt.
- WP-04 PerchPlex: tokens kept in the Keychain; the last profile resumes on relaunch, also when plex.tv is down.
- WP-04 App: plain notices when the library or plex.tv can't be reached.
- WP-04 App: plain sign-in screens and fault switches (`-PerchFakePlexTVDown`, `-PerchFakeServerDown`) in debug builds only.
- WP-04 App: a full-screen four-digit PIN screen for protected profiles and a debug "Check Admin PIN": the fourth digit submits (on-screen keys or a keyboard), a spinner shows while the PIN is checked, and a wrong PIN shakes the dots.
- WP-04 PerchPlex: the profile switch answer from plex.tv is read as JSON or XML; failed plex.tv and server calls are logged by path and status only, never the query or tokens.
- WP-05 Setup wizard: Welcome, Connect Plex (code or address, then "Connected to X, n libraries"), Choose server (only when there is more than one), Admin PIN (use the Plex PIN or set a Perch PIN, entered twice; setup cannot finish without one), Profiles and roles (ratings can only be made stricter), Add later (module-registered "Coming soon" entries) and Done.
- WP-05 App: "Who's watching?" profile picker. Protected profiles ask for their Plex PIN; leaving a kid profile asks for the adult's PIN or the Admin PIN; five wrong tries lock with a countdown. Offline it shows the cached profiles, "Can't switch profiles right now" and Try again.
- WP-05 App: run setup again from the temporary home, behind the Admin PIN; a kid sees "Ask a parent to change setup". Being signed out after setup reopens the wizard at Connect Plex.
- WP-05 PerchDesign: step container with progress dots, blurred library art backdrop with a slow pan, centred PIN screen with shake and lockout countdown, tinted initials avatars with a focus ring, profile grid.
- WP-05 PerchCore: SetupProgress, ProfileSwitchPolicy and CoreAction.editSetup. PerchPlex: a single policy-checked profile switch, cached Home users, library art, and image fetch with the token in a header.
- WP-05 App: DEBUG fake households (`-PerchFakeHousehold withPINs|noPINs`), `-PerchFakeSignedOut` and `-PerchResetSetup`.
- WP-05 Gate: UI tests build signed on a pinned test simulator and fail if any test is skipped.
- WP-06 PerchCore: neutral media types (MediaSummary, MediaRow, MediaDetail with markers, chapters, extras, versions and streams), RowContext with one ceiling filter applied by the registry to every row, the PlaybackReporting protocol, and the RowProvider shape (cached and refreshed rows).
- WP-06 PerchCore: US TV ratings (TV-Y to TV-MA) on the household scale; TV-14 rounds up to 15 for titles and down to 12A in allowed-rating lists.
- WP-06 PerchPlex: library sections and paging, Home rows (Continue watching, Up next in your series, Recently added), hubs, metadata with markers, chapters, extras and stream details, children and next episode.
- WP-06 PerchPlex: timeline reporting every 10 s and on state change, mark watched and unwatched with optimistic updates, scrobble at 90% on stop.
- WP-06 PerchPlex: per-profile Home snapshot in the App Group caches so Home can render without waiting; stale results are dropped after a profile switch.
- WP-06 App: Home row providers wired through PlexModule; DEBUG fake household library data; DEBUG Library check screen with opt-in write check (`-PerchLibraryWriteCheck`) and response dump (`-PerchLibraryDump`).
- WP-06 App: `-PerchLibraryCheckItem <rating key>` (DEBUG) shows that title's detail in Library check.
- WP-07 PerchPlayer: AVPlayerViewController inside our own container, behind a swappable engine seam (`PlaybackEngine`). Native Skip Intro and Skip Credits through contextual actions. Up next through the AVKit content proposal, with the video shrunk top right, a draining Play Now and Watch Credits. Display-mode matching from the playback decision before load. A separate overlay window for app overlays.
- WP-07 PerchPlayer: engine-agnostic playback rules: skip offers (one auto-skip per marker), up next (estimated credits are manual only), "Are you still watching?" after 3 automatic advances with no remote input, and household defaults until WP-18.
- WP-07 PerchPlex and PerchCore: the playback decision table (ARCHITECTURE.md) and playback sources with the Plex token in headers only (decision, start.m3u8, stop). Playback log (capped JSON lines in App Group Caches). PlayerHook context.
- WP-07 App: playback coordinator: resume from the saved position, the next episode, timeline reports with advancing positions, and artwork that never delays playback.
- WP-07 App: "Are you still watching?" and "Couldn't play this" overlays. Try Again is for parents only.
- WP-07 App: DEBUG Play buttons in Library check, `-PerchPlayItem`, `-PerchStartMs`, `-PerchForceOverlay`, `-PerchPolicy`, `-PerchChainStartMs`, the player status probe, and the fake household episode chain with a bundled 60 s clip.
- WP-07 Scripts and docs: `scripts/make-fixtures.sh` and `docs/howto/fixtures-library.md`.
- Project document pack (README, CLAUDE.md, spec, roadmap with numbered work packages, modules, architecture, design, integrations, permissions, references, decisions, glossary).
- Decisions through 1 November 2026: name Perch; build from scratch referencing Dusk and Swiftfin; app only with no proxy or hub; Plex PINs for profiles and an Admin PIN; provider-agnostic bring-your-own-key AI with permission levels and no free chat; setup wizard, welcome guide and feedback; Seerr-only polling and user-controlled Plex library refresh.

### Removed
- WP-05: the WP-04 debug sign-in screens, replaced by the wizard.
