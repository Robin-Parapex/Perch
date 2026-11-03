# WP-05 Setup wizard and profile picker: plan

## Context
WP-05 ends 0.1.0 (ROADMAP:49, acceptance :53-54). WP-04 gave the Plex client and plain DEBUG sign-in screens. WP-05 gives the real first run: a step wizard, the Admin PIN step, profiles and roles, "coming soon" steps, and an Apple TV style profile picker with the leave-kids-profile PIN rule.

**Status:** Robin asked on 2 Nov 2026, going to bed, for the next stages to be pushed through overnight using the reference repos for inspiration without copying code. That stands in for plan approval; he reviews in the morning. Branch `wp-05-setup-wizard`, stacked on the local `wp-04-plex-signin` tip (ad4ece0, not yet pushed). Nothing is pushed, no PR, no version bump or tag (0.1.0 release steps are left for Robin).

## Decisions (recorded in DECISIONS.md)
1. **Root routing derived from state** (after Dusk ContentView, MIT): `AppRoot` shows the wizard until setup is complete, then the profile picker when no profile resumes, otherwise the placeholder home. Setup-complete is an app-local flag in App Group defaults (`perch.setupComplete`), next to `plex.lastProfileID`; no SettingsDocument schema change.
2. **Steps:** Welcome, Connect Plex (code, or address and token), Choose server (only when more than one), Admin PIN, Profiles and roles, Add later (one screen listing Requests, Library refresh, Trakt, Home Assistant, Tautulli and AI as "Coming soon"; writes nothing), Done. Connect Plex and Admin PIN cannot be skipped; every other step has "Skip for now".
3. **Step logic is pure and tested** in PerchCore (`Setup/SetupProgress.swift`): order, which steps apply, can-skip, can-finish (refuses while the Admin PIN source is `.setupRequired` or `.unavailable`).
4. **Admin PIN step:** owner has a Plex PIN: "Use your Plex PIN" (primary) or "Set a Perch PIN" (verify the Plex PIN first, as `setPerchPIN` requires). Owner has none: a Perch PIN must be set, entered twice. Wizard PINs are 4 digits (PINPolicy allows 4 to 8; longer PINs come with Settings). Source `.unavailable` (plex.tv not reached yet) shows a wait and Try again, never a way past.
5. **Profiles and roles:** Home users with role and rating ceiling; roles change freely, ceilings only downwards (`setCeilingOverride`), kids default to PIN-to-exit. Edits go through the Authoriser with the fresh Admin PIN from step 4.
6. **Profile switching rule in PerchCore** (`Profiles/ProfileSwitchPolicy.swift`), not in the UI: from a kid with `pinRequiredToExit` to a non-kid, require the target adult's Plex PIN, or the Admin PIN when that adult has none; otherwise a protected target needs its own Plex PIN; else none. The app's `ProfileSwitcher` asks the policy first and then calls AdminPIN or `PlexSession.switchProfile`, so no screen can bypass it.
7. **Offline picker:** PlexSession keeps the last Home user list (non-secret fields only: id, name, thumb URL, protected, restricted, admin) in App Group defaults, so locked profiles still show when plex.tv is down.
8. **Picker look** (DESIGN:43, Apple TV app, Dusk HomeUserPicker for structure): centred row of 200 pt round avatars, name beneath, focused scale 1.1 with soft glow, lock glyph on protected profiles, current profile marked; PIN entry as a two-column screen (avatar and name left, keypad right, after Dusk). Avatars use `AsyncImage` from the Plex thumb with an initials fallback (Nuke is WP-08).
9. **Wizard look** (DESIGN:52): one question per screen, centred column, progress dots top-right, one white primary, "Skip for now" secondary, helper line under fields. Steps crossfade and slide 24 pt with the PerchMotion spring; Reduce Motion gives crossfades only. Background is the base colour with a slow, soft glass gradient; library artwork backdrops wait for the artwork pipeline (WP-08).
10. **Back:** Back goes to the previous step; at Welcome it leaves the app (top level). In the picker Back keeps the current profile; with no current profile there is nowhere to go back to.
11. **Re-run setup:** a "Run setup again" button on the placeholder home, behind the Admin PIN through the Authoriser, until Settings exists (WP-18).
12. **DEBUG fake household:** launch argument `-PerchFakeHousehold` swaps in a canned plex.tv and server transport (owner with PIN, a protected adult, a kid, one server), so the whole flow runs in UI tests and screenshots without Robin's account. DEBUG only; the fake PIN is fixed in the fake.
13. **Out of scope, recorded:** local network discovery (Bonjour `_plexmediasvr._tcp` or GDM) and a QR code on the link screen; both need a check on tvOS and add little while sign-in already uses plex.tv. The WP-04 debug sign-in screens are replaced by the wizard and removed; the fault switches stay.

## Changes after the Opus critic pass (these override the decisions above)
- **C1. Two fake households:** `-PerchFakeHousehold withPINs` (owner with PIN, protected adult, kid) and `-PerchFakeHousehold noPINs` (owner without PIN, adult without PIN, kid), so "refuses to finish without an Admin PIN" and "leaving a kid asks for a PIN when adults have none" are both shown.
- **C2. Leave-kid rule keys on `role == .kid`** (SPEC:56, MODULES:66: always), not on `pinRequiredToExit`. Tested incl. a profile changed to kid in step 5.
- **C3. One switching route:** `PlexSession.switchProfile` becomes internal behind a public `switchProfile(to:pin:policyApproved:)`-style entry that requires the PerchCore policy decision (or PlexSession takes the policy), so no view can switch without it; the WP-04 debug view goes. Tested.
- **C4. "From" profile when nothing resumed:** the policy uses the stored `plex.lastProfileID` role, so a kid last on the TV cannot pick an adult freely after a failed resume. Tested.
- **C5. Admin PIN step always verifies:** both routes call `AdminPIN.verify` (Use your Plex PIN: enter it once; Perch PIN: verify Plex PIN if the owner has one, then set and confirm). New PerchCore `CoreAction` for setup edits and re-run (parent only, fresh Admin PIN), with a kid-denied test.
- **C6. Re-run:** `setupComplete` stays true during a re-run until Done; Back at Welcome during a re-run returns home.
- **C7. Offline:** switching needs plex.tv; offline the current profile stays and the picker says "Can't switch profiles right now". Avatars are cached to disk (small app cache) so they do not pop in. Tested.
- **C8. Lockout shown twice:** Admin PIN lockout in the wizard, and profile PIN lockout from a kid profile.
- **C9. Look:** no gradient background (DESIGN:8). From Choose server on, the background is real library art from the connected server (fetched with the token in a header, never in a URL), blurred and dimmed, with staged entrances; the fake households use bundled sample art. The PIN screen is centred (avatar, name, dots, keypad in one column). One Opus critic pass on the simulator screenshots against DESIGN and the Apple TV app before done.
- **C10. Steps registered by modules:** the "Add later" screen lists module-registered entries so later WPs plug in. Connect Plex confirms with server name and library count; the Admin PIN step explains what it protects (SPEC:23-24).
- **For Robin (not decided overnight):** Settings > Integrations does not exist yet, so the Admin PIN gate is shown on the re-run entry; network scanning stays out of WP-05 (his call: Bonjour `_plexmediasvr._tcp` is the low-risk route); 0.1.0 release needs TestFlight, which conflicts with simulator-only for now.

## Slices (helpers, one owner per file)
- **A, core and Plex** (builder + tester): `SetupProgress`, `ProfileSwitchPolicy`, setup-complete key, Home user list persistence in PlexSession; tests incl. "Admin refuses a kid session even with the right PIN" if not already present.
- **B, design** (builder, parallel with A): `SetupStepContainer`, `ProgressDots`, `ProfileAvatar`, two-column PIN layout, field style, step transition modifier with Reduce Motion variant.
- **C, app** (builder, after A and B): fake household transport, `AppRoot`, setup screens, picker, `ProfileSwitcher`, re-run entry, removal of the debug screens, UI tests on the 3rd-generation simulator.
- Then verifier gate, one Opus reviewer pass, fixes, scribe for CHANGELOG and DECISIONS, simulator screenshots of each screen.

## Verification
- `scripts/gate.sh` GATE PASS; no new warnings; UI tests on the separate 3rd-generation simulator, never Robin's live one (C6E85DCA holds his sign-in).
- Acceptance (ROADMAP:53-54), shown with the fake household in UI tests and screenshots:
  1. Wizard completes with Plex only; refuses to finish without an Admin PIN.
  2. Picker shows the household; a protected profile asks for its PIN (verified by the session, fake plex.tv).
  3. Leaving a kid profile asks for a PIN even when the adult has none (Admin PIN).
  4. Admin PIN gates the re-run entry; Admin refuses a kid session even with the right PIN (test).
  5. Five wrong attempts lock out.
- Not done overnight, for Robin: the same walk-through with his real account on the live simulator, the on-device check, push, PR, and the 0.1.0 release steps.
