# REFERENCES

Where to look before building something. Grouped by what you're trying to learn. Items marked *(unverified)* were not confirmed by a live fetch when this pack was written; check the URL before relying on it.

## Design inspiration (10-foot UI)

- **Apple Human Interface Guidelines: Designing for tvOS** https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos *(standard HIG path)*. Also **Focus and selection** `.../focus-and-selection` and **Top Shelf** `.../top-shelf`. The baseline for every screen.
- **The Apple TV app itself** (tvOS 26). Study: hero cards with logos, the info panel in the player, Up Next behaviour, how little chrome there is. This is the look we are matching.
- **WWDC25: "Build a SwiftUI app with the new design" (session 323)** https://developer.apple.com/videos/play/wwdc2025/323/ and **"What's new in SwiftUI" (session 256)** https://developer.apple.com/videos/play/wwdc2025/256/ . Liquid Glass and material behaviour, sidebar-adaptable tab views. Also search WWDC25 for "Meet Liquid Glass", and earlier sessions "Build SwiftUI apps for tvOS" (WWDC20) for the focus engine. The Apple TV app has used a collapsible sidebar since tvOS 17.2; match that.
- **Infuse 8 by Firecore** https://apps.apple.com/app/infuse-video-player/id1136220934 . The closest third-party app to Apple polish: artwork handling, logo use, player chrome, library grids. Closed source; design reference only.
- **Plex "new experience" preview on Apple TV** and its forum feedback. A reference for what *not* to do: top nav that adds clicks, inconsistent Back, slow poster loading. Forum threads are listed in `DECISIONS.md` under "Lessons from Plex".
- **Netflix and Disney+ on Apple TV** for the end-of-episode countdown, the shrink-at-credits pattern, and profile pickers.

## Code inspiration (open source)

- **Dusk for Plex** https://github.com/marvinvr/dusk-player (wiki: `/wiki`; App Store https://apps.apple.com/gb/app/dusk-for-plex/id6760492635 ). Native Swift/SwiftUI Plex client for iOS, tvOS and macOS, **MIT**, one developer, active in 2026. Player is VLCKit (TVVLCKit, LGPL-2.1); TrueHD decoding needs a custom VLCKit build from a private repo, the public build routes TrueHD through Plex; includes a Rust converter that rewrites Dolby Vision profile 7 to 8.1 on the fly. Already has Plex Home, Seerr requests, Top Shelf, downloads, AirPlay, SharePlay. **The closest thing to Perch's 1.x and the primary code reference** for Plex auth, Home switching, hubs, markers, Seerr wiring and the 2.0 engine. Read the whole repo before planning 0.1. Note: TrueHD and DTS are decoded to multichannel PCM on the Apple TV; the platform cannot bitstream them, so Atmos in TrueHD is lost on any app.
- **Swiftfin** https://github.com/jellyfin/Swiftfin . Native Swift/SwiftUI Jellyfin client for iOS and tvOS (MPL-2.0 *(unverified)*). The best reference for a SwiftUI tvOS media app: focus handling, poster rows, player wrapping, settings. Read its tvOS target before planning 0.1.
- **Plezy** https://github.com/edde746/plezy . Flutter, GPL-3.0. Reference for *behaviour* (how it talks to Plex, markers, Plex Home switching, Seerr Explore rows, Top Shelf), not for code we copy. GPL: read, don't paste.
- **Plex Swift packages:** PlexKit https://github.com/lcharlick/PlexKit and plexswift https://github.com/LukasParke/plexswift (OpenAPI-generated) *(maintenance and licences unverified)*. Evaluate in the 0.1 plan; a thin client of our own may be simpler.
- **Home Assistant:** HAKit https://github.com/home-assistant/HAKit (Swift WebSocket/REST library used by the companion app) and the companion app https://github.com/home-assistant/iOS ; architecture notes https://developers.home-assistant.io/docs/apple/architecture . HAKit shows the event subscription patterns `PerchHome` needs.
- **TMDb Swift package** https://github.com/adamayoung/TMDb *(MIT, unverified)*. Useful if the app ever calls TMDB directly; otherwise a reference for models.
- **Nuke** https://github.com/kean/Nuke . MIT. Image loading, caching, prefetching; supports tvOS.
- **Players for 2.0:** KSPlayer https://github.com/kingslay/KSPlayer (Swift, FFmpeg and AVPlayer backends; licence believed GPL-3.0 with a paid commercial option, check before adopting) and VLCKit https://code.videolan.org/videolan/VLCKit (TVVLCKit is the tvOS flavour; LGPL-2.1+ *(unverified)*). Both are fine for a private build; record the choice in `DECISIONS.md`.
- **fanart.tv Swift wrapper** https://github.com/fitomad/FanartTVKit . Small; mostly a model reference.

## API documentation

- **Plex Media Server:** https://developer.plex.tv/pms/ (official) and https://www.plexopedia.com/plex-media-server/api/ (community) *(unverified)*. The python-plexapi docs are also a reliable map of endpoints.
- **Seerr:** https://docs.seerr.dev (project docs; migration guide from Overseerr/Jellyseerr at `/migration-guide`), repo https://github.com/seerr-team/seerr . API: Swagger at `http://<host>:5055/api-docs` on your instance; spec `seerr-api.yml` in the repo. Overseerr and Jellyseerr were sunset in May 2026; Seerr is current.
- **Tautulli API:** https://docs.tautulli.com/extending-tautulli/api-reference
- **Home Assistant WebSocket API:** https://developers.home-assistant.io/docs/api/websocket and REST https://developers.home-assistant.io/docs/api/rest
- **Frigate:** go2rtc https://docs.frigate.video/configuration/go2rtc , restream https://docs.frigate.video/configuration/restream/ , guide https://docs.frigate.video/guides/configuring_go2rtc , HA integration https://docs.frigate.video/integrations/home-assistant *(unverified)*
- **TMDB:** https://developer.themoviedb.org/reference . **fanart.tv:** https://fanart.tv/api-docs/ *(unverified)*
- **Decypharr:** https://github.com/sirrobot01/decypharr (debrid and usenet manager with arr integration; check its API for a repair/re-fetch endpoint).
- **Kometa** (poster overlays and collections, for ideas) https://kometa.wiki ; **Trailarr** https://github.com/nandyalu/trailarr *(unverified)*
- **Artwork sources:** ThePosterDB https://theposterdb.com , MediUX https://mediux.pro (no confirmed public API; URL paste in Admin is enough).
- **Apple MusicKit** https://developer.apple.com/documentation/musickit (check the tvOS availability table; `ApplicationMusicPlayer` availability differs by platform).
- **AVFoundation on tvOS:** `AVPlayerViewController` docs and the `AVDisplayManager` / `preferredDisplayCriteria` docs for frame-rate and dynamic-range matching.
- **Anthropic Claude API:** https://docs.claude.com (tool use, prompt caching).

## Device management

- **Apple Configurator for Mac** https://support.apple.com/guide/apple-configurator-mac/welcome/mac . Supervising an Apple TV and Single App Mode. Developer forum thread https://developer.apple.com/forums/thread/31217 . Jamf's tvOS profile reference is a readable description of the payload: https://docs.jamf.com/technical-papers/jamf-pro/managing-apple-tv/10.4.0/tvOS_Configuration_Profiles.html
- **TestFlight internal testing** (no App Review, 90-day builds): https://developer.apple.com/testflight/ and App Store Connect help.

## Community knowledge worth skimming

- Plex forums threads on the tvOS "new experience" and the Apple player beta (listed in `DECISIONS.md`) for the long tail of playback issues on Apple TV: frame-rate matching, TrueHD, PGS, stutter on high bitrate.
- r/PleX and r/AppleTV threads on Infuse vs Plex for what people value in a player.
- Netflix Tech Blog https://netflixtechblog.com has general TV UI performance posts; nothing specific was verified for this pack.
