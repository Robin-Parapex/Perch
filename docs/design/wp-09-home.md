# WP-09 Basic Home: design spec

Status: draft for Robin, 4 Nov 2026. Author: WP-09 lead (Fable). Applies to 0.2.0 only; later rows and the sidebar are named where they change the layout.

This is the screen the TV wakes up to. It must render from the cached snapshot in the first frame, never show a spinner, let the family resume in two clicks or fewer, and look like Apple made it. Numbers below are points on a 1920 x 1080 canvas. Where this spec and `docs/DESIGN.md` differ, this spec is the WP-09 reading of DESIGN and says why.

## 1. References (describe, never copy)

**Apple TV app, tvOS 26 Home.** Full-bleed artwork fills the top of the screen with a soft dark scrim rising from the bottom; the title logo sits bottom-left over it with one line of metadata and a single white pill button. The first row peeks above the fold so the eye knows there is more. Rows are plain: a 28 pt title, then cards with no borders, captions in two muted lines. Focus is the system lift with parallax, a soft long shadow and a slight scale; the rest of the row stays still. Nothing is boxed; the page is one dark surface tinted by the artwork. Scrolling is spring-smooth and snaps to cards. When a row scrolls into view the hero shrinks away rather than fading.

**Infuse (tvOS).** Continue watching uses wide 16:9 stills with a thin progress bar along the bottom edge and "32 min left" under the title. Series episodes show the episode still, not the poster, with "S2 E5" in the caption. Logos replace titles wherever one exists; the text fallback is big, white and left-aligned so it still reads as designed. The background is tinted from the focused artwork and crossfades as focus moves.

**What we take.** Apple's hero composition, scrims, row rhythm and native focus. Infuse's landscape Continue watching cards with progress and time left, episode stills for Up next, and the tinted background. We do not take Infuse's rotating hero carousel or the Apple app's channel rows.

**What Robin rejected in WP-03.** A flat gallery of components, grey gradient placeholders, a boxed hero that did not reach the edges. Every screenshot in the checklist is judged against the two references above, not against this document's numbers.

## 2. What is on screen in 0.2

One vertical scroll (`RowList`): the hero, then up to three rows.

| Order | Row id | Title shown | Card | Shown when |
|---|---|---|---|---|
| hero | derived, see 4 | logo or title text | HeroCard | a hero item exists |
| 1 | `plex.continueWatching` | Continue watching | LandscapeCard 336 x 190 | 1 or more items |
| 2 | `plex.upNext` | Up next in your series | LandscapeCard 336 x 190 | 1 or more items |
| 3 | `plex.recentlyAdded` | Recently added | PosterCard 180 x 270 | 1 or more items |

An empty row is not shown at all (no header, no gap). Rows keep the order above whatever the registry returns; ordering is by `placement.order`, then id, and a unit test pins it.

Not in 0.2: sidebar (WP-13; Home uses the full width and the 80 pt margins, which is where the collapsed sidebar will later sit), More info and Add buttons (WP-11, WP-15), trailer crossfade (1.0), Requested row (1.0), format badges on cards (1.2), row reordering (1.2).

## 3. Layout

### 3.1 Hero (0 to 864 pt)

- **Backdrop.** `artPath` of the hero item (series art for an episode) at `ArtworkSize.backdrop`, scaled to fill 1920 x 1080, anchored to the top centre, clipped to the hero's 864 pt. Ken Burns pans within the extra 216 pt. Until the image lands, `ArtworkPlaceholder` shows the blurred stand-in or the tinted gradient; never a grey box, never a spinner.
- **Scrims** (over the backdrop, under the content). Bottom: linear, base colour `#0b0b0f` at 0% opacity at y 380 to 92% at y 864, continuing to 100% at y 900 so the hero dissolves into the page instead of ending in a line. Left: linear, base colour 55% at x 0 to 0% at x 1000. Both are flat colour gradients on the image, which DESIGN allows; the chrome (buttons) is still Liquid Glass or a white pill.
- **Content block**, left-aligned at x 80, bottom-anchored so its last element ends at y 792 (hero bottom minus 72). From the bottom up:
  1. Actions row, 68 pt tall: one primary white pill, **Play** or **Resume**, icon plus label, 26 pt. One button only in 0.2.
  2. 24 pt gap.
  3. Synopsis, 26 pt, `textBody` (85% white), max 2 lines, 900 pt wide, fixed 2-line height of 68 pt so the block never jumps when the text arrives late (see 8).
  4. 16 pt gap.
  5. Metadata line, 22 pt `textSecondary`, items separated by a middle dot with 12 pt either side: film "2024 · 1 h 52 min · 15"; series "Series · 2024 · 12"; episode "Series title · S2 E5 · 31 min left" (drop "min left" when `remainingMs` is nil). The certificate is a thin outlined `Pill` 18 pt, the only badge on the hero in 0.2.
  6. 20 pt gap.
  7. Logo box 600 x 140, image fitted and bottom-left aligned (`logoPath` at `ArtworkSize.logo`). **Text fallback** when there is no logo: title in the 96 pt hero font, white 100%, one line, `minimumScaleFactor` 0.6, bottom-aligned on the same baseline as the logo box, with a 0 x 2 pt black 40% shadow so it reads over bright art. The fallback must look like a choice, not a failure: same position, same weight, no "no logo" styling.
- **Default focus** on launch and on returning to Home is the hero's Play button. First frame: the button is focusable immediately; the entrance animation never delays input.

### 3.2 Rows (from 864 pt)

- Row 1 header baseline sits at y 900 so about 140 pt of the first row's cards peek above the fold at rest. That peek is deliberate (Apple TV app).
- `Row` as built in WP-03: 28 pt semibold title at x 80, 12 pt gap, then the cards with 24 pt item gap and 80 pt margins; row gap 36. Horizontal scroll snaps to cards (`viewAligned`), cards never clip at the left margin.
- Landscape rows show 4 full cards and about half of a fifth; the poster row shows 8 full cards and a sliver of a ninth. The partial card is the affordance to scroll.
- Card captions (22 pt, one line each, no scaling on focus):
  - Continue watching: film "Title" / "31 min left"; episode "Series title" / "S2 E5 · 31 min left". Progress bar along the bottom edge of the artwork, 4 pt, white on 30% white, as built in `CardArtwork`.
  - Up next: "Series title" / "S2 E5 Episode title" (episode title truncated with an ellipsis). No progress bar.
  - Recently added: "Title" / "2024" for films, "Series" / "2024" for series. New in the last 7 days gets nothing extra in 0.2 (the NEW pill is 1.0).
- Artwork per card: landscape cards use the episode still (`thumbPath`) at `ArtworkSize.landscape`; films in Continue watching use `artPath` (the backdrop) at landscape size, cropped centre; posters use `thumbPath` at `ArtworkSize.poster`. Placeholder as the hero.
- When a row is focused, the scroll view brings its header to y 60 (the top margin) and the hero slides up out of view with the scroll, keeping its content pinned to its own bottom. Returning focus to the hero scrolls back to 0.

### 3.3 Kids' profile (`PerchStyle.kids`)

Same layout. Card radius 16, type scaled 1.1 (already in PerchStyle), rows already filtered by `RowContext.admit`, and the hero is chosen only from admitted items. Nothing else differs in 0.2; the "no horror artwork in seasonal rows" rule is for 1.2.

## 4. Hero item

Deterministic, so the hero only changes when the data changes:

1. the first Continue watching item, else
2. the newest Recently added film or series (not an episode), else
3. nothing: the hero area shows one of the states in 6.

Reasoning: the hero is the first focus, so putting the in-progress item there makes "resume" one click for the nightly case and leaves two clicks for everything in the rows. It also appears in row 1; that duplication is accepted (the Apple TV app repeats Up Next items in its hero) and recorded in DECISIONS when built. A rotating or focus-following hero is 1.0.

Hero copy for Continue watching: button **Resume**, metadata as in 3.1. For a Recently added pick: button **Play**.

## 5. Focus and the remote

- **Order.** Launch: hero Play. Down from the hero: row 1, at its remembered card or its first card. Left and right within a row; the row never wraps. Down and up move between rows, landing on each row's remembered card (`.focusSection()` per row, as WP-03 built). Up from row 1: the hero button.
- **Select** on a card: Continue watching resumes at `viewOffsetMs`; Up next plays the episode from the start; Recently added plays the film from the start, or for a series plays its first unwatched episode, else S1 E1 (the title page is WP-11; this is the 0.2 behaviour and is recorded in DECISIONS). Select on the hero button does the same for the hero item.
- **Back** inside the player returns to Home with focus on the exact card or button that started playback, and the vertical and horizontal scroll where they were. Back on Home at the hero does nothing in 0.2 (there is nowhere above Home); it never returns to the profile picker.
- **Long-press Select** on a card: nothing in 0.2 (context menu arrives with WP-11). It must not play.
- **Play/Pause** on a focused card plays it (same as Select).
- **Focus effect.** Cards: the system highlight effect (lift, parallax, shadow) plus the 3 pt white ring, as decided in WP-03; the caption does not move. Hero button: the system button focus plus scale 1.06. No custom shadows. Each row remembers its last focused item id (`FocusCoordinator` pattern from Swiftfin, reimplemented), and Home remembers which row and item last had focus, in memory per profile.

## 6. States

Every state renders in the first frame from whatever is known. No state shows a `ProgressView`.

| State | Hero | Rows | Extra |
|---|---|---|---|
| **Warm launch, snapshot present** (the nightly case) | from the snapshot, placeholder art, then crossfade to real art | from the snapshot, headers and captions complete | refresh in place in the background (8) |
| **First launch after setup, no snapshot** | tinted base gradient (no art), a single 26 pt `textHelper` line centred in the hero: "Getting your library ready", no indicator | none yet; each row fades in as it arrives | if nothing arrives in 20 s the server state decides: unreachable or empty below |
| **Empty library** (server reachable, all rows empty) | base gradient, centred: 64 pt "Nothing to watch yet", 26 pt helper "Films and series you add to your media server will show up here.", one secondary button **Check again** | none | |
| **Offline with snapshot** (refresh failed, cached rows exist) | cached | cached | `PerchCornerNotice` top-left, 6 s: "Can't reach your media server. Showing what you had." Shown once per failure, not on every retry. Select on a card still tries to play; failure shows the player's "Couldn't play this. Try again" |
| **Offline, no snapshot** | base gradient, centred: 64 pt "Can't reach your media server", 26 pt helper "Check it's on and connected, then try again.", primary **Try again**, secondary **Switch profile** | none | this replaces today's placeholder lines (`home.serverDown`, `home.retry` identifiers kept) |
| **Kid profile** | as above, admitted items only | admitted items only | style `kids`; **Switch profile** keeps the PIN rule; no "Run setup again" (a kid sees "Ask a parent to change setup" where that control lives) |
| **Partial** (one or two rows empty) | as 4 | only non-empty rows, no gaps left behind | |

The centred hero messages use the same block grid as 3.1 but centred horizontally and vertically in the hero so the screen does not look top-left anchored (Robin's objection to the WP-04 screens).

Until Settings exists (WP-18), **Switch profile** and **Run setup again** stay reachable from Home: a small translucent-material menu button, 68 pt, top-right at x 1840 right edge, y 60, with the profile avatar at 44 pt and the profile name; Select opens a `PerchTopSheet` with Switch profile and Run setup again (Admin PIN through the Authoriser as today). It is the last item in the focus order (right from the hero button). This replaces the placeholder's buttons and is removed when the sidebar lands.

## 7. Motion (exact)

All timings go through `PerchMotion.resolve`. Spring is the house spring (response 0.45, damping 0.85). Nothing bounces, nothing overshoots.

**Entrance, every time Home appears with content** (launch, profile switch; not on Back from the player, where the screen is simply there):

| t (s) | Element | Effect | Reduce Motion |
|---|---|---|---|
| 0.00 | backdrop | fade in 0.5 s; Ken Burns 4% scale over 20 s, linear, then holds | fade 0.3 s, no pan |
| 0.10 | logo or title text | fade 0.4 s, scale 0.96 to 1.0 | fade 0.3 s |
| 0.20 | metadata, synopsis, button | fade 0.3 s, slide up 12 pt | fade 0.3 s |
| 0.25 | row 1 | fade 0.3 s, slide up 12 pt | fade 0.3 s |
| 0.35 | row 2 | same | same |
| 0.45 | row 3 | same | same |

The first frame already contains every element at opacity 0 and the hero button is focusable at t 0; the entrance is cosmetic and is interrupted cleanly by input.

**Live changes**

- Image arrival: crossfade placeholder to image 0.3 s. First-row images must be prefetched from the snapshot before the first frame so the first row shows no pop-in (DESIGN premium checklist 2).
- Page tint: `PageBackground` with `perchTint` from the hero backdrop at 10%; when the tint changes (image arrived, hero item changed) crossfade 0.5 s. Reduce Motion: same (a fade).
- Refresh in place: an item that is new fades in 0.3 s; a removed item fades out 0.3 s and its neighbours close the gap with the spring; a moved item animates with the spring; progress bars animate width 0.3 s. A row that goes from empty to non-empty slides in like the entrance row. Nothing moves under the focused card: if the focused item is removed, focus goes to its neighbour without a jump.
- Focus: system highlight timing; ring fades 0.15 s; focused row lifts 4 pt and the others dim to 0.9 with the spring (Reduce Motion: dim only, no lift).
- Scroll between hero and rows: the spring.
- Hero change (the hero item changed after a refresh): crossfade the whole hero 0.5 s, no re-entrance.
- Corner notice: slides down from the top-left and fades, 0.35 s (existing `OverlayTransition`).

## 8. Data and refresh

- First frame: `ModuleRegistry.cachedRow` for each provider, synchronously, on the main actor, from the snapshot. No await before the first frame.
- Then one `refreshRow` per provider in a task group; results are applied as they land, each with the in-place animations above. A failed refresh keeps the cached rows and raises the offline notice once.
- Hero synopsis: `MediaSummary` carries no summary. Add `summary` (capped at 300 characters) to the light fields of `MediaSummary` and the snapshot in PerchPlex, since the hub JSON already carries it; the snapshot format bumps and an old file is simply ignored. If the owner judges that too large for the slice, the fallback is to fetch the hero's `MediaDetail` after the first frame and fade the synopsis in; the layout reserves the two lines either way.
- Hero logo: `logoPath` (clearLogo) from the item, else the series logo for an episode, else text.
- Prefetch before the first frame: hero backdrop and logo, row 1 artwork; then row 2 and 3 artwork, then the next page of each row as it scrolls. This is WP-08's `ArtworkPrefetcher`; WP-09 only calls it.
- Images decode off the main thread (WP-08). Home never blocks on an image.

## 9. Tint

Tint comes from the hero backdrop pixels (`ArtworkTint.tint(from:)`), never from metadata. It is applied once, to the page background at 10% over `#0b0b0f`. It is not applied to text, buttons, rings or scrims. Neutral art gives the plain base. Kids' profile: same tint rule. Focus-following tint (background changes as you move across cards) is 1.0, not 0.2.

## 10. Wording

Sentence case, no exclamation marks, no backend names. All strings in one place in the Home feature.

| Where | Text |
|---|---|
| Row titles | Continue watching · Up next in your series · Recently added |
| Hero button | Play · Resume |
| Time left | "31 min left" · "1 h 12 min left" · under 1 min "Almost done" |
| Episode code | "S2 E5" (no leading zeros) |
| Series card year line | "Series · 2024" |
| First launch | Getting your library ready |
| Empty | Nothing to watch yet / Films and series you add to your media server will show up here. / Check again |
| Offline, cached | Can't reach your media server. Showing what you had. |
| Offline, nothing cached | Can't reach your media server / Check it's on and connected, then try again. / Try again / Switch profile |
| Profile menu | Switch profile · Run setup again · (kid) Ask a parent to change setup |

Never: Plex, server name, hub, on deck, transcode, snapshot, cache, loading, error codes.

## 11. Acceptance and how it is measured

From `docs/ROADMAP.md` 0.2.0:

1. **Home renders from cache with no spinner on second launch.** Verified on the test simulator with the fake household: first launch populates the snapshot; the second launch is captured at its first frame and must show hero and rows (checklist S1). A unit test proves `cachedRow` output renders without any async work; a UI test asserts no `ProgressView` identifier appears on Home at any time.
2. **Launch to Home under 1.5 s warm.** A DEBUG-only signpost from process start to the first Home frame, read from the simulator log, on the live simulator against the household server, three runs, all under 1.5 s. Reported with the numbers. Not verified on the Apple TV (simulator-only period, see memory).
3. **Two clicks or fewer to resume.** UI test: launch, press Select (hero Resume) resumes the fixture's in-progress item; and launch, Down, Select resumes from row 1.
4. **Back returns where you were.** UI test: focus row 1 card 3, Select, Back; focus is on row 1 card 3.

## 12. Screenshot checklist (defines done)

The verifier captures these on the test simulator (fake household) unless marked live. The lead judges each against section 1 and the criteria here; a fail goes back to the slice owner. All at 1920 x 1080, standard profile unless stated.

| Id | Capture | Pass when |
|---|---|---|
| S1 | second launch, first frame (t 0) | hero and three rows present with captions; placeholders only where art has not landed; no spinner, no blank |
| S2 | t 1.5 s after launch | entrance complete; logo present; art crossfaded in; row 1 peeks about 140 pt; page tinted from the backdrop |
| S3 | focus on row 1, card 2 | hero scrolled away, row 1 header at y 60, system lift and 3 pt ring on card 2 only, caption still, other rows dimmed 10%, progress bar and "min left" visible |
| S4 | focus on row 3 (posters) | 8 full posters plus a sliver; captions aligned; no clipped left card |
| S5 | hero text fallback (fixture item without a logo) | 96 pt title in the logo's place; looks intentional |
| S6 | kid profile | radius 16, larger type, only admitted items; profile menu shows Switch profile |
| S7 | empty library fixture | centred message, one secondary button, nothing else |
| S8 | offline with snapshot (`-PerchFakeServerDown` after a good launch) | rows intact, corner notice visible once |
| S9 | offline, no snapshot | centred message with Try again (primary) and Switch profile |
| S10 | Reduce Motion on, t 0.4 s | elements fading, no slide, no scale, no pan |
| S11 | live simulator, Robin's library, t 1.5 s | real logo on the hero, real art in rows, nothing names a backend, launch time under 1.5 s in the log |
| S12 | after Select on row 1 card 3 then Back | focus ring on row 1 card 3, scroll unchanged |
| R1 | 12 s recording: launch, Down, Right x2, Select, Back | every transition smooth, no pop-in on row 1, no jump when images or the synopsis arrive, Back lands on the card |
| R2 | 6 s recording, Reduce Motion | fades only |

Done also needs: `scripts/gate.sh` green, no new warnings, the DEBUG Library check removed, the placeholder's Home strings and identifiers migrated, `CHANGELOG.md` and `DECISIONS.md` updated, and the PR body listing S1 to S12 with anything not captured stated plainly.

## 13. Dependencies and open points for Step 2

- WP-08 must be merged first: `ArtworkImage`, `ArtworkPrefetcher` and the tint plumbing are not on `origin/main` or on `wp-08-artwork` yet (4 Nov 2026). WP-09 calls them and does not rebuild them. If WP-08 ships a different API, sections 3, 7 and 8 adapt; the numbers stay.
- `MediaSummary.summary` (section 8) is a small PerchPlex addition owned by one slice.
- The snapshot's `written` date is not public; nothing in 0.2 needs it, so leave it.
- `PerchSize.focusScale` appears unused on cards; the hero button is the one place it applies.
- Components to add to PerchDesign in WP-09, composed in the gallery as a realistic Home, not a list: `HeroMessage` (the centred message block of section 6) and the profile menu button. No other new components; no new packages.
