# WP-09 Home screen: report (draft)

5 Nov 2026. Branch `wp-09-home`. Spec: `docs/design/wp-09-home.md`. Simulator only; no hardware run.

## Summary
Home replaces the placeholder: hero with logo or text fallback, metadata line and synopsis; Continue watching, Up next in your series and Recently added rows; first frame from the cached snapshot with no spinner; empty, offline and first-launch states; profile menu top-right until the sidebar lands; kids' style; page tint; staged entrance with Reduce Motion variants; focus memory and Back to the card. The DEBUG Library check is removed.

## Acceptance
Source: spec section 11 (ROADMAP 0.2.0).

| Item | Result |
|---|---|
| Home renders from cache with no spinner on second launch | PASS. `testCachedRenderOnSecondLaunchHasNoSpinner`. The cached Home also draws while the session is still connecting (fix e6034ed) and with the server down (capture at 1 s). |
| Launch to Home under 1.5 s warm | PASS on the live simulator against Robin's server: 914, 882, 845 ms (first run); 864, 1242, 996 ms (after the artwork fix). About one run in three shows a 1 to 2 s stall before the app's root view exists (3279 ms once); that is simulator or debug-build start-up, not Home. |
| Two clicks or fewer to resume | PASS. `testResumeInTwoClicks` (Select on the hero; Down then Select). |
| Back returns where you were | PASS. `testBackReturnsToCard`, `testRowFocusMemory`, `testPlayFromHomeCardAndMenuReturnsFocusToTheCard`. |

## Screenshot checklist
Source: spec section 12. Captures are in the lead's scratchpad and attached to the PR.

| Id | Capture | Result |
|---|---|---|
| S1 | second launch, first frame | Not meaningful: black at 0.3 s on the simulator because the process has not drawn yet (the signpost covers it) |
| S2 | t 1.5 s after launch | Pass |
| S3 | focus on row 1, card 2 | Pass (header at about 72 pt, spec says 60) |
| S4 | focus on row 3 (posters) | Pass |
| S5 | hero text fallback | Pass |
| S6 | kid profile | Pass after the synopsis box fix |
| S7 | empty library fixture | Pass |
| S8 | offline with snapshot | Pass after fix e6034ed (hero, rows and notice at 1 s) |
| S9 | offline, no snapshot | Pass |
| S10 | Reduce Motion on, t 0.4 s | Captured, judged fades only |
| S11 | live simulator, Robin's library | Pass after fix 153f42e (series logo, backdrop, five loaded cards by 1.5 s) |
| S12 | after Select on row 1 card 3 then Back | Pass |
| R1 | 12 s recording: launch, Down, Right x2, Select, Back | Captured, not judged frame by frame |
| R2 | 6 s recording, Reduce Motion | Captured, not judged frame by frame |

## Tests run
Targeted, not the full gate, at Robin's instruction (see DECISIONS, "Targeted checks before a PR during active development"). All green in signed runs on the test simulator on 5 Nov 2026:
- PerchCore 207, PerchPlex 332, PerchDesign (all, including HeroMetricsTests).
- PerchAppTests 18.
- HomeUITests 7, ArtworkUITests 1, ProfilePickerUITests 9, PlayerUITests 8, DesignGalleryUITests 3.
- Final run after the last commit (153f42e): xcodegen drift check clean; HomeUITests 7 of 7 passed, signed, on the test simulator.

## Decisions
All in `docs/DECISIONS.md`, 2026-11-05 entries.
- Hero item on Home.
- Select on Home cards in 0.2.
- Back on Home.
- Hero synopsis comes from the snapshot.
- Home reads settings synchronously for the first frame.
- Profile menu until the sidebar.
- Ambient motion switch.
- Row animation scoped to the rows stack.
- Certificate inline in the hero metadata.
- Library check removed.
- Home renders while the session connects.
- Artwork loads wait for the session.
- Stale launch profile never renders.
- Targeted checks before a PR during active development.

## Known limits
- The header lands at about 72 to 77 pt rather than 60 when a row is focused; cause not found.
- Back from the player can take several Menu presses while the player is loading or Skip Intro is up. This is player behaviour from WP-07.
- No hardware run; simulator only.
- The fake household has one logo only.
- Occasional 1 to 2 s stall before the root view on simulator launch.

## Not verified
- No tests yet for: a failed parent-to-kid switch while the server drops; Select on a season card; Back with no hero; a restricted user with no settings entry getting the kids style; the kid ceiling applied on Home rows.
- `testRowFocusMemory` passes on geometry alone; it needs a different column in row 2.
- Design gallery kid preview and the composed Home section were not screenshot-reviewed.
- S1 first frame, and R1 and R2 frame by frame.

## Follow-ups
- An artwork load that times out after 20 s while the server is unreachable never retries when the server returns.
- Find the cause of the row header landing at about 72 to 77 pt when focused (spec: 60).
- The fixture video carries an audible test tone during UI tests; make it silent.
- Add the missing tests listed under Not verified.
