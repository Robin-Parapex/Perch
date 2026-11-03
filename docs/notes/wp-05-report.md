# WP-05 Setup wizard and profile picker: report

3 Nov 2026. Branch `wp-05-setup-wizard`, stacked on the local `wp-04-plex-signin` tip (ad4ece0). All commits are local. Nothing is pushed, no PR is open, and there is no version bump or tag.

## What was built
- **Setup wizard:** Welcome, Connect Plex (code or address, "Connected to Living room, 2 libraries"), Choose server (only when more than one), Admin PIN, Profiles and roles, Add later, Done.
  - The Admin PIN step always verifies, and the wizard cannot finish without an Admin PIN.
  - Add later lists module-registered "Coming soon" entries.
- **"Who's watching?" picker:**
  - Tinted avatars over blurred library art, white focus ring, "Watching now" on the current profile, and a lock on protected profiles.
  - PIN screens are centred on the same art. A wrong PIN shakes; a lockout counts down.
  - Offline, the picker shows cached profiles with "Can't switch profiles right now" and Try again.
- **Switching rules in code:** PlexSession works out what a switch needs from fresh Home users, so no screen can weaken it.
  - Leaving a kid profile needs the adult's Plex PIN, or the Admin PIN when the adult has none.
  - An unknown current profile counts as kid.
  - Five wrong tries lock, for profile PINs and the Admin PIN alike.
- **Run setup again** from the temporary home, behind the Admin PIN; a kid sees "Ask a parent to change setup" with no keypad.
- **Signed out after setup** reopens the wizard at Connect Plex.
- **Picker art** is limited to the household's strictest rating, so kids never see art above their ceiling.
- **DEBUG switches:**
  - `-PerchFakeHousehold withPINs|noPINs`: Robin as owner, Jo as a protected adult, Sam as a kid, PIN 1234, link code PRCH.
  - `-PerchFakeSignedOut`, `-PerchResetSetup` and `-PerchDesignGallery`.

## Acceptance (ROADMAP:53-54), shown with the fake households in signed UI tests
| Item | Shown by |
|---|---|
| Wizard completes with Plex only | `testWithPINsWizardCompletesAndLandsOnPicker` |
| Refuses to finish without an Admin PIN; mismatch says so | `testNoPINsWizardRequiresPerchPINAndRefusesMismatch` |
| Protected profile asks for its PIN (wrong, then right) | `testProtectedProfileAsksForItsPIN` |
| Leaving a kid asks for a PIN when the adult has none | `testLeavingAKidProfileAsksForTheAdminPIN`, plus PerchPlex `PlexPolicySwitchTests` |
| Admin PIN gates re-run; a kid is refused | `testParentRunsSetupAgainWithTheAdminPIN`, `testKidCannotRunSetupAgain` |
| Five wrong attempts lock out | `testFiveWrongProfilePINsLock`, `testFiveWrongAdminPINsLockTheWizardStep`, `testLockoutShowsAtOnceWhenPINScreenReopens` |
| Offline picker | `testOfflinePickerShowsProfilesAndCannotSwitch` |
| Back | `testBackReturnsToThePreviousStep`, `testBackFromPINScreenReturnsToPicker`, `testBackOnPickerOpenedFromHomeReturnsHome` |
| Signed out reopens the wizard | `testSignedOutAfterSetupReopensWizardAtConnectPlex` |

Gate: `scripts/gate.sh` GATE PASS at 587cfd3. Results:
- xcodegen: no drift.
- Packages: PerchCore 174, PerchPlex 129, PerchDesign 26 and 7 placeholder suites.
- UI tests: 18 run signed, 0 failed, 0 skipped (the gate fails on skips).
- Warnings: none in the app build.

## How it was checked
- **Opus visual critic** on the first screenshots ("not ready": two primaries per screen, flat PIN screens, small titles, ragged profile rows, lockout looking normal). Findings were fixed. The lead and builders looked at a few new screenshots (picker, profiles grid, Admin PIN); the critic did not run a second pass.
- **Opus code review** of `ad4ece0..HEAD` ("ship with fixes", nothing blocking). Fixed:
  - the switch policy now runs in the session on fresh data, closing a stale-PIN loophole that would let a kid out;
  - Back now leaves the app at top level;
  - setup edits check the real current profile;
  - a guard on finishing;
  - the link sign-in is cancelled with the wizard;
  - the lockout shows when the PIN screen reopens;
  - picker art is rating-filtered.
- **Gate:** signed simulator UI tests on the Apple TV 4K 3rd generation simulator (11ACEAE4), never your live one. The gate now fails if any test is skipped.

Screenshots (temporary, gone after a reboot):
- `/private/tmp/claude-502/-Volumes-RoBroLabs-MediaDisk-Parapex-Github-Perch/94700a35-b9d5-4c30-8a43-9de4ed51df8d/scratchpad/wp05-shots-v2/`
- the latest grid and picker: `.../scratchpad/wp05-shots-v3/`

## Needs Robin
1. **Look at it:** a walk-through with your real account on the live simulator.
2. **Push and PRs:** WP-04 (PR 5, 12 local commits not pushed) first, then WP-05 as its own PR stacked on it. Say the word and I run `/pr open`.
3. **0.1.0 release:** WP-05 ends 0.1.0, which needs TestFlight. That conflicts with simulator-only for now; your call on timing.
4. **Network scan:** Bonjour `_plexmediasvr._tcp` is the low-risk route if you want it in the wizard. It is out of WP-05.
5. **Artwork before sign-in:** Welcome and Connect have no art, because no server is known yet. A bundled art set would fix that; this is a design decision.
6. **Records to check:** decisions with no named author say "Decided by the WP-05 lead (Claude)".

## Known gaps, recorded for later WPs
- **Reconnect has no Admin PIN gate.** If a sign-out button is added (Settings, WP-18) with no Perch PIN stored, someone who links another account could set the Admin PIN freely. Close this before adding sign-out.
- **Sign-in after the wizard closes.** A cancelled link sign-in may still store tokens inside PlexSession, though the wizard ignores the result.
- **Wizard lockout screen:** a fifth wrong Admin PIN in the wizard returns to the step intro with "Too many tries". The countdown keypad appears only when the PIN screen is reopened.
- **PIN length:** wizard PINs are 4 digits; longer PINs come with Settings.
- **Not tested:** no Release build was compiled; the DEBUG switches are guarded by `#if DEBUG` on reading. Only the tvOS 27.2 simulator runtime is installed.
