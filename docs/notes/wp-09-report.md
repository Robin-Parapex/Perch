# WP-09 Home screen: report (draft)

5 Nov 2026. Branch `wp-09-home`. Spec: `docs/design/wp-09-home.md`.

## Summary
Home replaces the placeholder: hero with logo or text fallback, metadata line and synopsis; Continue watching, Up next in your series and Recently added rows; first frame from the cached snapshot with no spinner; empty, offline and first-launch states; profile menu top-right until the sidebar lands; kids' style; page tint; staged entrance with Reduce Motion variants; focus memory and Back to the card. The DEBUG Library check is removed.

## Acceptance
Source: spec section 11 (ROADMAP 0.2.0).

| Item | Result |
|---|---|
| Home renders from cache with no spinner on second launch | pending verifier |
| Launch to Home under 1.5 s warm | pending verifier |
| Two clicks or fewer to resume | pending verifier |
| Back returns where you were | pending verifier |

## Screenshot checklist
Source: spec section 12.

| Id | Capture | Result |
|---|---|---|
| S1 | second launch, first frame | pending |
| S2 | t 1.5 s after launch | pending |
| S3 | focus on row 1, card 2 | pending |
| S4 | focus on row 3 (posters) | pending |
| S5 | hero text fallback | pending |
| S6 | kid profile | pending |
| S7 | empty library fixture | pending |
| S8 | offline with snapshot | pending |
| S9 | offline, no snapshot | pending |
| S10 | Reduce Motion on, t 0.4 s | pending |
| S11 | live simulator, Robin's library | pending |
| S12 | after Select on row 1 card 3 then Back | pending |
| R1 | 12 s recording: launch, Down, Right x2, Select, Back | pending |
| R2 | 6 s recording, Reduce Motion | pending |

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

## Known limits
- The header lands at about 77 pt rather than 60 when a row is focused; cause not found.
- Back from the player can take several Menu presses while the player is loading or Skip Intro is up. This is player behaviour from WP-07.
- No hardware run; simulator only.
- The fake household has one logo only.

## Not verified
TBC (to be filled by the lead).
