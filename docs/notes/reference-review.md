# Reference review: Dusk and Swiftfin

Read for WP-01 on 1 November 2026. Shallow clones: Dusk (marvinvr/dusk-player) at `3e32318b748a5c11183a610022ffc778f1bba741`, Swiftfin (jellyfin/Swiftfin) at `76f5b06665e0d307b2579410ef82d79a43757452`. Paths are relative to each repository. We borrow approaches, not files; see `CLAUDE.md`.

## Headlines

- Dusk is a real tvOS app: target `Dusk-tvOS`, tvOS 26.0 minimum, Swift 6.0, strict concurrency complete (`project.yml:6`, `:15`, `:58-111`, `:98`). It is the closest match to Perch.
- Swiftfin is a Jellyfin client, so it has no Plex code. tvOS minimum 26.1, `SWIFT_VERSION = 5.0` (`Swiftfin.xcodeproj/project.pbxproj:1095`, `:1098`).
- Swiftfin uses MPV and AVPlayer, not VLCKit (`Shared/Objects/MediaPlayerManager/Players/MPVMediaPlayer.swift`), so it does not help with 2.0.
- Neither repository has a `PrivacyInfo.xcprivacy`. Perch writes its own.

## 1. Plex auth

**Borrow from Dusk** (Swiftfin has no plex.tv flow):
- PIN create and poll: `POST /api/v2/pins`, `GET /api/v2/pins/{id}` (`Dusk/Sources/PlexService/PlexService+Auth.swift:42-53`). Link URL at `:60-61`. Check the `strong:` flag at `:42` against the Plex docs before copying.
- Headers built in one place: `X-Plex-Client-Identifier`, `X-Plex-Product`, `X-Plex-Platform`, `X-Plex-Device-Name` (`PlexService+Networking.swift:11-24`). Server token in `X-Plex-Token` (`ServerPool.swift:586`).
- Client identifier generated once and kept (`PlexService.swift:94`, `:160-164`). Where it is stored was not confirmed.
- Keychain generic password (`KeychainHelper.swift:6-17`). Note Perch requires `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`docs/MODULES.md`), which is stricter than Dusk's `kSecAttrAccessibleAfterFirstUnlock`.
- One retry after fresh authentication (`PlexService+Auth.swift:69`).

**Avoid:** token handling spread across many extensions. Keep Perch's in one actor.

## 2. Plex Home switching and PIN

**Borrow from Dusk:**
- List with `GET /api/v2/home/users` (`PlexService+Home.swift:182-184`). Switch with `POST /api/home/users/{id}/switch?pin=…` (`:80-104`), PIN normalised first (`:92`).
- Commit the new token only after success, so a wrong PIN leaves the session intact (`:122-125`).
- Active Home token in its own Keychain slot (`:128-137`). Restored sessions validated on launch (`:348`).

**Avoid:** the very tolerant JSON walking at `:260-340`. It suggests unstable response shapes. Decode into one typed model and test against fixtures.

## 3. Hubs, markers, timeline

**Borrow from Dusk** for Plex specifics:
- Hubs: `/hubs`, `/hubs/continueWatching`, `/hubs/promoted`, `/hubs/sections/{id}`, `/hubs/search` (`PlexService+Library.swift:113`, `:129`, `:252`, `:260`, `:301`). Multi-server merging in `MultiServer/HubMerge.swift:24`.
- Markers: `includeMarkers=1` on metadata (`PlexService+Library.swift:346`). Skip and credits logic with an estimated-credits fallback (`Features/Player/PlayerViewModel+Presentation.swift:91-134`). Auto-skip countdown (`PlayerViewModel.swift:90-106`).
- Timeline: `GET /:/timeline` with state, time, duration and `X-Plex-Session-Identifier` (`PlexService+Playback.swift:160-172`). Scrobble and unscrobble at `:178`, `:189`. 10 second tick, queued for offline sync (`PlaybackCoordinator+Timeline.swift:18`, `:108`).

**Borrow from Swiftfin** the shape only, since its APIs are Jellyfin's: `MediaSegmentObserver.swift:16-35`, `MediaProgressReporter.swift:17-99`, serial report queue at `:168`.

**Avoid:** Dusk's very large coordinator files (`PlaybackCoordinator+Session.swift` passes line 1950).

## 4. tvOS focus

**Borrow from Swiftfin** for restoration: `Shared/Objects/FocusCoordinator.swift` has request tokens (`:67-69`), initial-focus placeholder roles (`:25-56`), remembered focus per container (`:209-211`) and `coordinatedFocus(_:)` modifiers (`:219-227`). Also `.focusSection()` in `Shared/Components/PosterHStackLibrarySection.swift:107-133`. This serves non-negotiable 3 directly. If we copy the file rather than reimplement it, it stays MPL-2.0 (see Licences).

**Borrow from Dusk** for tab and search edge cases: `.focusSection()` on shelves (`Shared/MediaCarousel.swift:39`); `@FocusState`, `.prefersDefaultFocus` and `resetFocus` on hero buttons (`Features/Home/HomeTVView.swift:10-12`, `:210`, `:770-775`).

**Avoid:** walking `parentFocusEnvironment` to decide what Back does (`App/MainTabShells.swift:190-200`). It is brittle.

## 5. Poster rows

- **Dusk:** `ScrollView(.horizontal)` with `LazyHStack` and `.focusSection()` (`Shared/MediaCarousel.swift:27-39`). Actor image loader with `NSCache` (`Shared/DuskAsyncImage.swift:56-138`). Simple and native.
- **Swiftfin:** `CollectionHStack`, a UICollectionView-backed package (`Shared/Components/PosterHStack.swift:9-41`). Nuke pipelines split by purpose (`Shared/Extensions/Nuke/ImagePipeline.swift:67-83`), 1000 MB disk cache (`DataCache.swift:24-34`).

**Take:** Dusk's lazy row as the starting point and Swiftfin's Nuke pipeline split for WP-08, since Nuke is already approved. **Avoid:** a hand-rolled image cache, and adding `CollectionHStack` without a dependency decision.

## 6. Top Shelf

**Borrow from Dusk** (Swiftfin has only a Top Shelf image, no extension):
- Separate extension target depending on `TVServices`, embedded in the app, `APPLICATION_EXTENSION_API_ONLY: true`, one shared snapshot file compiled into both (`project.yml:107`, `:113-135`).
- Info.plist: `NSExtensionPointIdentifier = com.apple.tv-top-shelf`, principal class `$(PRODUCT_MODULE_NAME).ContentProvider` (`DuskTopShelf/Info.plist`).
- `TVTopShelfSectionedContent` provider returning nil so tvOS falls back to the static image (`DuskTopShelf/ContentProvider.swift:3-48`). Use this nil path for the WP-01 placeholder.
- App Group on both targets. Data is a JSON snapshot plus cached images (`TopShelfSnapshot.swift:12-64`). The app calls `topShelfContentDidChange()` after writing (`TopShelfPublisher.swift:61`, `:120`).
- Gotcha: on a real Apple TV the only writable place in the App Group is `Library/Caches`; the simulator does not enforce this (`TopShelfSnapshot.swift:41-45`).

**Note for WP-17:** Dusk's extension has no token and no network (`TopShelfPublisher.swift:7-10`). `docs/SPEC.md` section 16 has our extension read the owner token through the shared Keychain group. WP-17 should weigh the snapshot approach, since it also makes the family-safe rule easier to enforce.

## 7. VLCKit for 2.0

Only Dusk applies.
- Wiring: `TVVLCKit.xcframework` embedded, `AVKit.framework` explicit (`project.yml:100-104`). Conditional imports (`Playback/VLCKitEngine.swift:1-4`). `VLCMediaPlayer(library:)` at `:425`, `player.drawable = playerView` (`VLCKitRendererTVOS.swift:17`).
- Packaging: binaries not committed. `ci_scripts/install_vlckit.sh` fetches them with pinned SHA-256 (`:34-47`), called from `ci_post_clone.sh`. A post-build script checks for staleness (`project.yml:108-111`).
- Dusk's own 3.7.3-dusk3 build lives in a private repository (`install_vlckit.sh:19-25`). The fallback is VideoLAN's stock 3.7.3 (`:42-47`). Start with stock.
- TrueHD: stock builds disable the decoder. Dusk patches it back on (`ci_scripts/vlc-patches/0100-…`), giving up to 8-channel PCM, and for Atmos only the 7.1 bed (`docs/playback.md:1185-1195`). Dusk records that it holds no Dolby licence and sees legal and App Review risk (`:1196-1203`). That is a decision for Robin in 2.0, not a default.
- Dolby Vision 7 to 8.1: a statically linked Rust library, `Native/DuskDovi` (libdovi), design at `docs/playback.md:530-563`. It feeds an AVPlayer remux path, not VLC (`:613-614`). Profile 7 with TrueHD forces converted E-AC-3 audio (`:548-563`). Default off (`:648`). Needs Metal Toolchain handling in CI (`ci_scripts/ci_post_clone.sh`).

## Skeleton facts for WP-01

| Item | Dusk | Swiftfin |
|---|---|---|
| Generator | XcodeGen `project.yml`, with `Dusk.xcodeproj` also committed | Hand-edited pbxproj |
| Packages | None via SwiftPM; xcframeworks fetched by script | SwiftPM: Nuke, CollectionHStack and others |
| Shared schemes | Explicit in `project.yml:174-209` | Committed under `xcshareddata/xcschemes/` |
| xcconfig | None | `XcodeConfig/Shared.xcconfig`, optional `#include? DevelopmentTeam.xcconfig` |
| CI | `ci_scripts/ci_post_clone.sh` for Xcode Cloud | `fastlane/`, no `ci_scripts` |
| ATS | `NSAllowsArbitraryLoads=true` | Same |
| Local network | `NSBonjourServices` (`_plexmediasvr._tcp`) and `NSLocalNetworkUsageDescription` | Neither key in the tvOS plist |
| Other plist keys | URL scheme, `ITSAppUsesNonExemptEncryption=false` | URL schemes, `UIBackgroundModes` audio |
| Privacy manifest | None | None |
| Icon | `AppIconTV.brandassets`: imagestacks 400x240 and 1280x768, wide Top Shelf 2320x720, `ASSETCATALOG_COMPILER_APPICON_NAME: AppIconTV` | `App Icon & Top Shelf Image.brandassets` with icon, App Store icon, Top Shelf and wide imagesets |

## What to avoid overall

- Shipping without a privacy manifest.
- Oversized coordinator and view-model files.
- Private binary dependencies and unlicensed codec patches.
- UIKit focus-environment walking.
- Anything from Swiftfin's Jellyfin API layer; only patterns transfer.

ATS is not on this list: both references use `NSAllowsArbitraryLoads`, and so does Perch by decision (`docs/DECISIONS.md`, "Apple TV model and ATS").

## Licences

- **Dusk: MIT**, confirmed from `LICENSE`, "Copyright (c) 2026 Marvin von Rappard". Adapted code is allowed; keep the notice in `THIRD_PARTY_NOTICES.md`. If the DV converter is ported, carry the libdovi notices too (`Dusk/Resources/ThirdPartyNotices.txt`).
- **Swiftfin: MPL-2.0**, confirmed from `LICENSE.md` and per-file headers (Copyright 2025 Jellyfin & Contributors). A copied or modified file stays MPL-2.0, keeps its header and is listed in `THIRD_PARTY_NOTICES.md`. Reimplementing the idea carries no obligation. `FocusCoordinator.swift` is the file most likely to be copied.
- **VLCKit: LGPL.** The GitHub mirror README says LGPLv2.1 (https://github.com/videolan/vlckit), and Dusk bundles the LGPL-2.1 text (`Frameworks/VLCKit-LICENSE.txt`). "2.1 only" against "2.1 or later" (`docs/REFERENCES.md` says LGPL-2.1+) is **not confirmed**: upstream `COPYING` on code.videolan.org could not be read. Verify in WP-36. Dynamic embedding, as Dusk does, is the compliant pattern. Dusk's TrueHD patch adds a separate patent concern.
- **Plezy: GPL-3.0.** Read for behaviour only, never paste from it.

## Not reached

Dusk's PIN-entry UI, Swiftfin's MPV wiring in detail, Swiftfin's fastlane use, and Dusk's `STYLE.md` and `AGENTS.md`. Nothing from either repository was built or run.
