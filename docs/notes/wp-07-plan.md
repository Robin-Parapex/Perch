# WP-07 plan: PerchPlayer, then the rest of 0.2.0 First playback

## Context

WP-01 to WP-06 are merged; the lowest unmerged WP is **WP-07 PerchPlayer**, first of stage **0.2.0 First playback** (WP-07 player, WP-08 artwork, WP-09 Home). WP-06 left the playback groundwork in PerchPlex (metadata with markers, `detailForPlayback`, `nextEpisode(after:)`, `PlexPlaybackReporter` timeline every 10 s, scrobble at 90%, watched state, Home row providers with a per-profile snapshot cache). PerchPlayer is still a stub, there is no Home UI and no Play action anywhere, and no playable URL is built yet.

**Status:** plan, approved by Robin on 4 Nov 2026 ("proceed"). Branch `wp-07-player`.

## Assumptions (taken as defaults because the questions were skipped)

- **Scope:** plan and build WP-07 now; WP-08 and WP-09 are outlined below and each gets its own plan, branch and PR after the previous merges. Stop after each PR.
- **Test media (Robin, 3 Nov):** as little server work as possible.
  - `scripts/make-fixtures.sh` writes every clip into **one folder**, `build/fixtures/Perch Fixtures/`: about 12 clips of 30 s each, about 1 GB in total. That includes one 4K sample at 80 Mbit/s, which can be left out if space matters.
  - Clip names are self-describing (`01 MP4 H264 AAC.mp4`, `07 MKV HEVC DV7 TrueHD.mkv`, ...).
  - Robin uploads the folder to the NAS and adds it in Plex as an **"Other Videos" library**. That library type plays files as they are, with no title matching or posters, so the clips show up by file name.
  - `docs/howto/fixtures-library.md` gives the steps in five lines.
  - Until the library exists, the decision table is proven by unit tests on Plex metadata fixtures, and the simulator plays the bundled debug clip. The live matrix is the only part waiting on the upload.
  - If ffmpeg is not installed, ask before installing it.
- **Device:** stay simulator-only. Display-mode matching and the dropped-frames check are listed in the PR as not checked on the device.
- **Behaviour defaults until WP-18 adds per-profile settings** (recorded in DECISIONS.md): resume plays from the saved position automatically; auto-skip off, Skip pill shown for 6 s; autoplay next episode on, 10 s countdown; "Are you still watching?" before a 4th consecutive autoplay with no remote input since the 1st; no credits marker means the countdown starts 30 s before the end (Dusk's estimated-credits fallback); subtitles off unless a forced stream exists; image subtitles never chosen automatically.
- **Token:** stays out of URLs. Sent as headers through `AVURLAssetHTTPHeaderFieldsKey`; the spike confirms that HLS segment requests carry it. If they don't, the fallback is an `AVAssetResourceLoaderDelegate`, never the token in a logged URL.

## WP-07 design (branch `wp-07-player`)

**PerchCore** (neutral types, no AVKit)
- `PlaybackDecision`: method (directPlay / directStream / audioTranscode / transcode), reasons, video range (SDR / HDR10 / HDR10+ / DV), frame rate, notes ("Atmos lost", "DV7 as HDR10").
- `PlaybackSource`: URL, headers (redacted in `description`), decision, start position, session ID.
- Fix the `PlayerHook` shape (`Modules/Module.swift:62`): event, ratingKey, position.
- `PlaybackLog` actor: JSON lines in App Group Caches, capped (about 500 entries, under 200 KB) to respect the 500 KB persistence rule. Each entry: time, profile ID, ratingKey, title, decision with reasons, engine "native", outcome (start / stop / failure plus error), start latency.

**PerchPlex**
- Decode the stream fields the table needs (`PlexLibraryWire.swift:366-416`): video profile, DOVI present / profile / BL-compat, colour primaries, audio profile, channels.
- `PlexPlaybackDecider`: a pure function implementing `ARCHITECTURE.md:47-62` (first matching row per dimension, 4K never downscaled for subtitles).
- `PlexLibrary.playbackSource(for:startMs:subtitle:)`: authorises `.play`, calls `detailForPlayback`, decides, then builds the direct-play part URL or the `/video/:/transcode/universal/start.m3u8` URL. The session ID is shared with `startPlayback(item:sessionID:)` (`PlexLibrary.swift:495`).

**PerchPlayer** (UIKit where tvOS needs it)
- `PlayerContainerViewController`: embeds `AVPlayerViewController` as a child, not modal.
- `PlaybackSession` (`@MainActor`, observable): AVPlayer lifecycle, resume seek, periodic time to the reporter, marker state (intro / credits), end of item, autoplay counter for "still watching", stall and failure handling.
- `DisplayCriteriaMatcher`: `appliesPreferredDisplayCriteriaAutomatically = false`, sets `AVDisplayManager.preferredDisplayCriteria` from the asset before play, and clears it on exit.
- `OverlayWindowHost`: a `UIWindow` one level above normal, hosting SwiftUI. It becomes key only while an overlay needs focus and hands key back to the player window afterwards. This resolves the `.fullScreenCover` limits in `DECISIONS.md:192-197`.
- Overlays, reusing PerchDesign visuals (`PerchCornerPill`, `Pill`, button styles):
  - Skip Intro / Skip Credits pill.
  - Next-episode countdown: video shrinks to 640x360 top-right over 0.5 s, "Next episode in 10", Back cancels.
  - "Are you still watching?" sheet.
  - "Couldn't play this", with Back.
  - Skip also as a custom info-panel action.
  - Reduce Motion variant for each.

**PerchApp**
- `PlaybackCoordinator`: bridges PerchPlex to PerchPlayer, writes the playback log, and fans `PlayerHook` events out to registered hooks. The player sits above the current screen in the root, so Back returns to the exact item.
- Entry points until WP-09: Play buttons in the DEBUG Library check view, plus a `-PerchPlayItem <ratingKey>` launch argument.
- The fake household gets a DEBUG-only bundled clip of about 1 MB, excluded from Release, with intro and credits markers at known times so UI tests can play it offline.

**Tests**
- Unit tests:
  - the decision table, with every row and the key combinations (MKV + SRT, DV7, 4K + PGS, TrueHD);
  - no token in any built URL;
  - log cap and redaction;
  - the countdown and still-watching state machines;
  - marker skip windows.
- UI tests on the 3rd-gen simulator (`scripts/gate.sh`):
  - play the fake clip, the Skip pill appears and skips;
  - credits lead to the countdown, and Back cancels it;
  - Back from the player restores focus on the item.

## Catching stuck helpers early (Robin, 3 Nov: Sonnet got stuck earlier)

- Every Sonnet brief has a hard budget, about 25 tool calls or 2 build attempts. If the same build or test error appears twice, the helper must stop and report `blocked`, with the error excerpt.
- Helpers run in the background; check each one when it reports and do not wait on long silent runs. A `blocked` or `failed` report, or a budget overrun, goes straight to **solver (Opus)** with the evidence. No second Sonnet attempt at the same problem.
- The hard parts start on Opus. The overlay window and focus spike, the HLS header auth and the overlay slice (C) go to solver. Sonnet builders get only fully specified slices (A, the fixtures script, tests).
- Swift 6 concurrency errors and xcodebuild or simulator flakiness are the usual traps, so briefs name the exact gate command, the simulator ID and "never use the other Apple TV simulator".

## Decisions after the reference read (3 Nov)

- Dusk and Swiftfin both drop AVPlayerViewController for a bare `AVPlayerLayer` and a custom HUD. **We keep AVPlayerViewController** (non-negotiable 1, `DECISIONS.md:17-19,47-48`), which gives us the native AVKit pieces they lost:
  - **Skip Intro / Skip Credits** use `contextualActions`, Apple's own bottom-right button. This replaces the custom pill.
  - **Next-episode countdown** uses `AVContentProposal` with an `AVContentProposalViewController`, with `preferredPlayerViewFrame` at 640x360 top-right, so the video shrinks natively.
  - **The overlay window** is kept for "Are you still watching?", "Couldn't play this" and, later, the doorbell and notices.
- **Estimated credits:** Dusk's rule, start = duration - clamp(4%, 45 s, 120 s). An estimated start gives a manual proposal only: no autoplay and no auto-skip. One auto-skip per marker per session.
- **Still watching:** Dusk's pass-out rule, default 3 auto-chained episodes, reset by any remote input.
- **Display criteria:** applied before the item loads, from Plex metadata (`AVDisplayCriteria(refreshRate:formatDescription:)` built from the colour tags, as Dusk does). Skipped when matching is off. Reset to nil at teardown.
- **Resume:** wait for `readyToPlay`, seek with zero tolerance, then play. `preferredForwardBufferDuration` 20 s.
- **Transcode:** call `/decision` before `start.m3u8`, and `/transcode/universal/stop` at teardown. Query items follow Dusk; the token goes in a header (pending the spike).
- **Teardown hygiene:** generation counter for stale async work, observers removed explicitly (Swiftfin, Dusk).

## How the work runs (helpers)

1. **scout:** shallow-clone Dusk and Swiftfin at their pinned SHAs into scratch, and digest their player presentation, skip and credits, `MediaSegmentObserver`, display criteria and timeline code. Approach only; borrowed ideas get a source comment.
2. **solver spike** (riskiest first):
   - Does focus move correctly between the player window and a key overlay window on tvOS?
   - Does header auth reach the HLS segments from Plex's transcoder?
   - Run against the live server in the simulator; findings go into the design before building.
3. Build slices, one owner per file:
   - A, **builder (Sonnet)**: PerchCore types plus the PerchPlex decider and source;
   - B, **builder (Sonnet)**, using the spike's container code: PerchPlayer container, session and display matcher;
   - C, **solver (Opus)**: overlay window and overlays.
   - The lead writes the coordinator and integration.
   - **tester** writes the decision-table and state-machine tests alongside.
4. **builder:** the fixtures script. Robin creates the library.
5. **verifier:** `scripts/gate.sh` green; then a live simulator run over the fixtures library, collecting the logged decisions and resume timings.
6. **critic:** simulator screenshots of the overlays against Apple TV app and Netflix references, per the visual bar.
7. **reviewer:** one pass on the whole diff (playback, auth headers, concurrency).
8. **scribe:** CHANGELOG Unreleased, DECISIONS (token transport, playback log format, behaviour defaults, PlayerHook shape), `docs/notes/wp-07-plan.md` and `wp-07-report.md`.
9. Then `/pr open`, ready, and stop for Robin's merge.

## Acceptance for WP-07 and how each is shown

- Each fixture's logged decision matches the table: unit tests plus a table of live decisions in the PR.
- Resume within 2 s: start latency from the playback log in the simulator against the live server.
- Skip, countdown, still watching, failure, Back: UI tests plus simulator screenshots.
- `preferredDisplayCriteria` and no dropped frames on the 80 Mbit/s 4K sample: device only, so listed as not checked on the device.

## Robin's steps

- Upload the `Perch Fixtures` folder to the NAS and add it as an "Other Videos" library (optional for the PR; only the live decision table waits on it).
- Approve installing ffmpeg if it is missing.
- Merge the PR.

## Rest of 0.2.0 (each planned in full when it starts)

- **WP-08 Artwork pipeline:**
  - Nuke in the app target only; PerchDesign stays agnostic (`DECISIONS.md:173`). The version is pinned in DECISIONS and `Package.resolved` is committed.
  - Pipelines split thumbs and backdrops (Swiftfin), with a 7-day disk cache.
  - Prefetch the next row plus the focused backdrop and logo.
  - Blurred low-res Plex transcode as the placeholder, never grey.
  - 10% tint from the focused backdrop.
  - Add the `clearLogo` field.
  - Move the `ImageDiskCache` users over.
- **WP-09 Basic Home:**
  - Reference screenshots first (Apple TV app, Infuse, Dusk).
  - Hero at 80% height with logo and text fallback.
  - Continue watching, Up next and Recently added from `ModuleRegistry.cachedRow` then `refreshRow`, with no spinner.
  - Play from Continue watching in 2 clicks via `PlaybackCoordinator`.
  - Staged entrances and fades with Reduce Motion variants.
  - Remove the DEBUG Library check (`DECISIONS.md:377`).
  - Critic pass on screenshots.
- **Stage acceptance:**
  - Home renders from cache on second launch.
  - Warm launch to Home under 1.5 s, measured in the simulator.
- No version tag or TestFlight at the end of 0.2.0 (releases deferred).
