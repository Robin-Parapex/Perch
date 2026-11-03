# WP-06 plan: PerchPlex library

## Context

WP-06 (ROADMAP.md:58) is the data layer for 0.2.0 "First playback": library sections, hubs, Continue watching, Recently added, metadata with markers, chapters and extras, timeline reporting and watched state. It has no screens of its own. WP-07 (player), WP-08 (artwork) and WP-09 (basic Home, "renders from cache with no spinner", ROADMAP.md:66) consume it. WP-10, WP-11, WP-17, WP-18 and WP-23 build on it later.

Today PerchPlex has only a section count and backdrop art (`PlexSession.librarySummary`, `libraryArt`, `PlexEndpoints.recentlyAdded`). There are no section, item, hub or metadata models. `PlexSession` (an actor) is the only token holder, and `serverContext()` is private. Tests fake HTTP through `PlexTransport` (`Tests/PerchPlexTests/Support/FakeTransport.swift`, `RoutedTransport.swift`, `SessionRig.swift`). Baseline: PerchCore 174 tests, PerchPlex 129.

References read (approach only, nothing pasted): Dusk at 759a5aa (MIT) for Plex endpoints, lenient decoding, timeline and scrobble; Swiftfin at 491b68b (MPL-2.0) for paging and optimistic watched state. Each borrowed idea gets a one-line comment naming its source. THIRD_PARTY_NOTICES.md gets "ideas only, WP-06" lines.

**Status:** plan only, amended after an Opus critic pass. Branch `wp-06-plex-library` is cut from the local `wp-05-setup-wizard` tip (c0f17aa). WP-04 and WP-05 are unpushed; WP-06 stacks on them.

## Decisions (recorded in DECISIONS.md)

1. **Shape.** A new `PlexLibrary` actor in `PerchPlex/Library/`, owned next to `PlexSession`.
   - It gets a `PlexServerContext` (base URL, server token, profile ID, machine ID, generation) from a new internal `PlexSession.libraryContext()`. The token never leaves PerchPlex.
   - `PlexSession` bumps `generation` inside `setState` whenever the profile, machine ID or base URL changes, or the state leaves `.ready`. That covers activate, switch, `resume()` and sign-out.
   - `PlexLibrary` drops any response with a stale generation, so a switch mid-request can never show one profile's rows to another. Switching still goes only through `PlexSession.switchProfile` (DECISIONS.md:292).
2. **Wire models stay internal; neutral types go in PerchCore.**
   - Plex JSON decodes into internal `PlexWire*` envelopes. Every field is optional, and `librarySectionID`, `extraType` and `index` accept either an int or a string (a Dusk quirk).
   - A stream, marker or chapter that fails to decode is dropped, not the whole item.
   - Public results are neutral PerchCore types: `MediaSummary`, `MediaRow`, `MediaDetail` (with `MediaMarker`, `MediaChapter`, `MediaExtra`, and `MediaVersion` for part and stream attributes) and `PlaybackProgress`.
   - Reason: PerchCore owns models (MODULES.md:31-40), so Home, the player and later modules need nothing Plex-shaped.
3. **Extension points fixed here** (Module.swift:22: the first user fixes the shape).
   - **`RowProvider`:**
     - `func cachedRow(in: RowContext) -> MediaRow?` is synchronous and reads a snapshot store that is nonisolated and guarded by a `Mutex`.
     - `func refreshRow(in: RowContext) async throws -> MediaRow`.
     - `RowContext` carries the profile ID, the effective ceiling and an optional subject (rating key), which covers Home, title-page and person-page placements.
     - PerchCore provides one `RowContext.admit(_:)` filter, applied by the registry to every provider's row, so modules never filter separately.
     - `PlexModule.contributions()` returns three Home rows: Continue watching, Up next in your series, Recently added.
   - **`PlaybackReporting`** (a new PerchCore protocol): `sessionID`, `report(state:positionMs:)`, `stop(positionMs:)`. PerchPlayer (WP-07) depends on PerchCore only (MODULES.md:60), so it reports through this protocol.
   - **Left for WP-07:** the playable source (direct-play URL plus token handling, where INTEGRATIONS.md:10 and DECISIONS.md:320 conflict) and `PlayerHook`. A PerchApp coordinator bridges PerchPlex to PerchPlayer.
4. **Endpoints.** These settle the "to be confirmed" note at INTEGRATIONS.md:3. JSON only, the token in a header, paging via `X-Plex-Container-Start/Size` query items. V4 checks every path on the live server and corrects them before merge.
   - **Sections:**
     - `GET /library/sections`, video sections only (movie, show). "Other videos" is identified by `subtype=clip` or the Plex Video Files scanner or agent (Dusk).
     - Items come from `/library/sections/{id}/all` with a single `sort` parameter. Paging is 50 items, then 100. The next offset comes from the server's row count, and paging stops on an empty page.
     - Counts use `Size=1` and read `totalSize`. Watch-state filters and the full sort and filter set stay with WP-10.
   - **Continue watching and Up next:**
     - One call to `GET /hubs/continueWatching?includeGuids=1`. If the server returns a hub `key` instead of items, its items path is followed (possibly `/hubs/continueWatching/items`; V4 confirms).
     - Items with `viewOffset > 0` go to Continue watching. Episodes with no offset go to Up next.
     - If Up next comes back empty, fall back to `GET /library/onDeck` for episodes with no offset.
     - A series appears in one row only (deduped by `grandparentRatingKey`); Continue watching wins.
   - **Recently added:**
     - `GET /hubs?count=20&includeGuids=1`, keeping hubs whose type is movie, show, season or episode and whose identifier contains `recent`. Music, photo and playlist hubs are dropped. Film and series hubs are merged by `addedAt`.
     - Fallback is `/library/recentlyAdded`, already used in WP-05. The full hub list is kept for later WPs.
   - **Metadata:**
     - `GET /library/metadata/{rk}?includeMarkers=1&includeChapters=1&includeExtras=1&includeGuids=1`.
     - `checkFiles=1` is sent only by a separate `metadataForPlayback(rk)`, which WP-07 calls just before play.
     - Extras fall back to `/library/metadata/{rk}/extras` when they are not inline. Trailers and clips are kept.
   - **Children:** `/children` for seasons and episodes, and `/allLeaves`. The next episode is found by index and never steps back into season 0 (Dusk).
   - **Markers and chapters:**
     - Markers are intro and credits, with `final` decoded when present. Neither reference reads it, so V4 confirms it.
     - Chapters carry index, title, start, end and a thumb path. WP-07 uses them for the player's chapter list. All times are in milliseconds.
   - **Media, Part and Stream:** they carry what the decision table needs (ARCHITECTURE.md:47-62): container, video and audio codec, DOVI profile, bit depth, colour transfer, frame rate, channels, subtitle codec and format, part key, duration and size.
5. **Timeline reporting.** `PlexLibrary.startPlayback(item:sessionID:)` returns a `PlexPlaybackReporter` actor that conforms to `PlaybackReporting`.
   - It captures the context at start. The session ID comes from the caller, so WP-07 can share it with any transcode session, or is a fresh UUID.
   - It sends `GET /:/timeline` with `ratingKey`, `key`, `state` (playing, paused, buffering, stopped), `time` and `duration` in ms, and `X-Plex-Session-Identifier`.
   - It sends every 10 s (INTEGRATIONS.md:11) and on every state change.
   - Seeking back is reported as is. Buffering repeats the last known time.
   - One request is in flight at a time, and the newest pending report replaces older ones. Sends go out in strict order.
   - `stop()` cancels the queue and sends `stopped`.
   - If the generation changes (profile switch or sign-out), the reporter goes inert and sends nothing more.
   - The clock is injected for tests. WP-07 drives the reporter; WP-23 (Trakt) listens later through `PlayerHook`.
6. **Watched state.**
   - `markWatched` and `markUnwatched` call `/:/scrobble` and `/:/unscrobble` (`identifier=com.plexapp.plugins.library`).
   - At `stop()`, if the position is at least 90% of a sane duration, the reporter also scrobbles. This is idempotent with Plex's own threshold.
   - Updates are optimistic in the in-memory rows, then a refresh reconciles. Each item carries a revision, so a late read cannot undo a newer toggle (Swiftfin).
   - Reporter progress also updates Continue watching in memory, so Home is correct the moment the player closes.
   - Watch-state changes go through a small internal `PlexWatchStateSink` protocol so the reporter and `PlexLibrary` stay decoupled.
7. **Permissions, no change to the model.**
   - Timeline, mark watched and mark unwatched are checked as the existing `CoreAction.play` through `Authoriser`: yes for parent, teen and kid, no for topShelf.
   - Watch state is per Plex user, so a kid marking a title affects only their own profile.
   - No matrix row is added. Robin confirms this below.
8. **Cache so Home never shows a spinner.**
   - **In memory:** the last good rows, keyed by profile ID and machine ID. A failed refresh keeps them and sets the module status to degraded.
   - **On disk:** a small JSON snapshot of the three Home rows for each profile and server.
     - Light fields only: rating key, type, titles, season and episode index, art paths, offset, duration, certificate, added date.
     - Capped at 40 items per row, about 64 KB, in the App Group Caches directory. It is purgeable and outside the 500 KB persistent budget (DECISIONS.md:151).
     - It is read synchronously at launch, passed through `RowContext.admit` on every read (so a ceiling lowered since it was written still applies), and rewritten after each good refresh.
   - Sign-out deletes all snapshots. A profile only ever reads its own file, and Top Shelf (WP-17) never reads these files.
9. **Rating ceiling: carry now, filter only Perch's own override.**
   - Plex already filters managed users' libraries (PERMISSIONS.md:25). WP-06 carries each item's certificate, and `admit` drops an item only when the profile's Perch ceiling is below the Plex restriction, which happens when an Admin has lowered it.
   - `RatingCeiling(certificate:)` learns the US TV ratings so episodes are not counted as 15:
     - TV-Y, TV-Y7 and TV-G become U.
     - TV-PG becomes PG.
     - TV-14 becomes 15, rounded up to fail closed.
     - TV-MA becomes 18.
     - NR and unknown stay 15.
   - Ceilings across all rows and search remain WP-18.
10. **Durations.** Remaining time and progress use the part duration, then the item duration. If either is missing or shorter than the offset (the debrid quirk, INTEGRATIONS.md:14), remaining is nil and WP-09 shows no "min left".
11. **Fake household.** The DEBUG `-PerchFakeHousehold` canned transport gains library fixtures: sections, continueWatching, hubs, an episode with intro and credits markers, chapters and a trailer. WP-07 and WP-09 can then build and UI-test without Plex.
12. **Library check (DEBUG only).**
    - A "Library check" button on the existing placeholder screen. It lists sections, the three rows' counts and first titles, and, for the first Continue watching item, its markers, chapter count, extras and media summary.
    - It is read-only. It is how WP-06 is shown against a real server before Home exists, and it is removed when WP-09 lands.

## Slices (helpers, one owner per file)

1. **Lead: PerchCore types and extension points.**
   - Files: `PerchCore/Media/MediaModels.swift`, `PerchCore/Media/RowContext.swift`, `PerchCore/Media/PlaybackReporting.swift`, `Modules/Module.swift` (RowProvider only), `Modules/ModuleRegistry.swift` (admit on rows), and the `Ratings/RatingCeiling.swift` TV mapping.
   - Tests: `PerchCoreTests/MediaModelsTests.swift`, `RatingCeilingTests` additions.
2. **builder A: wire models, endpoints, shared types, fixtures, test support.**
   - Files: `Library/PlexLibraryWire.swift`, `Library/PlexLibraryEndpoints.swift` (an extension, so `PlexEndpoints.swift` stays untouched), `Library/PlexLibraryMapping.swift`, and `Library/PlexServerContext.swift` (with the `PlexWatchStateSink` protocol).
   - Fixtures go under `Tests/PerchPlexTests/Fixtures/library/`. A owns any changes to `FakeTransport`, `RoutedTransport` and `SessionRig`, and they are frozen after A. B and C add only new support files.
   - Tests: decode tests.
3. **builder B: the `PlexLibrary` actor.** Depends on 1 and 2.
   - Files: `Library/PlexLibrary.swift`, `Library/PlexHomeSnapshotStore.swift`, `Library/PlexSectionPager.swift`, plus the `libraryContext()` and generation edits in `Auth/PlexSession.swift`.
   - **tester** alongside: stale generation dropped on switch and `resume()`, one snapshot per profile, sign-out wipe, re-filter on read, continueWatching split, dedupe and onDeck fallback, hub type filter, pager stops.
4. **builder C: reporter and watched state.** Depends on 2, and runs in parallel with B.
   - Files: `Library/PlexPlaybackReporter.swift`, `Library/PlexWatchState.swift`.
   - **tester** alongside, with an injected clock: 10 s cadence, send on change, seek back reported, buffering holds time, coalescing and order, stopped flush, inert after generation change, 90% scrobble, revision guard, topShelf denied.
5. **builder D: app and module wiring.** Depends on 3 and 4.
   - Files: `PlexModule.swift` (row contributions), `PerchApp/CoreServices.swift`, the DEBUG fake-household fixtures, the DEBUG Library check view, and one UI test in `PerchUITests` that opens Library check on the fake household and asserts the counts.
6. **Wrap-up:**
   - **verifier:** `scripts/gate.sh`.
   - **reviewer (Opus), once** on the whole WP diff: token confinement, generation and concurrency, permission checks, snapshot isolation between profiles.
   - **scribe:** CHANGELOG (Unreleased, "WP-06 PerchPlex: ..."), DECISIONS.md items 1 to 12, THIRD_PARTY_NOTICES.md, and the report `docs/notes/wp-06-report.md`.

At most three helpers run at once.

## Verification

- **V1 Gate:**
  - `scripts/gate.sh` passes on simulator 11ACEAE4. UI tests never run on C6E85DCA.
  - No new warnings.
  - PerchCore and PerchPlex test counts rise above 174 and 129.
- **V2 Unit acceptance,** all against fixtures and fakes:
  - sections and paging
  - the three rows built, deduped and admitted
  - metadata with markers (intro, credits, `final`), chapters, extras and the decision-table stream fields
  - timeline cadence, ordering and inert-after-switch
  - scrobble and unscrobble
  - a snapshot read that touches no transport, so the test fails on any network call
- **V3 Fake household:** the new UI test in the gate (V1) shows correct Library check counts with `-PerchFakeHousehold` on 11ACEAE4.
- **V4 Live read-only check (needs your word, and your hands for the kid's PIN):**
  - A signed debug build runs on simulator C6E85DCA, where your live sign-in is. Manual run only, no UI tests.
  - Library check against the real server:
    - rows match what Plex Web shows for that profile
    - one episode shows its intro and credits markers
    - the continueWatching path, the hub identifiers and the `final` flag are confirmed
  - Raw responses are saved to the session scratchpad, never the repo, so the fixtures can be corrected and anonymised.
  - Switch to the kid's profile: its rows change, show no adult titles, and are not empty.
- **V5 Live timeline and scrobble (only with your word):**
  - From Library check, a DEBUG "simulate 30 s of playback" runs on one title you name, then mark watched, then mark unwatched.
  - The original offset is then restored with `/:/progress`.
  - Seen in Plex Web's dashboard.
  - If you say no, this is skipped and reported as unit-tested only.
- No Apple TV install (simulator only since 2 Nov 2026).

## For Robin

**Answers (Robin, 3 Nov 2026, via the WP-05 lead):** V4 yes; V5 yes (Robin names the title when asked); all profiles, kids included, may mark their own titles watched or unwatched: yes. TV rating mapping: not yet answered, built as decision 9 unless he says otherwise.

1. **V4:** may a debug build make read-only library calls to your real Plex server on the live simulator? You would enter the kid's PIN for the switch check.
2. **V5:** may it send timeline, scrobble and progress calls for one test title you choose, with watch state restored afterwards? If not, timeline and watched state are proven by unit tests only until WP-07.
3. **Kids and watched state:** all profiles may mark their own titles watched or unwatched, under the existing play permission. Is that right?
4. **TV ratings:** the US TV ratings map onto UK ceilings as in decision 9 (TV-14 rounds up to 15). Is that right?
5. **Scope:** Up next data comes into WP-06 because WP-09 needs it. Sort and filter beyond paging stays in WP-10, and full ceilings stay in WP-18.
6. **Stacked unpushed work:** WP-04, WP-05 and now WP-06 are local only. Nothing here needs a push.
