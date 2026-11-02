# WP-04 PerchPlex sign-in: plan

## Context
WP-04 is the fourth of five WPs in 0.1.0 (ROADMAP:48). PerchPlex is a stub. WP-05 (wizard and profile picker) needs a working Plex sign-in underneath it: link code, manual address, server choice, Home users with restriction profiles, PIN-checked switching, tokens in the Keychain, resume on relaunch, and clear unreachable states. WP-04 delivers that client plus plain screens to exercise it on the Apple TV. Wizard styling and the real profile picker stay in WP-05.

**Status:** planned in a cloud session (no Swift toolchain there); building continues locally on the Mac.

Branch `wp-04-plex-signin` from `main`, commits `feat(WP-04): ...`, one draft PR. Not stacked on WP-03 (still draft PR #4): sign-in screens use native SwiftUI controls only, so no PerchDesign dependency; WP-05 restyles them. If WP-03 merges first I rebase (expected conflict only in `PlaceholderView`).

## Decisions I am taking (recorded in DECISIONS.md)
1. **Link flow = short code** at plex.tv/link (non-strong `POST /api/v2/pins`), as ROADMAP says. Poll `GET /api/v2/pins/{id}` every 2 s; new code automatically on expiry. No QR in WP-04.
2. **Endpoints** (Dusk `marvinvr/dusk-player`, MIT, confirmed against python-plexapi): `GET /api/v2/user` (validate token), `GET /api/v2/home/users`, legacy `POST /api/home/users/{id}/switch?pin=` with the owner token, `GET clients.plex.tv/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1`, server `/identity` and `/library/sections`. JSON everywhere (`Accept: application/json`); switch response accepts `authToken` or `authenticationToken`.
3. **Wrong PIN = 401/403 on a protected user**; transport errors and timeouts = unreachable, never a failed attempt.
4. **Profile PIN lockout** reuses `PINLockout` (5 tries, 60 s doubling to 1 h), one lockout for profile switching, stored under `plex.profilePINLockout` in App Group defaults. Owner PIN for Admin keeps AdminPIN's own lockout.
5. **Token storage:** owner account token in `SecretKey.plexOwnerToken`; each switched profile's account token in `plexUserToken(id)`; each profile's server access token in `SecretKey.module("plex", "server.<userID>")` so relaunch works when plex.tv is down. Client identifier (not secret) in App Group defaults `plex.clientIdentifier`. Last profile ID in defaults `plex.lastProfileID` (ARCHITECTURE:72).
6. **Server choice** (machine ID, name, last good URI, manual URL) in `settings.modules["plex"].config`, non-secret keys only (passes `validate()`).
7. **Connection choice:** probe `/identity` concurrently; local beats remote beats relay, 1.5 s grace for a better tier; timeouts 5 s local, 8 s remote (idea from Dusk ServerProbe). Last good URI tried first. Manual servers are checked by `machineIdentifier` (Dusk does not; we do).
8. **Manual route:** address (IP or host, optional scheme, default port 32400, IPv6 in brackets) plus token. Token stored as the owner token; Home users and switching then work if it is an account token, otherwise the app runs as one profile and says profile switching is unavailable.
9. **Profiles sync to the settings document:** new Home users get `ProfileSettings.defaults` (owner/unrestricted parent, restricted kid); existing entries keep roles and overrides, but `plexRestriction` is refreshed from Plex (source of truth). Unknown `restrictionProfile` with `restricted == true` becomes `.custom([])`, which maps to U (fail closed). `household.ownerPlexUserID` set from `/api/v2/user`. `AdminPIN.setOwnerHasPlexPIN` set from the owner's Home user `protected` flag.
10. **Owner PIN verifier** built before `AdminPIN` in `CoreServices` (it reads the token at call time, so no PerchCore change).
11. **Unreachable wording** (GLOSSARY: "Profile", no jargon outside setup): signed-in screens say "Can't reach your library right now" with Try again; plex.tv down says "Profile PINs can't be checked right now", current profile stays, PIN-protected switches locked. "Plex" appears only in the sign-in screens (setup context).
12. **Screens live in the app target**, debug-reachable from the placeholder ("Plex sign-in" button) and launch argument `-PerchPlexSignIn`. PerchPlex stays UI-free apart from its `Module` conformance.

## Files
**Packages/PerchPlex/Sources/PerchPlex/**
- `Networking/PlexHTTP.swift`: `PlexTransport` protocol (`send(URLRequest) async throws -> (Data, HTTPURLResponse)`), `URLSessionTransport` (15 s timeout, no cache), `PlexError` (`notSignedIn`, `plexTVUnreachable`, `serverUnreachable`, `unauthorized`, `pinIncorrect`, `pinRequired`, `lockedOut(until:)`, `linkExpired`, `http(Int)`, `decoding`, `serverMismatch`).
- `Networking/PlexClientIdentity.swift`: `X-Plex-*` headers (Product Perch, Platform tvOS, Device Apple TV, Version from bundle, client ID kept in defaults).
- `Networking/PlexEndpoints.swift`: pure request builders, tokens only in `X-Plex-Token` headers, never in logged URLs.
- `Models/`: `PlexPin`, `PlexAccount`, `PlexHomeUser` (+ `restriction: PlexRestriction`, `displayName`), `PlexResource`/`PlexConnection` (+ tier sort), `PlexServerIdentity`, `PlexLibrarySummary` (section count for the confirmation line).
- `Auth/PlexLinkFlow.swift`: `AsyncStream<LinkState>` (`code(String, expiresAt)`, `linked(token)`, `failed(PlexError)`).
- `Auth/PlexSession.swift`: the one actor that holds tokens (per reference-review "keep token handling in one actor"): `signIn(accountToken:)`, `signInManually(address:token:)`, `homeUsers()`, `switchProfile(to:pin:)` (commit only on success, after Dusk), `resume()`, `signOut()`, `state` stream (`signedOut`, `connecting`, `ready(profile, server)`, `serverUnreachable`, plus `profileSwitchingAvailable` flag).
- `Auth/PlexOwnerPINVerifier.swift`: `PlexPINVerifying` via the switch endpoint for the owner; discards the token.
- `Servers/ServerDiscovery.swift`, `Servers/ConnectionProber.swift`, `Servers/ServerAddress.swift` (parser).
- `Profiles/ProfileSync.swift`: Home users -> settings document (decision 9).
- `PlexModule.swift`: `Module` conformance (`id "plex"`, status from session, `testConnection` = `/identity`, no contributions yet).
- `Package.swift`: add `resources: [.process("Fixtures")]` to the test target.

**Tests** (`Packages/PerchPlex/Tests/PerchPlexTests/`, Swift Testing, fake transport serving JSON fixtures written from the documented shapes): link flow (code, linked, expiry renews, unreachable), header set, address parsing table, connection tier ordering and grace, manual `machineIdentifier` mismatch, Home user decoding incl. restriction mapping and `id` as string or int, switch (success commits, wrong PIN does not, unreachable is not an attempt, lockout after 5), owner verifier true/false/throws, profile sync keeps edits and refreshes restriction, resume with plex.tv down uses cached server token, no token ever in a URL.

**PerchApp**
- `CoreServices.swift`: build `PlexSession` and verifier, pass verifier to `AdminPIN`, register `PlexModule`.
- `Features/PlexSignIn/`: `PlexSignInView` (two choices), `PlexLinkCodeView` (large code, "On your phone, go to plex.tv/link and enter this code"), `PlexAddressView` (native `TextField`s and `SecureField` so the iPhone keyboard prompt works), `PlexServerPickerView` (name, "This home" / "Away" label, confirms "Connected to <name>, <n> libraries"), `PlexProfilesDebugView` (Home users, role and ceiling shown, PIN entry, resume shows last profile), `ConnectionNotice` (the two unreachable states with Try again).
- `PerchMain.swift`, `Features/Placeholder/PlaceholderView.swift`: debug entry and `resume()` on launch.
- `PerchUITests`: launch with `-PerchPlexSignIn`, sign-in choices visible and focusable, Back returns.

**Docs:** `CHANGELOG.md` Unreleased, `DECISIONS.md` (above), `THIRD_PARTY_NOTICES.md` (Dusk MIT notice: ideas only, kept for the one-line source comments), `docs/notes/wp-04-plan.md`.

## Build order (helpers)
1. builder A: networking, models, address parser, endpoints. tester alongside: fixtures and model/parser/header tests.
2. builder B: link flow, session, switching, verifier, profile sync, discovery and prober. tester: flow and session tests.
3. builder C: app screens, CoreServices wiring, UI test.
4. reviewer (Opus) on the full diff, focused on Swift 6 concurrency and compile risk since nothing can be compiled here; I fix findings. scribe: CHANGELOG, DECISIONS, notices.

## Verification
- Reviewer pass on the full diff before the PR.
- **Robin on the Mac:** `scripts/gate.sh` green (xcodegen drift, all package tests, UI test). Send me any build errors.
- **On the Apple TV 4K (Debug over network), acceptance list for the PR:**
  1. Sign in with code at plex.tv/link on the phone; app moves on by itself.
  2. Manual address plus token connects; wrong token says so; wrong address says can't reach.
  3. Several servers: picker shows them; one server: chosen automatically.
  4. Home users listed with the right role and ceiling (kid profile shows U or PG as Plex says).
  5. Wrong profile PIN refused, right one switches; five wrong lock for 60 s.
  6. Quit and relaunch: last profile resumes with no PIN.
  7. Server off: "Can't reach your library right now", Try again works when it is back.
  8. Wi-Fi to WAN blocked (plex.tv down, LAN up): current profile keeps playing, PIN switches locked with the message.
  9. Admin PIN with the owner's Plex PIN works (AdminPIN verifier wired).
- Then push and open the draft PR.
