# WP-06 Plex library and Home rows: report

3 Nov 2026. Branch `wp-06-plex-library`, cut from `wp-05-setup-wizard` at 768a2ed and worked in the git worktree `Perch/.claude/worktrees/wp-06`, so the shared checkout stayed on WP-05. Pushed on Robin's "Yes, push" as a draft PR stacked on Robin-Parapex/Perch#7 (WP-05): merge #7 first, preferably with a merge commit, so this branch does not conflict.

## What was built
Per the approved plan, `docs/notes/wp-06-plan.md`.
- **PerchCore:** media types, RowContext with one ceiling filter in the registry, PlaybackReporting, the RowProvider shape, US TV ratings.
- **PerchPlex:** wire models, endpoints, mapping and the PlexLibrary actor.
  - Sections, pager, Home rows (Continue watching, Up next, Recently added), hubs, detail, children, next episode, watched toggles, playback start.
  - Per-profile Home snapshot store, timeline reporter, watch state, session generation.
- **App:** PlexModule row providers, CoreServices wiring, fake household library, DEBUG Library check (opt-in write check, response dump, `-PerchLibraryCheckItem <rating key>`), one UI test.

## How it was checked
- **Helpers:** Sonnet scouts, Opus critic on the plan, Sonnet builders A to D, Opus reviewer (approve with fixes: 5 should-fix, all fixed with tests), Opus solver for the ServerProbingTests flake, Sonnet builder for the live-shape alignment, Sonnet verifier for the gate, Sonnet scribe for records.
- **Flake:** wall-clock margins in the test were stretched by suite load; no prober bug. Tests are now independent of load; 2 x 20 whole-suite iterations green.
- **Gate:** GATE PASS on 11ACEAE4 at 4595c72. xcodegen no drift; PerchCore 186, PerchDesign 26, PerchPlex 262, other packages pass; UI tests 19 of 19, 0 skipped.
- **After 7754a84:** only the PerchPlex package tests (266, pass) and an app build were re-run, on simulator 5341203D. The full gate was re-run on the final tree before the push; its result is in the PR description.
- **V4 live read-only check** on your live simulator C6E85DCA, signed debug build, setup completed with defaults, you typed your own Plex PIN.
  - Sections 2 (Movies, TV); Continue watching 17; Up next 3; Recently added 40 after the fix (20 before).
  - Hub identifiers: home.continue (mixed), home.ondeck (episode), home.movies.recent (movie), home.television.recent (mixed), home.music.recent, home.photos.recent, home.videos.recent, movie.curated.16.1, home.playlists.
  - Defect fixed: the television recently-added hub is typed "mixed" and was dropped. Hubs are now chosen by identifier and items filtered by kind. `/hubs/continueWatching` returns one Hub with inline Metadata.
  - Film detail showed 20 chapters, an inline trailer extra, h264 1080 video, EAC3 8-channel audio, SRT and PGS subtitles.
  - Raw responses are in the session scratchpad only. Fixtures were rewritten to the real structure with invented values.

Kid-profile switch (V4): switched to Arthur (kid, no PIN asked). The rows changed and hold only children's titles: Continue watching 1, Up next 0, Recently added 36; the adult films in Robin's rows are gone and the rows are not empty. The live simulator was left on Arthur.

## Not verified live
- Intro and credits markers: none came back for one film (Frozen II) and three episodes (Silo, Thomas & Friends, The Kardashians). Checked after Robin said detection is on:
  - Our request is right. `PlexEndpoints.metadata` sends `/library/metadata/{rk}` with `includeMarkers=1`, `includeChapters=1`, `includeExtras=1` and `includeGuids=1`, pinned by `PlexLibraryEndpointTests`. That is the same endpoint and flag Dusk and python-plexapi use.
  - The server honoured the query. The same live responses carry `Extras` for all four titles and 20 `Chapter` entries for Frozen II, so the include flags arrived. No `Marker` key is present at all (it is not an empty array), on any of the four.
  - Decoding is right. `Marker` on the item is decoded (`PlexLibraryWire`), and the fixture test with intro and credits markers passes.
  - So the server holds no markers for these items yet. The likely cause is that the analysis has not run on them: it is a scheduled task, and files on the debrid mount may not have been analysed. Nothing in the app needed changing. The `final` flag is unconfirmed.
- Dolby Vision stream fields: no DV title checked.
- V5 timeline, scrobble and progress on a test title: blocked, not run. Robin allowed the simulator tool, but it cannot drive the tvOS simulator C6E85DCA. Key presses report success yet focus never moves, and tap and swipe time out. No other input route was tried. The app on C6E85DCA was relaunched with `-PerchLibraryWriteCheck -PerchLibraryDump`, is still on Arthur, and no writes were made.

## Needs Robin
1. V5 (optional before merge): on C6E85DCA, switch to your profile, open Library check, pick "The Odyssey", then press Simulate 30 s of playback, Mark watched, Mark unwatched and Restore offset, and check it ends unwatched at no offset. Note its state first: if it was watched, press Mark watched again at the end.
2. Markers: in Plex Web, open one Silo episode and check whether it offers Skip intro. If it does not, run Analyze on that episode or season, then repeat the library check.
3. Merge Robin-Parapex/Perch#7 first, preferably with a merge commit, then review the WP-06 draft PR.

## Known gaps, recorded for later WPs
- **Title logo:** PerchCore has no field for the Plex `Image` clearLogo that the WP-09 hero needs.
- **Recently added:** a new series can appear next to its own season and episodes (not collapsed).
- **Dump folder:** the DEBUG library-dump folder survives sign-out.
- **Library check** is temporary and goes when WP-09 lands.

Decisions are in `docs/DECISIONS.md` (WP-06 sections, your answers dated 3 Nov 2026), including your confirmation that US TV-14 counts as UK 15.
