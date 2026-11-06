# WP-13 Sidebar shell: report (draft)

6 Nov 2026. Branch `wp-13-sidebar`. Plan: `docs/notes/wp-13-plan.md`. Simulator only; no Apple TV run. Built before WP-10 so the grids, title pages and search have a home.

## Summary
Sidebar shell (system TabView sidebar: Home, Films, Series, Search, Settings). The profile avatar in the sidebar header opens the picker. A navigation stack per tab, with per-profile focus memory. Settings tab: switch profile, run setup again (kids see "Ask a parent"). Films, Series and Search are empty pages until WP-10, WP-12 and WP-11. The profile menu on Home is removed.

Launch focus lands in the sidebar (tvOS 27 system behaviour; five approaches tried). Resume is Right then Select, within the two-click rule. Hero text fades while the sidebar has focus.

## Back rules
- Back pops within a tab. At a tab root, focus moves to the sidebar.
- In the sidebar, a first Back shows "Press Back again to leave". A second Back within 2 s leaves the app (Robin's decision, 5 Nov 2026).
- Double-tap Back from content returns to Home.

## Acceptance
| Item | Result | Shown by |
|---|---|---|
| Sidebar with Home, Films, Series, Search, Settings and the profile avatar | Done | NavigationUITests, wp13b-expanded.png |
| Back pops within a tab; at a tab root it moves to the sidebar | Done | NavigationUITests |
| Back in the sidebar: double press to leave, with a hint | Done | NavigationUITests, wp13b-hint.png |
| Double-tap Back from content returns to Home | Done (focus lands on the Home sidebar item) | NavigationUITests |
| Focus restored per tab and per profile | Done | NavigationUITests, PerchAppTests |
| Launch lands on Play | Not met: tvOS 27 gives the sidebar first focus; resume is Right then Select | DECISIONS |
| Kid profile cannot run setup from Settings | Done (enforced in code) | ProfilePickerUITests, review |

## Screenshots
Captured in the lead's scratchpad; not judged frame by frame.
- `/private/tmp/claude-502/-Volumes-RoBroLabs-MediaDisk-Parapex-Github-Perch/3729fe79-1cc3-4fd2-b0a3-4f79d23cca68/scratchpad/wp13b-expanded.png`
- `/private/tmp/claude-502/-Volumes-RoBroLabs-MediaDisk-Parapex-Github-Perch/3729fe79-1cc3-4fd2-b0a3-4f79d23cca68/scratchpad/wp13b-films.png`
- `/private/tmp/claude-502/-Volumes-RoBroLabs-MediaDisk-Parapex-Github-Perch/3729fe79-1cc3-4fd2-b0a3-4f79d23cca68/scratchpad/wp13b-hint.png`
- `/private/tmp/claude-502/-Volumes-RoBroLabs-MediaDisk-Parapex-Github-Perch/3729fe79-1cc3-4fd2-b0a3-4f79d23cca68/scratchpad/wp13b-kid.png`

## Tests run
Targeted, not the full gate, per DECISIONS ("Targeted checks before a PR during active development"). Simulator 11ACEAE4 (test simulator).
- NavigationUITests 8 of 8.
- HomeUITests 7 of 7.
- ProfilePickerUITests 9 of 9.
- DesignGalleryUITests 3 of 3.
- PerchAppTests 20.
- PerchDesign 42.

## Review
- Opus reviewer: "ship", with 2 should-fix items (avatar carried over to a kid profile; double-tap Back left the leave hint showing) and notes (stacks reset on profile switch; unresolved profile treated as kid in Settings). All fixed.
- Opus design critic: "needs fixes" (launch focus, hint placement, hero title under the sidebar, empty-state copy and size, avatar alignment, DESIGN.md out of date). All fixed or recorded. The critic's call to drop the double-Back hint was overruled by Robin's explicit request.

## Decisions
Robin's decisions are recorded in `docs/DECISIONS.md` ("2026-11-05 Sidebar and navigation (WP-13)").

## Known limits
- Simulator only; no Apple TV run.
- Push focus uses a 0.6 s nudge; check on hardware.
- PIN keypad dismissal then setup rerun swap: check on hardware.
- Leave-hint inset is tied to the panel width.

## Not verified
- Double-tap Back while already in the sidebar has no test.
- Profile-change stack reset is not tested with a pushed screen.
- Launch focus on hardware (system behaviour on tvOS 27).

## Follow-ups
- Check push focus (0.6 s nudge), the PIN keypad swap and launch focus on the Apple TV.
- Add tests for the two untested cases above.
