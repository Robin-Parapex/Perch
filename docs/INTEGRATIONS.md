# INTEGRATIONS

What each backend gives us, what we call, and the traps. Exact endpoints get confirmed in each stage plan against the docs linked in `REFERENCES.md`.

## Plex Media Server (direct from app)

- **Auth:** plex.tv PIN flow (`/pins`), token per Plex Home user; switch user with `/api/v2/home/users/<id>/switch`. Store tokens in Keychain.
- **Discovery:** `/identity`, `/library/sections`, hubs (`/hubs`, `/hubs/continueWatching`), `/library/metadata/<key>` with `includeMarkers=1`, `includeChapters=1`, `includeExtras=1`.
- **Markers:** intro and credits markers come on metadata; use them for Skip and for the end-state trigger.
- **Playback:** build the decision from `Media/Part/Stream` attributes; direct play URL `/library/parts/<id>/<ts>/file.<ext>?X-Plex-Token=`; direct stream / transcode via `/video/:/transcode/universal/start.m3u8` with `directPlay`, `directStream`, `videoResolution`, `subtitles=auto|burn|sidecar`.
- **Timeline:** `/:/timeline` every 10 s during playback, plus on pause/stop, so Plex (and Tautulli) see accurate progress.
- **Themes:** series theme music at `/library/metadata/<key>/theme`.
- **Library refresh:** refresh on app start and manual refresh use `/library/sections/<id>/refresh` (or all sections). Perch never refreshes on a timer. The setup guide tells users to enable Sonarr and Radarr's Plex connection for partial scans on import.
- **Traps:** Plex Home switching needs the owner token; the app holds it in Keychain (see `DECISIONS.md`). Plex Home user PINs are used as-is and verified by plex.tv. Some debrid-mounted files report wrong duration until first play; tolerate it.

## Seerr (direct from app, `PerchSeerr`)

- Successor to Overseerr and Jellyseerr; Swagger at `/api-docs` on the instance, spec in the repo.
- **Use:** `/search`, `/discover/movies`, `/discover/tv`, `/discover/trending`, watch-provider discover (`watchProviders`, `watchRegion=GB`) for "New on <service>" rows, `/movie/<id>` and `/tv/<id>` (include `mediaInfo` for availability and request status), `/request` (create, with `seasons`), `/request/<id>/approve`, `/request/count`, `/user` for the per-profile mapping.
- **Identity:** the app signs in to Seerr with the Plex token (`POST /api/v1/auth/plex`) per profile where possible, falling back to an API key entered in setup. Requests are created as the signed-in user so Seerr's own approval rules apply. Each profile has a Seerr user; kids and teens have auto-approve off.
- **State mapping to plain words:** pending -> Requested ("Waiting for a parent" on kids' screens) ; approved or auto-approved, processing, in an arr queue -> Getting it ready ; partially available -> Some episodes ready ; available -> Ready to watch ; declined, failed, or no import within 24 hours -> Couldn't find this yet.
- **Polling:** the app polls Seerr only, and only while requests are pending: every 30 s for ten minutes, then every 2 minutes, then every 5, while the app is open (`Poller` in `MODULES.md`). Seerr marks a title available once Plex has indexed it.
- **Traps:** keep Seerr's TMDB as the single TMDB ID source. Seerr's Plex sync interval sets the floor on how fast "Ready to watch" appears.

## Sonarr, Radarr, Decypharr, Usenet (never called by the app)

- Pipeline: Seerr -> arrs -> Decypharr (Real-Debrid symlinks) or Usenet client -> Plex library.
- Perch does not talk to them. The one requirement is their built-in Plex connection (Settings > Connect > Plex Media Server) so a partial scan runs on import.
- Progress bars therefore show only what Seerr reports.
- **Traps:** debrid links expire; seeking over a cold link can stall, so prefer direct play with a healthy buffer. Mixed release quality: remember per-title audio track; let Admin flag a title for a better version.

## Home Assistant (direct from app, `PerchHome`)

- **Connection:** the app connects directly (`PerchHome`) with a long-lived access token and a single WebSocket (`subscribe_events`, `subscribe_trigger`), and shows events by role.
- **Import:** after connecting, the user chooses Areas, cameras, the doorbell entity and scenes. Nothing else is subscribed or shown.
- **Events we use:** doorbell button (your doorbell entity or Frigate `frigate/events` with `camera: doorbell`), person/parcel detections, appliance done sensors, a `perch.message` custom event for "dinner's ready" from phones, bedtime time trigger.
- **Actions we call:** `light.turn_on` with brightness/transition, `scene.turn_on`, `cover.set_cover_position`, `media_player.select_source` (amp), `lock.unlock` (parent, PIN-fresh), `notify.mobile_app_*` (request landed).
- **Playback -> HA:** Perch fires `perch.playback` events through the Home Assistant API with `profile`, `room` and `title`, so automations live in HA where you can tune them.
- **Weather:** `weather.*` entity for seasonal weather rows.
- **Traps:** scope the HA token's actions through the role allow-list applied in `PerchCore`; don't rely on HA user permissions alone.

## Frigate (events via HA, streams via go2rtc)

- **Live view:** go2rtc HLS (`/api/stream.m3u8?src=doorbell`) or WebRTC. HLS is simplest for AVPlayer; expect 2 to 4 s latency plus connection time, fine for a doorbell. Show the latest snapshot immediately and swap in live video when it opens; pre-open the stream on the first motion event so it's usually ready by the button press.
- **Address:** events come through Home Assistant; the Frigate address is used only for go2rtc streams and snapshots.
- **Events:** Frigate's HA integration exposes event sensors and MQTT events; snapshots at `/api/events/<id>/snapshot.jpg`, clips at `/api/events/<id>/clip.mp4`; GenAI descriptions in the event payload when enabled.
- **Timeline:** `/api/events?camera=&after=` for today's events in the Home tab.

## TMDB and fanart.tv (direct from app, `PerchSeerr`)

- TMDB: person details and credits, similar/recommendations, keywords for seasonal rows, watch providers by region, images (logos via `/images?include_image_language=en,null`), trailers (`/videos`, YouTube keys; we only play local trailers from Plex extras or Trailarr).
- fanart.tv: `hdmovielogo`, `hdtvlogo`, `moviebackground`, `showbackground`, `clearart`.
- Called directly with the user's keys when entered, otherwise through Seerr for TMDB data.
- Cache aggressively (24 h for metadata, 7 d for images). Respect rate limits.
- Artwork overrides: Admin can paste a ThePosterDB or MediUX image URL; the override is stored in the app and the bytes cached.

## Tautulli (direct from app, `PerchTautulli`, 2.2)

- Address and API key entered in setup (no OAuth).
- API `?cmd=`: `get_history`, `get_home_stats`, `get_user_watch_time_stats`, `get_item_watch_time_stats`, `get_users`. Map Tautulli users to profiles.
- Year in review computed in the app from history and cached.

## Trakt (direct from app, `PerchTrakt`, 1.1)

- Device OAuth code flow shown on the TV, activated on a phone.
- Scrobble from the timeline; watchlist and history sync per profile.

## Apple MusicKit (direct from app, 1.3)

- MusicKit for Swift on tvOS: `MusicAuthorization`, `MusicLibraryRequest`, `MusicCatalogSearchRequest`, `ApplicationMusicPlayer`. Needs the MusicKit capability on the App ID and the user signed into Apple Music on the Apple TV.
- Traps: background audio pauses when the app goes to background on tvOS; that's acceptable for us.

## AI (direct from app, `PerchAI`, 2.1)

- `AIProvider` protocol with two adapters: OpenAI-compatible (base URL, key, model) and Anthropic Messages (key, model). The user's key is stored in the Keychain and the model name is free text.
- Structured outputs only: one request, one structured result, no free chat.
- Guardrails: media-only system prompt; results passed through the profile's rating ceiling; permission levels 1 to 4 enforced before any tool runs; monthly budget, per-profile hourly limits, and a local call log with profile, tokens and estimated cost.
- Prompt caching for the system prompt and library summaries where the provider supports it.

## Trailers (1.0 hero, optional)

- Prefer local: Plex extras (`includeExtras=1`) or Trailarr-downloaded trailers next to the media. Play muted with AVPlayer in the hero. No YouTube embedding on tvOS.
