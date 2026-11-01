# MODULES

How Perch stays modular, works with nothing but a Plex server, and lets a household add integrations (including bring-your-own-key AI) with no server of ours. **There is no self-hosted component.** Everything runs in the app. This doc overrides anything in `ARCHITECTURE.md` that mentions a proxy or Hub.

## Two tiers

| Tier | What's needed | What you get |
|---|---|---|
| **0. Plex only** | A Plex server and this app | Browse, play, profiles from Plex Home with Plex PINs, custom collections and per-title memory on the device |
| **1. Integrations** | Keys entered in the app (setup wizard or Settings) | Seerr requests, Trakt, Home Assistant and Frigate, Tautulli stats, AI features with your own provider. Keys in the device Keychain. Roles and budgets enforced on the device. |

**Setup wizard** (`SPEC.md` 1a) configures tier 0 on first run and offers each tier 1 module as a skippable step; every step can be re-run from Settings. **Home Assistant imports only what the user picks** (Areas, cameras, doorbell entity, scenes); Frigate events arrive through Home Assistant and only streams and snapshots use the Frigate address directly.

## Module contract

Each integration is a Swift package exposing one `Module`:

```
protocol Module {
  static var id: ModuleID { get }            // "seerr", "homeassistant", "ai", ...
  var status: ModuleStatus { get }           // notConfigured, ok, degraded(reason), error(reason)
  func settings() -> any View                // its settings page (Admin PIN gated)
  func testConnection() async -> TestResult
  func contributions() -> [Contribution]     // what it adds to the app
  func requiredRole(for action: ActionID) -> Role   // permissions it declares
}
```

**Extension points** (the only ways a module touches the UI):
- `RowProvider`: rows for Home, title pages, person pages (position hints, per-profile on/off).
- `TitleActionProvider`: buttons on a title page (Request, Is this OK for the kids?).
- `SearchProvider`: a results section in Search and Ask.
- `OverlayProvider`: full overlays and corner notices through the `EventBus`.
- `EventSource`: streams events (doorbell, request ready).
- `PlayerHook`: play, pause, credits, stop, failure.
- `SettingsPage` and `AdminPanel` sections.
- `Poller`: a periodic job with an interval and a "while app is active" flag (replaces webhooks).

The app shell (`PerchApp`) composes enabled modules at launch. Adding a feature means adding a module or extending one; the shell, the player and the design system don't change.

## Packages

```
PerchCore       models, Module protocol, extension points, EventBus, Keychain store, PINs, roles, budget, pollers
PerchDesign     tokens, materials, components, focus helpers
PerchPlex       auth, Home switching and PIN verification, hubs, metadata, markers, timeline, playback decision table
PerchPlayer     AVPlayer container, overlay window, chrome; 2.0 second engine behind the same API
PerchSeerr      requests, states, discover rows, approvals, ready polling
PerchHome       Home Assistant: WebSocket events, actions, scenes, role allow-list
PerchFrigate    camera streams, snapshots, event timeline (via Home Assistant or direct)
PerchAI         AIProvider protocol, adapters, budget, permission levels, feature prompts, caching
PerchTrakt      device OAuth, scrobbling, watchlist and history sync
PerchTautulli   stats, year in review
PerchApp        the tvOS app target, Top Shelf extension
```

Every package has tests against a fake backend. No package imports another's internals; they share `PerchCore` only.

## PINs and roles

Two PINs, both familiar to Plex users:

1. **Profile PINs are Plex Home PINs.** Switching to a profile calls plex.tv's Home user switch with that profile's PIN; plex.tv verifies it. PINs are never stored. Profiles without a Plex PIN switch freely, **except that leaving a kids' profile always needs a PIN**: the chosen adult's Plex PIN if they have one, otherwise the Admin PIN.
2. **Admin PIN** gates Settings > Integrations, AI, Profiles and roles, Admin (which also needs the parent role), plus door and alarm actions. **Default: the Plex account owner's Home PIN**, verified by plex.tv (nothing stored). **If the owner has no Plex PIN, the wizard requires a Perch PIN**: app-specific, hashed with PBKDF2, kept in the Keychain. The Perch PIN can also be set as an override at any time. The Admin PIN can never be empty. Five failed attempts, then a 60 s lockout that doubles.

**Tokens:** the owner's Plex token and the token of each Plex Home user that has been switched to are kept in the Keychain (per-user tokens are what give per-user watch state). Relaunch resumes the last profile without a PIN; switching to any PIN-protected profile always asks. PINs themselves are never stored.

Plex PIN verification needs plex.tv; if it's unreachable, the current profile stays, PIN-protected switches are locked, and the app says so. A Perch PIN works offline.

**Roles** default from Plex Home: account owner and any unrestricted Home user -> parent; restricted Home users -> kid; teen only by assignment in Admin. Editable behind the Admin PIN. `PerchCore` enforces the matrix in `PERMISSIONS.md` on the device.

**Rating ceilings:** Plex is the source of truth. Each Home user's Plex restriction profile maps to a BBFC ceiling (table in `PERMISSIONS.md`); Admin can lower a profile's ceiling further, never raise it. The ceiling filters discover, recommendation, seasonal and AI results; Plex itself filters the library.

## Keys and settings

- Keys live in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), never UserDefaults, never iCloud, never logged. Shown as `sk-…a1b2` after saving.
- Home Assistant uses a long-lived access token; the settings page recommends a dedicated Home Assistant user limited to the entities Perch needs.
- Config export (for a second Apple TV) excludes keys. Optional iCloud sync of settings without keys is a later minor version.

## Without a server: what changes

- **Ready detection polls Seerr only**, and only while a request is in Requested or Getting it ready: 30 s intervals for the first ten minutes after a request, then 2 minutes, then 5, one small call each, only while the app is open. Perch never scans Plex on a timer; Sonarr and Radarr's own Plex connection triggers the partial scan on import. Optional safety net in Admin (off by default): refresh the matching library once if a title has been Getting it ready for 15 minutes.
- **Plex-only households** (no Seerr): no polling at all. Settings offer refresh on app start (off / all / chosen libraries) and manual refresh.
- **No automatic repair.** A failed stream shows "Couldn't play this" with "Try again" (re-request through Seerr, parents only).
- **No audit server.** Privileged actions are logged on the device, visible in Admin.
- **Feedback** goes to the Perch feedback endpoint when it exists, else a QR to a pre-filled GitHub issue, else a user webhook. Nothing else ever talks to a server of ours.
- **Multiple Apple TVs:** single device for now; the settings document, keys kept separate and per-person data keyed by Plex user ID make iCloud sync a later minor version, not a rewrite.

## AI module

**Provider-agnostic, bring your own key.** `AIProvider` protocol with two adapters:
- **OpenAI-compatible:** base URL, API key, model name. Covers OpenAI, OpenRouter (`https://openrouter.ai/api/v1`), Groq, Mistral, Ollama and LM Studio on the LAN, and most others.
- **Anthropic Messages:** API key, model name.

Model is free text with a suggestion list per provider that leads with **free and cheap models** (OpenRouter's free tier first); frontier models are not needed for any Perch feature. A Test button sends a one-token request and shows latency and the reply. Adding a provider later is one adapter file.

**Features, grouped by cost:**
- **Daily batch, cached per profile** (pennies): For you tonight, weekly digest, auto-collections, seasonal blurbs, Who's who guides.
- **On demand, small** (a few hundred tokens): Ask, Who's that? (subtitles trimmed to the last few minutes), Is this OK for the kids?, Previously on, Movie night picker, Smart requests.
- **No free chat.** Every feature is one request with a structured result; there is no conversation mode.

**Guardrails:** media-only system prompt; structured output (title IDs, filters, one-line reasons) parsed by Perch, never shown as prose; off-topic input gets "I can only help with what to watch"; no automatic retries; subtitles and history trimmed to what the feature needs.

**Who may use it:** parents by default; a toggle in Admin enables teens (rating-limited); never kids.

**Permission levels** per profile (Admin): 1 Recommend only (default), 2 Can request (Seerr, subject to approval rules), 3 Can navigate (open title, play, switch tab), 4 Home actions (parents only, off by default, 2.3).

**Controls (Admin PIN):** per-feature toggles; a monthly request budget with an estimated cost from the provider's published price when known; per-profile hourly limits; local call log (feature, profile, tokens, estimated cost) in Admin. When the budget is exhausted: "Ask is taking a break until next month".

## Release shape (future)

Tier 0 plus tier 1 is a releasable app: "Perch for Plex" with optional connections, every key entered by the user, no service of ours in the loop. See `DECISIONS.md` for the release constraints (Plex trademark rules, licence checks on the second engine).
