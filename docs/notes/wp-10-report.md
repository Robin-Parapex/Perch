# WP-10 Films and Series: report (draft)

6 Nov 2026. Branch `wp-10-library`. Plan and notes: `docs/notes/wp-10-plan.md`. Simulator only; no Apple TV run.

## Summary
Films and Series tabs are paged poster grids with native sort and filter menus (genre, decade, resolution, unwatched), a letter rail when sorted by title, and a Collections row above the grid that opens a collection page. The profile's rating ceiling applies to the grid, the letters and the collections, and is checked again on every page. Fake household browse data (28 films, 13 series, three collections) and a read-only browse probe are DEBUG only.

## Acceptance
| Item | Result | Shown by |
|---|---|---|
| Sort | Done | LibraryUITests, PerchPlex tests |
| Filters | Done | LibraryUITests, PerchPlex tests, live probe |
| Letter jump | Done | LibraryUITests, PerchDesign tests |
| Collections (row and page) | Done | LibraryUITests, live probe |
| Back returns to the same poster | Done | LibraryUITests, NavigationUITests |
| A kid sees no 15 or 18 titles | Done | LibraryUITests, PerchPlex tests, code review, live probe |
| Live check against the household server | Done | Live probe, below |

## Screenshots
Captured in the lead's scratchpad; not judged frame by frame. Files `wp10b-*.png` in:
- `/private/tmp/claude-502/-Volumes-RoBroLabs-MediaDisk-Parapex-Github-Perch/3729fe79-1cc3-4fd2-b0a3-4f79d23cca68/scratchpad/`

## Tests run
Targeted, not the full gate, per DECISIONS ("Targeted checks before a PR during active development"). Simulator 11ACEAE4 (test simulator).
- PerchPlex 354.
- PerchDesign 43.
- PerchAppTests 34.
- LibraryUITests 5.
- NavigationUITests 8.
- HomeUITests 7.
- DesignGalleryUITests 3.

## Live probe
Household server, normal signed launch, 6 Nov 2026, after the rating-key fix.
| Check | Films | Series |
|---|---|---|
| Unfiltered | 490 | 132 |
| PG ceiling, before fix | 1 | 4 |
| PG ceiling, after fix | 223 | 25 |
| 12 ceiling | 338 | 41 |
| Collections, unfiltered | 94 | none |
| Collections under PG | 50 | none |

## Review
- Opus code review: no leak found; one blocking over-restriction and 4 should-fix items. All fixed.
- Opus design critique: "needs fixes", with 2 blocking (lopsided grid, kid collections row) and 6 should-fix. All fixed or recorded.

## Decisions
Recorded in `docs/DECISIONS.md` ("2026-11-06 Films and Series grids (WP-10)").

## Known issues
- Simulator only; no Apple TV run.
- Reconnect during paging is proven by unit tests only.
- A lowered-ceiling collections row costs about 2 s of member loads (estimated, not measured).
- Focus lift on grid posters is the system highlight, about 1.11 (DESIGN says 1.05 to 1.08).
- The `-PerchOpenFirstCollection` DEBUG flag is not covered by a test.
- The Series tab shares the Films code and has no UI test of its own.
