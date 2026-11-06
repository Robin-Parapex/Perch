# WP-11 Series and title pages: report (draft)

6 Nov 2026. Branch `wp-11-title-pages`. Plan and notes: `docs/notes/wp-11-plan.md`. Simulator only; no Apple TV run.

## Summary
Film and series pages with a fixed-size hero (logo, facts line, inline format marks, synopsis), a state-aware primary button, icon-circle secondary buttons, and a cast rail. The series page adds season chips, an episode shelf and one Play next rule (`SeriesNext`) used everywhere a series plays. Select on grid, collection and Home series cards opens the page; Play/Pause plays. A theme music hook is built, off by default and never for kids.

## Acceptance
| Item | Result | Shown by |
|---|---|---|
| Title page with state-aware primary button and first focus | Done | TitleUITests, PerchAppTests TitleLogicTests, live screenshots |
| Series page with season rail, episode list, Play next | Done | TitleUITests, PerchAppTests TitleLogicTests, live screenshots |
| Cast rail | Done | TitleUITests, live probe, live screenshots |
| Theme music hook, off for kids | Done | PerchAppTests TitleLogicTests, live probe |
| Resume and next episode within 2 clicks from Home | Done | HomeUITests, TitleUITests |
| Back returns to the exact episode or card | Done | TitleUITests, HomeUITests, LibraryUITests |

## Screenshots
Captured in the lead's scratchpad; files `wp11b-*.png` in:
- `/private/tmp/claude-502/-Volumes-RoBroLabs-MediaDisk-Parapex-Github-Perch/3729fe79-1cc3-4fd2-b0a3-4f79d23cca68/scratchpad/`

## Tests run
Targeted, not the full gate, per DECISIONS ("Targeted checks before a PR during active development"). Simulator 11ACEAE4 (test simulator).
- PerchAppTests 52.
- TitleUITests 5.
- LibraryUITests 5.
- NavigationUITests 8.
- HomeUITests 7.
- PlayerUITests 7 of 8 in the combined run; the failing one (testStillWatchingContinueKeepsPlaying) passes alone.
- DesignGalleryUITests 3.
- PerchDesign 43.
- PerchCore 207.
- PerchPlex 360.

## Live probe
Household server, normal signed launch, 6 Nov 2026.
| Check | Result |
|---|---|
| First film | 44 cast, no theme, logo |
| First series | theme yes, 24 episodes |

## Review
- Opus code review: ship, with 2 should-fix items and notes. All fixed. The token never reaches third-party hosts.
- Opus design critique: "needs fixes". All fixed or recorded.

## Decisions
Recorded in `docs/DECISIONS.md` ("2026-11-06 Series and title pages (WP-11)").

## Known issues
- Simulator only; no Apple TV run.
- Live theme music not heard by ear.
- Two player UI tests are flaky under long combined runs.
- Some logos have transparent margins.
- No gallery entries for the new components (`PerchIconButton`, `FormatGlyph`, `FactsLine`).
