# WP-12 Search: report (draft)

6 Nov 2026. Branch `wp-12-search`. Plan and notes: `docs/notes/wp-12-plan.md`. Simulator only; no Apple TV run.

## Summary
A Search tab using the system search field and keyboard (`.searchable` on the tab root). Results sit in rows below: Films and Series, Episodes, and Collections for adults. Select opens a film or series page and plays an episode; Play/Pause plays. Every result is checked against the profile's rating ceiling in the app, because the live server ignores the rating filter on search. The query is kept per profile until a profile switch.

## Acceptance
| Item | Result | Shown by |
|---|---|---|
| Search field with the system keyboard | Done | SearchUITests, live screenshots |
| Dictation into the field | Manual check by Robin, not automatable | Not shown |
| Library results in rows | Done | SearchUITests, SearchModelTests, live screenshots |
| A kid sees no 15/18 results | Done | SearchUITests (leaking server), SearchModelTests |
| Query kept when leaving and returning | Done | SearchUITests, SearchModelTests |
| Back from a page and from the player returns to the same result | Done | SearchUITests |

## Screenshots
Captured in the lead's scratchpad; files `wp12b-*.png` in:
- `/private/tmp/claude-502/-Volumes-RoBroLabs-MediaDisk-Parapex-Github-Perch/3729fe79-1cc3-4fd2-b0a3-4f79d23cca68/scratchpad/`

## Tests run
Targeted, not the full gate, per DECISIONS ("Targeted checks before a PR during active development"). Simulator 11ACEAE4 (test simulator).
- PerchPlex 367.
- PerchAppTests 66.
- SearchUITests 4.
- NavigationUITests 8.
- HomeUITests 7.
- LibraryUITests 5.
- TitleUITests 5.

## Live probe
Household server, signed launch, 6 Nov 2026.
| Check | Result |
|---|---|
| "the" | 20 results per group in about 140 ms |
| Single letters | Nothing returned |
| `contentRating=` on search | Ignored by the server |
| Collections | Carry section and type |

## Review
- Opus code review: no leak path, 3 should-fix items and notes. All fixed.
- Opus design critique: small fixes. All applied.

## Decisions
Recorded in `docs/DECISIONS.md` ("2026-11-06 Search (WP-12)").

## Known issues
- Simulator only; no Apple TV run.
- Dictation not checked.
- Returning to the tab focuses the keyboard, not the last result.
- Poster titles are one line at rest.
- The teen (managed-account) restriction on search is unverified live.
