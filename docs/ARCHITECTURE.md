# ARCHITECTURE

The shape of the system. Detailed design happens per stage; this fixes the boundaries so stages don't fight each other.

**Read with `MODULES.md`, which wins where they differ.**

## Components

The tvOS app (`PerchApp`, with its Top Shelf extension) is the whole system. It is built from Swift packages that share `PerchCore` only:

- `PerchCore`: models, Module protocol, extension points, EventBus, Keychain store, PINs, roles, budget, pollers.
- `PerchDesign`: tokens, materials, components, focus helpers.
- `PerchPlex`: auth, Home switching and PIN verification, hubs, metadata, markers, timeline, playback decision table.
- `PerchPlayer`: AVPlayer container, overlay window, chrome; 2.0 second engine behind the same API.
- `PerchSeerr`: requests, states, discover rows, approvals, ready polling.
- `PerchHome`: Home Assistant WebSocket events, actions, scenes, role allow-list.
- `PerchFrigate`: camera streams, snapshots, event timeline.
- `PerchAI`: AIProvider protocol, adapters, budget, permission levels, feature prompts, caching.
- `PerchTrakt`: device OAuth, scrobbling, watchlist and history sync.
- `PerchTautulli`: stats, year in review.

The app talks directly to Plex, plex.tv, Seerr, Trakt, Home Assistant (WebSocket), Frigate (streams and snapshots only), Tautulli, TMDB and fanart.tv (directly, or through Seerr), MusicKit, and the user's chosen AI provider. There is no proxy, no Hub and no server of ours in the app's data path. Keys live in the device Keychain and roles and budgets are enforced by `PerchCore`.

## What we run

The only server we run is the optional feedback endpoint described in `SPEC.md` 1c. The app never depends on it.

## The app

**Pattern:** SwiftUI + `@Observable` view models, one `Feature` folder per screen family, services injected through the environment. No third-party architecture frameworks.

**Services (protocols, so they can be faked in tests):**
- `PlexService`: auth, libraries, hubs, metadata, markers, playback decision, timeline reporting.
- `ReadyWatcher` (a `Poller` in `PerchSeerr`): polls Seerr for request state changes while requests are pending -> `EventBus`.
- `HAService`: calls Home Assistant directly through `PerchHome`.
- `TraktService`: device OAuth, scrobbling, watchlist and history sync through `PerchTrakt`.
- `MusicService`: MusicKit.
- `ArtworkService`: resolves poster/logo/backdrop (override -> fanart.tv -> TMDB -> Plex) with Nuke caching and pre-warming for the next row.
- `PlaybackCoordinator`: owns the player, applies the decision logic, emits `PlayerHook` events consumed by `PerchHome`, shows "Couldn't play this" with "Try again".

**Cross-cutting:**
- `EventBus` for overlays: doorbell, notices, "ready" toasts. The overlay host lives in a **dedicated `UIWindow` at a higher window level** than the main window, so it draws above everything including the player. The player itself (`AVPlayerViewController`) is embedded in our own full-screen container view controller rather than presented modally, so focus can be handed to and from the overlay window cleanly.
- `FocusCoordinator`: restores focus on Back, remembers row/item per screen.
- `ProfileSession`: current profile, role, PIN state, rating ceiling, DND state.
- `DeepLinkRouter`: `perch://title/<ratingKey>`, `perch://play/<ratingKey>`, `perch://home`, used by Top Shelf and HA automations.

**Playback decision table (native engine, 1.x).** Inspect the Plex media part (container, video codec and profile, audio codec, subtitle format) and apply the first matching row per dimension. Terms: *direct play* = the file as-is; *direct stream* = Plex remuxes to HLS without re-encoding video; *audio transcode* = direct stream plus audio re-encoded to EAC3; *transcode* = video re-encoded. Log every decision with the reason.

| Dimension | Case | Expected outcome |
|---|---|---|
| Container | MP4, MOV, M4V | direct play possible |
| Container | MKV, AVI, TS, WMV | direct stream (Apple's player cannot open these) |
| Video | H.264 (any level the Apple TV 4K supports), HEVC SDR, HEVC HDR10, HEVC HDR10+ (native on the 3rd generation Apple TV 4K; plays as HDR10 on older models) | direct play or direct stream per container |
| Video | HEVC Dolby Vision profile 5 or 8.1 | direct play or direct stream; keep DV metadata, request DV display mode |
| Video | HEVC Dolby Vision profile 7 (Blu-ray remux) | direct stream as HDR10 base layer; label as HDR10 in the debug overlay |
| Video | AV1, VP9, MPEG-2, VC-1 | transcode (no hardware decode on Apple TV 4K) |
| Audio | AAC, AC3, EAC3, EAC3-JOC (Atmos) | pass through |
| Audio | TrueHD (incl. Atmos), DTS, DTS-HD, DTS:X, FLAC, PCM, Opus | audio transcode to EAC3 5.1 (Atmos is lost for TrueHD Atmos; note it in the debug overlay). 2.0's second engine lifts this. |
| Subtitles | None | direct play possible |
| Subtitles | Text (SRT, ASS/SSA, WebVTT), embedded or external | direct stream: Plex converts the track to WebVTT inside the HLS stream and the player shows it natively (ASS styling is lost). AVPlayer cannot attach an external SRT to a progressive file, so selecting any text subtitle moves a direct-play item to direct stream |
| Subtitles | PGS, VOBSUB, DVB (image) | offer the track but warn "needs re-encoding"; selecting it forces a transcode with burn-in. Default off. 2.0's second engine lifts this. |
| Resolution | 4K source and the chosen path would downscale (for example burn-in on a weak server) | prefer turning the subtitle off and telling the user over downscaling |

Frame-rate and dynamic-range matching: set `AVPlayerViewController.appliesPreferredDisplayCriteriaAutomatically = false` and set `AVDisplayManager.preferredDisplayCriteria` from the media's frame rate and dynamic range before playback begins, so the Apple TV switches once, not mid-stream. Matching only takes effect when Match Content (frame rate and dynamic range) is enabled in the Apple TV's own video settings; the setup guide says so.

## Data

- Watch state, progress, ratings ceiling: **Plex** (source of truth).
- Requests and states: **Seerr**, cached in the app.
- Profiles, roles, rooms, row config, custom collections, artwork overrides, per-title memory (audio/sub/offset), audit log, AI spend: the app's settings document and local store (per-person data keyed by Plex user ID). Keys are kept separately in the Keychain.
- **Rating ceilings** use the BBFC scale (U, PG, 12, 12A, 15, 18). Ceilings come from each Plex Home user's content restrictions, mirrored to a BBFC scale in the app. The app maps TMDB GB certifications to the same scale for discover, recommendation, seasonal and AI results; unknown certificate = treated as 15.
- App-local: last profile, UI prefs, image cache. Nothing that would be lost badly if the Apple TV was reset.

## Security

- The app reaches Plex over the LAN or the plex.tv relay. Other services are reached at the addresses the user enters.
- Keys are stored in the Keychain, never in UserDefaults or iCloud, and never logged.
- Plex Home PINs are verified by plex.tv; nothing is stored on the device. The Admin PIN works as described in `MODULES.md`.
- Door and alarm actions require the Admin PIN entered in the last 5 minutes. They are logged on the device in a local audit log.
- AI prompts never include tokens or home entity IDs beyond what the role may act on; results are filtered before the model sees them.

## Testing

- Unit: playback decision table, permission matrix (role x action x room), request state mapping, seasonal calendar, recommendation merge, polling policy backoff.
- UI smoke: focus and Back on each screen; run on hardware before each TestFlight.
- A fixture Plex library of ~15 items covering the decision table lives on the server for repeatable playback tests: MP4 H.264 1080p; MKV HEVC HDR10 EAC3; MKV HEVC DV 8.1 EAC3-JOC; MKV HEVC DV 7 TrueHD Atmos; MKV H.264 DTS-HD; MKV with PGS subtitles; MKV with ASS subtitles; MP4 AAC with SRT sidecar; an 80 Mbit/s 4K sample; one file from the Real-Debrid mount; one AV1 file; one 4:3 SD MPEG-2 file.
- App Transport Security: users type plain-HTTP addresses for Plex, Seerr, Home Assistant, Frigate and local AI servers, so this private build sets `NSAllowsArbitraryLoads` (a public release would need HTTPS guidance or per-host exceptions instead). Info.plist carries `NSLocalNetworkUsageDescription`, because Apple documents the key for tvOS 14 and later; the real prompt behaviour on tvOS 26 is still to be checked on the Apple TV. Export compliance: set `ITSAppUsesNonExemptEncryption` to NO so TestFlight uploads don't wait on a questionnaire.

## Observability

- An in-app debug overlay (Admin PIN) showing the current playback decision, bitrate, dropped frames and engine, plus the local playback log and module status badges. Nothing leaves the house.
