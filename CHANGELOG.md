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
- WP-08 Artwork pipeline: sized images from the server (a poster went from 420 KB to 26 KB), blurred placeholders that crossfade to the full image (never a grey box), next-row and focused-item prefetch, page tint from the focused artwork, and a 300 MB on-disk artwork cache that survives relaunch and clears on sign-out and reset.
- WP-08 PerchPlex: clear logos read from Plex for the Home hero.
- WP-08: cached artwork shows while the server is connecting or unreachable (the last server ID is kept until sign-out); a different first ready server clears the artwork caches.
- WP-08: sign-out clears the memory and disk artwork caches, cancels prefetches, resets the tint and removes the remembered picker backdrop; loads that finish after a clear are dropped.
- WP-08: hosted unit test target PerchAppTests (ArtworkServiceTests, 7 tests), run by the gate.
- WP-08: size buckets raised for 4K (poster 480x720, backdrop 3840x2160); a poster is 48,792 B against 419,887 B full size.
- WP-08: the fallback gradient is a calm vertical wash instead of a spotlight.
- WP-09 Home screen: hero with logo or text fallback, metadata line and synopsis; Continue watching, Up next in your series and Recently added rows; first frame rendered from the cached snapshot with no spinner; refresh in place; empty, offline and first-launch states with centred messages; profile menu (Switch profile, Run setup again) top-right until the sidebar lands; kids' style from the profile role; page tint from the hero backdrop; staged entrance animation with Reduce Motion variants; focus memory per row and Back from the player returning to the card.
- WP-09 PerchDesign: HeroCard metadata line, spec scrims that end in the page colour, one-shot 20 s Ken Burns, collapsing synopsis row, `titleIdentifier`; new HeroMessage and ProfileMenuButton; card captions clear the focus lift; composed Home section in the design gallery; `perchAmbientMotion` environment value.
- WP-09 PerchCore and PerchPlex: `MediaSummary.summary` (capped at 300 characters) mapped from Plex; `ModuleRegistry.homeRowProviders` sorted by order then id.
- WP-09 DEBUG: fake household gains summaries, a clearLogo on film 1001 and `-PerchFakeEmptyLibrary`; `-PerchUITests` turns off ambient motion for UI tests.
- WP-09 tests: HomeModelTests (hosted), HomeUITests (focus, Back, two-click resume, cached render with no spinner, empty library, offline, profile menu); ArtworkUITests rewired to Home.
- WP-13 Sidebar shell: Home, Films, Series, Search and Settings tabs, a navigation stack per tab, per-profile focus memory, and the profile avatar in the sidebar header opening the picker. Films, Series and Search are empty pages until WP-10, WP-12 and WP-11.
- WP-13 Settings: switch profile and run setup again (behind the Admin PIN); a kid sees "Ask a parent".
- WP-13 Back: pops within a tab, then moves focus to the sidebar; from the sidebar, Back twice within 2 s leaves the app; double Back from content returns to Home.
- WP-13 Home: the profile menu is removed (the sidebar avatar replaces it), and the hero text fades while the sidebar has focus.
- WP-10 Films and Series grids: paged poster grids with native sort and filter menus (genre, decade, resolution, unwatched) and a letter rail to jump by title.
- WP-10 Collections: a Collections row above the grid and a collection page with a hero; a collection needs two or more titles.
- WP-10 Rating ceiling applied to browse: grids, letters and collections follow the profile's ceiling, checked again on every page; a failed ratings lookup shows Try again.
- WP-10 Debug: fake household browse data (28 films, 13 series, three collections) and a read-only browse probe.
- WP-11 Film and series pages: hero with logo, facts line and inline format marks, a state-aware primary button (Play, Resume, Play next, Play again) with first focus, and icon-circle secondary buttons.
- WP-11 Series page: season chips, episode shelf, and one Play next rule used everywhere a series plays; a jump chip goes to the next episode's season.
- WP-11 Cast rail (focusable, no action until person pages) and a theme music hook, off by default for everyone and never for kids.
- WP-11 Select on a grid, collection or Home series card opens the page; Play/Pause plays. Home refreshes after Back from a page. Certificates show without the country prefix.
- Project document pack (README, CLAUDE.md, spec, roadmap with numbered work packages, modules, architecture, design, integrations, permissions, references, decisions, glossary).
- Decisions through 1 November 2026: name Perch; build from scratch referencing Dusk and Swiftfin; app only with no proxy or hub; Plex PINs for profiles and an Admin PIN; provider-agnostic bring-your-own-key AI with permission levels and no free chat; setup wizard, welcome guide and feedback; Seerr-only polling and user-controlled Plex library refresh.

### Changed
- WP-08: avatars and the profile picker backdrop use the new artwork cache; the old image cache is removed.

### Fixed
- WP-07 PerchPlex: Perch now prefers the server's home-network address. A remembered public address no longer wins without checking local addresses, and when the app starts on a public address it looks for a local one in the background without delaying launch.

- WP-09: artwork loads started while the session connects now wait for it instead of failing.
- WP-09: Home draws from the cached snapshot while the session is still connecting.

### Removed
- WP-05: the WP-04 debug sign-in screens, replaced by the wizard.
- WP-09: the placeholder home, the DEBUG Library check screen and `-PerchLibraryCheck`.
