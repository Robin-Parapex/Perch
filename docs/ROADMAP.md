# ROADMAP

Versions and numbered work packages. Each work package (WP) is one branch and one pull request, planned with `/plan` just before it starts, built, reviewed, and merged. A minor version is released when all of its WPs are merged and its acceptance checks pass on the Apple TV. No issue tracker is needed: the WP number is the unit of work.

## Versioning rules

Semantic versioning `MAJOR.MINOR.PATCH`.

| Bump | When |
|---|---|
| **MAJOR** | A new playback engine, a change to the permission model, or a redesign of the main navigation. Also 1.0.0 itself (the MVP). |
| **MINOR** | A stage below. One minor per stage. |
| **PATCH** | Fixes, polish, performance, copy, artwork. Shipped between stages whenever needed. |

- `0.x` versions are pre-MVP milestones; the family may try them but the previous player stays installed.
- **1.0.0 is the MVP**: the first build the family uses every night instead of Plezy or Dusk.
- Branches: `wp-15-seerr`. Commits: conventional (`feat:`, `fix:`, `chore:`, `docs:`), each mentioning its WP (`feat(WP-15): ...`). Tags: `v1.0.0`.
- `CHANGELOG.md` follows Keep a Changelog; the `Unreleased` section lists merged WPs; a release cuts it into a version section.
- Xcode Cloud builds every merge to `main` and uploads to TestFlight internal testing; the build number is set by Xcode Cloud. TestFlight builds expire after 90 days, so a build is pushed at least every 10 weeks regardless.

## Stage table

Effort assumes Claude Code writes most of the code and Robin tests on the TV in evenings and weekends.

| Version | Stage | Work packages | Effort |
|---|---|---|---|
| 0.1.0 | Foundations and setup wizard | WP-01 to WP-05 | 1 to 2 weekends |
| 0.2.0 | First playback | WP-06 to WP-09 | 1 to 2 weekends |
| 0.3.0 | Browse, search, library refresh | WP-10 to WP-14 | 1 weekend |
| **1.0.0** | **MVP: requests, profiles, guide, feedback, hardening** | WP-15 to WP-21 | 2 weekends |
| 1.1.0 | Discovery and Trakt | WP-22 to WP-23 | 1 weekend |
| 1.2.0 | Recommendations, people, seasonal, polish | WP-24 to WP-28 | 1 to 2 weekends |
| 1.3.0 | House and Music | WP-29 to WP-35 | 2 weekends |
| 2.0.0 | Second player engine | WP-36 to WP-37 | 1 to 2 weekends |
| 2.1.0 | AI | WP-38 to WP-41 | 1 to 2 weekends |
| 2.2.0 | Insights and full Admin | WP-42 to WP-43 | 1 weekend |
| 2.3.0 | House extended | WP-44 to WP-45 | 1 weekend |

Roughly 13 to 19 weekends in total; the MVP around weekend 5 to 7.

---

## 0.1.0 Foundations and setup wizard

- **WP-01 Project skeleton.** Xcode project; targets `PerchApp`, `PerchTopShelf`, UI tests; Swift packages under `Packages/` (empty but compiling); Swift 6, tvOS 26 minimum; bundle IDs, App Group, Keychain access group and the `perch` URL scheme from `CLAUDE.md`; Xcode Cloud workflow building `main` to TestFlight internal testing; `THIRD_PARTY_NOTICES.md`; privacy manifest; ATS setting (`NSAllowsArbitraryLoads` for this private build); export-compliance flag; a placeholder screen with the wordmark to prove the pipeline; `docs/notes/reference-review.md` from an afternoon reading Dusk and Swiftfin. **Robin's manual steps** (the lead lists them and waits): create the GitHub repo and push; create the app record in App Store Connect with the bundle ID; create the Xcode Cloud workflow from Xcode (Product > Xcode Cloud) and grant it the repo; add himself as an internal tester.
- **WP-02 PerchCore.** `Module` protocol and extension points (`MODULES.md`), `EventBus`, Keychain store, the settings document (serialisable, keys separate, per-person data keyed by Plex user ID), roles and the permission matrix, rating ceiling mapping from Plex restriction profiles (`PERMISSIONS.md`), Admin PIN (Plex-owner default, Perch PIN required when the owner has none, never empty), `Poller`, local audit log. Unit tests for the matrix, the ceiling mapping and the PIN lockout.
- **WP-03 PerchDesign.** Tokens, materials, `PosterCard`, `LandscapeCard`, `Row`, `HeroCard`, `Pill`, `Badge`, overlay containers, focus styles, Reduce Motion variants. A preview gallery screen behind a debug flag.
- **WP-04 PerchPlex sign-in.** plex.tv link flow (code on screen, enter at plex.tv/link) and manual server address with token; server selection when there are several; Plex Home users with restriction profiles; PIN verification through the Home switch endpoint; owner and per-user tokens in Keychain; relaunch resumes the last profile; "server unreachable" and "plex.tv unreachable" states. Thin Plex client of our own (decided).
- **WP-05 Setup wizard shell and profile picker.** Step framework (progress, Skip for now, Back), native text fields everywhere so the iPhone keyboard prompt works, steps: Welcome, Connect Plex (link or address), Choose server, Admin PIN (use Plex owner PIN, or set a Perch PIN; required when the owner has none), Profiles and roles (defaults per `PERMISSIONS.md`, editable), then placeholders for Seerr, Library refresh, Trakt, Home Assistant, Tautulli, AI that say "coming soon" until their WPs land. Profile picker with the leave-kids-profile PIN rule. Wizard re-runnable from Settings.

**Acceptance**
- Installs from TestFlight via Xcode Cloud on the Apple TV 4K.
- Wizard completes with Plex only and refuses to finish with an empty Admin PIN; profile picker shows the household; switching to a PIN-protected Plex Home profile asks for that PIN and plex.tv verifies it; leaving a kid profile asks for a PIN even when the adult profiles have none.
- Admin PIN gates Settings > Integrations; Admin refuses a kid-role session even with the correct PIN (test exists); five wrong attempts lock out.

## 0.2.0 First playback

- **WP-06 PerchPlex library.** Sections, hubs, Continue watching, Recently added, metadata with markers, chapters and extras, timeline reporting, watched state.
- **WP-07 PerchPlayer.** AVPlayerViewController inside our container, overlay window above it, decision table from `ARCHITECTURE.md`, `preferredDisplayCriteria` matching, resume, Skip Intro / Skip Credits, next-episode countdown, "Are you still watching?", playback log.
- **WP-08 Artwork pipeline.** Nuke, prefetch for the next row and the focused backdrop, blurred placeholders, tint extraction.
- **WP-09 Basic Home.** Hero (library title, logo fallback to text), Continue watching, Up next in your series, Recently added, cached render with no spinner.

**Acceptance**
- The fixture library's codec matrix plays; each file's logged decision matches the table.
- Resume within 2 s; no dropped-frame warnings on the 80 Mbit/s 4K sample over Ethernet.
- Home renders from cache with no spinner on second launch; launch to Home under 1.5 s warm.

## 0.3.0 Browse, search, library refresh

- **WP-10 Films and Series.** Grids, sort, filters, alphabetical jump, collections.
- **WP-11 Series and title pages.** Season rail, episode list, Play next, title page for library items with the state-aware primary button, cast rail (static), theme music hook (off for kids).
- **WP-12 Search.** Native keyboard with Siri dictation, library results.
- **WP-13 Sidebar and navigation.** Collapsible sidebar (Home, Films, Series, Search, Settings), profile avatar, focus restoration, Back audit on every screen, double-tap Back to Home.
- **WP-14 Library refresh.** Settings: refresh on app start (off / all / chosen libraries; runs after Home has rendered), manual refresh in the sidebar menu and Admin (per library or all, with progress). Copy says it wakes the server's drives. Default on-start setting prompted during setup when Seerr is not connected.

**Acceptance**
- Any library title in <= 3 clicks from Home; resume and next episode in <= 2.
- With the search field focused, holding the Siri button dictates a title and results appear.
- Back returns to the exact row and item on every screen.
- Manual refresh of one library shows progress and new files appear in Recently added when done.

## 1.0.0 MVP

- **WP-15 PerchSeerr.** Sign-in with each profile's Plex token (API key fallback that sets the matching Seerr account explicitly; no match means "Ask a parent"), request create (series, season, film), state mapping to plain words, approval queue for non-parents with corner notice and badge, a minimal **Requests tab** (Mine, Waiting with Approve for parents), "Requested and now ready" row with NEW badge, polling policy (`MODULES.md`: Seerr only, only while requests are pending, 30 s then 2 min then 5 min), wizard step.
- **WP-16 Requesting from the app.** Title page for titles not in the library (Request / Latest season only / Requested / Getting it ready / Some episodes ready / Ready to watch / Couldn't find this yet), "You could request" in search, Similar titles rail with state tags, long-press Request for another profile.
- **WP-17 Hero, Top Shelf, deep links.** Hero with logo, badges, synopsis, trailer crossfade from local extras; family-safe Top Shelf (lowest rating ceiling, read-only); `perch://` deep links.
- **WP-18 Profiles, roles, Settings.** Kids' profile behaviour (leave via an adult's Plex PIN), rating ceilings applied to every row and search, per-profile Settings (subtitles, audio, autoplay, auto-skip, DND default, theme music), Admin PIN gating of Integrations, AI, Profiles, Admin.
- **WP-19 Welcome guide, feedback, What's new.** Scripted interactive guide after setup (coach marks over the sidebar, Home rows, Settings, Admin; replayable from Settings; presented by the in-app assistant, placeholder name Pip, no AI needed); Support and feedback screen (dictated text, optional diagnostics, delivered to the Perch feedback endpoint when live, else a QR code that opens a pre-filled GitHub issue, else a user-set webhook URL); What's new screen on first launch of a new version.
- **WP-20 Minimal Admin.** Requests (stuck, Try again), Plex health, module status badges, playback log, Refresh libraries, the optional 15-minute refresh safety net (off by default), local audit log, third-party notices. Admin requires the parent role and the Admin PIN.
- **WP-21 Hardening.** Playback failure flow ("Couldn't play this", Try again for parents), server unreachable and plex.tv unreachable states, VoiceOver labels on every control, Reduce Motion honoured, performance pass on focus and scrolling.

**Acceptance (the MVP bar)**
- The previous player is deleted from the living-room Apple TV for seven consecutive nights; the playback log shows at least one session each night and no failure entries, and Robin records in the PR that the family did not ask for the old player back or restart the app to fix playback.
- A request made from the TV shows "Getting it ready" and then "Ready to watch" with NEW on Home with no manual steps, while Perch makes no Plex scan calls (verified in the Plex log).
- Kids' profile cannot leave without an adult's Plex PIN, sees nothing above its ceiling in any row or search (checked against five known 15 and 18 titles), and cannot open Admin; Top Shelf shows nothing above the household's lowest ceiling.
- The guide runs end to end after a fresh setup; a feedback report produces a scannable QR that opens a pre-filled issue.

## 1.1.0 Discovery and Trakt

- **WP-22 Discovery rows and full Requests tab.** New on Netflix / Apple TV+ / Disney+ / BBC (GB, deduplicated against the library), Coming this week (from Seerr), Requests tab expanded to Mine / Family / Ready / Waiting with filters.
- **WP-23 Trakt.** Device OAuth (code on TV, activate on phone), scrobbling from the timeline, watchlist and history sync per profile, wizard step.

**Acceptance**
- A title requested from a New on row lands and shows NEW with no manual steps.
- A kid's request appears in the parent's queue; approving it from the Requests tab moves the kid's title page to "Getting it ready".
- Watching an episode scrobbles to Trakt within a minute of finishing.

## 1.2.0 Recommendations, people, seasonal, polish

- **WP-24 Because you watched and end-of-film picks.** Per-profile history to TMDB similar via Seerr, merged and ranked; credits-marker end state with three picks.
- **WP-25 Person pages.** Top rated, For you, In your library, Filmography; People in search.
- **WP-26 Seasonal rows.** Calendar-driven rows and a subtle hero treatment; kid-safe variants; date override in Admin.
- **WP-27 Library polish.** Custom collections, row order and visibility per profile, poster badges (4K, DV, HDR10+, Atmos), theme music on by default for non-kid profiles, Browse by network (off by default).
- **WP-28 Remote shortcuts and artwork overrides.** Long-press context menu (request for, mark watched, add to collection, who's in this); Admin artwork overrides from TMDB, fanart.tv or a pasted URL.

**Acceptance**
- Person page from a cast circle in one click; all four rows populate for a well-known actor.
- With the date override at 30 October then 2 November, the seasonal row switches from Halloween to Bonfire Night.
- End-of-film picks appear at the credits marker; Back restores the credits.

## 1.3.0 House and Music

- **WP-29 PerchHome connection.** Home Assistant URL and long-lived token, WebSocket subscription, wizard step that imports only chosen Areas, cameras, the doorbell entity and scenes; role allow-list enforced on the device.
- **WP-30 Doorbell and alerts.** Doorbell overlay (snapshot first, go2rtc live stream when open, Unlock for parents with the Admin PIN entered in the last 5 minutes, Dismiss), two alert levels, do not disturb per playback. Frigate events via Home Assistant; Frigate URL only for streams and snapshots.
- **WP-31 Lighting and scenes.** Playback-driven lighting per room, Movie night scene, quick controls (long-press Play/Pause while browsing; Lights action in the player's info panel).
- **WP-32 House tab.** Cameras grid, today's events timeline, rooms, scenes. Sidebar gains House.
- **WP-33 Weather and notifications.** Weather-aware seasonal variants; phone notification when a request lands (opt-in, via Home Assistant).
- **WP-34 Apple Music.** MusicKit library, playlists, search, now playing, AirPlay; Music Assistant or Home Assistant media players as optional targets when present. Sidebar gains Music.
- **WP-35 Per-title memory and Single App Mode note.** Remembered audio and subtitle tracks per title; `docs/howto/single-app-mode.md` (tested only if Robin approves supervising a device).

**Acceptance**
- Doorbell press shows the overlay with a snapshot within 2 s and live video within 6 s during a film; Dismiss resumes it.
- Kids' profile sees the overlay with no Unlock; a forged unlock action under a kid role is refused by `PerchCore` (test exists).
- Lights dim on play and fade up at the credits in the theatre room only.
- An Apple Music playlist plays with artwork and controls.

## 2.0.0 Second player engine

- **WP-36 VLCKit engine.** TVVLCKit behind the same player API and chrome; automatic selection from the decision table (MKV with DTS or TrueHD, image subtitles); manual override per title; audio offset remembered per title; night mode (DRC); subtitle styling parity. Licences recorded in `THIRD_PARTY_NOTICES.md`.
- **WP-37 Dolby Vision profile 7 to 8.1.** On-the-fly conversion following Dusk's approach so Blu-ray remuxes keep DV.

**Acceptance**
- The PGS and DTS fixture files play without server transcoding.
- An audio offset of +150 ms set during playback persists for that title.
- Dolby Vision titles still use the native engine by default; a DV profile 7 remux plays as DV.

## 2.1.0 AI

- **WP-38 PerchAI provider layer.** `AIProvider` with OpenAI-compatible and Anthropic adapters, model as free text with free and cheap suggestions first, Test connection, keys in Keychain, monthly budget, per-profile limits, per-feature toggles, AI permission levels per profile (Recommend only / Can request / Can navigate / Home actions), call log, wizard step, parent-only with a teen toggle.
- **WP-39 Ask.** Dictation into the Ask field, structured-query prompt (genres, decades, mood, people, runtime), personalised ranking from the profile's history, watchlist, ratings and time of day, media-only guardrails, structured output only, "I can only help with what to watch" for anything else.
- **WP-40 Daily batch features.** For you tonight, weekly digest row, auto-collections, seasonal blurbs, Who's who guides; cached per profile per day.
- **WP-41 On-demand features and guide Q&A.** Who's that? (subtitles trimmed to the last few minutes), Is this OK for the kids?, Previously on, Movie night picker, Smart requests; the welcome guide gains an optional "ask Pip" question box when AI is configured.

**Acceptance**
- "Find me something funny from the 60s" by dictation returns at least five comedies from the 1960s in under 4 s, split into library and request rows, ranked differently for two profiles with different histories.
- The same query works against two providers by changing only settings; keys are redacted after saving and absent from a config export.
- A kid-role session has no Ask; a teen session with AI enabled gets rating-limited results and no home actions; a Recommend-only profile cannot trigger a request through Ask (tests exist).
- An exhausted budget shows "Ask is taking a break until next month", not an error.

## 2.2.0 Insights and full Admin

- **WP-42 Tautulli.** URL and API key, wizard step, year in review (animated), monthly recap row, fun stats on title and person pages, rewatch rows.
- **WP-43 Full Admin.** Diagnostics export (QR or webhook), AI spend and call log, audit log, module health, server stats.

**Acceptance**
- Year in review plays end to end for each profile with totals matching Tautulli.
- Admin unreachable from any non-parent profile.

## 2.3.0 House extended

- **WP-44 Household touches.** Bedtime prompt for kids' profiles, messages to the TV from phones, ambient screensaver (what's new, weather, calendar, now playing).
- **WP-45 Voice home control and extras.** Home actions through Ask for profiles at permission level 4, Frigate GenAI summaries in doorbell alerts, receiver lip-sync in quick controls.

**Acceptance**
- Bedtime overlay fires at the configured time on the kids' profile and pauses playback.
- Screensaver appears after the idle timeout inside the app and exits on any remote input.

## Later (unscheduled)

- **Perch website and feedback endpoint** (separate repo `perch-site`): home page, setup guide, FAQ, release notes; one POST endpoint that stores feedback, forwards to GitHub issues or Discord, returns a reference. The app falls back to the QR route without it.
- iCloud sync of settings without keys; multi-device households.
- Optional Sonarr/Radarr module for repair and progress.
- Public release, only if decided later: "Perch for Plex" naming, trademark check, HTTPS guidance instead of arbitrary loads, App Store assets, App Review.

## Patch policy

- Fixes to playback, focus or Back ship as patches within days.
- Copy and artwork tweaks are patches.
- A TestFlight rebuild to beat the 90-day expiry needs only a new build number.
