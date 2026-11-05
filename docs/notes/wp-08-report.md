# WP-08 artwork pipeline: report

5 Nov 2026. Branch `wp-08-artwork`. Plan: `docs/notes/wp-08-plan.md`.

## Built
- Sized image requests from Plex, with `clearLogo` read for the Home hero.
- Nuke artwork pipeline with blurred placeholders that crossfade to the full image.
- Prefetch of the first row on load, the next row and the focused item.
- Page tint from the focused artwork.
- 300 MB on-disk cache keyed by serverID|path|size, surviving relaunch and cleared on sign-out and reset.
- Avatars and the profile picker backdrop moved to the new cache; the old image cache is removed.

## Checks
- **Gate:** passed on the second run (PerchCore 200, PerchPlex 329, PerchPlayer 52, PerchDesign 35, 31 UI tests). The first run had one flaky failure in PlayerUITests `testCouldntPlayAsKidOffersBackOnly`, which passed twice when run alone.
- **UI tests:** ArtworkUITests shows 6 placeholders, then 6 loaded, with no spinners.
- **Live:** sized poster 25,575 B against 419,887 B full (first size set; 48,792 B with the 4K buckets); placeholders 2 to 3 KB; backdrop 381 KB. The second launch logged 36 of 36 posters from cache.

## Notes for WP-09
- `artwork.*` accessibility identifiers land on the card button in XCUITest.
- The first row is prefetched on load.

Decisions are in `docs/DECISIONS.md` (2026-11-05 sections).

## Review and design critique
Fixes after review, 5 Nov 2026.
- **Review:** Opus reviewer verdict "ship", with four should-fix items, all fixed. Opus design critic verdict "needs fixes" (focus and tint evidence, crescent artefact, spotlight gradient, 4K sharpness), all addressed.
- **Offline cache:** new `ArtworkCachePolicy` (PerchCore `Media/ArtworkCacheKey.swift`) keeps the last server ID in App Group defaults key `perch.artwork.serverID`, forgotten only on sign-out, so cached art shows while the server is connecting or unreachable. A first ready server that differs clears the artwork caches.
- **Avatars:** the cache key keeps the `c` query item so avatars refresh, and drops the rest.
- **Sign-out:** clears memory and disk artwork caches, cancels prefetches, resets the tint and removes the remembered picker backdrop. A generation counter drops loads that finish after a clear. DEBUG flag `-PerchClearArtwork`.
- **Tests:** new hosted unit test target PerchAppTests (ArtworkServiceTests, 7 tests), run by the existing gate via the PerchApp scheme. App-target logic gets a hosted test target rather than moving into a package.
- **Polish:** the placeholder fades out once the image loads; logos show nothing behind them. The tint cache is keyed by the full cache key. The prefetch cache count runs off the main actor.
- **Gradient:** the fallback is a calm vertical wash (about 55% luminance, 35% desaturated, opacity 0.16 to 0.07) instead of a spotlight.
- **Sizes:** raised for 4K: poster 480x720, landscape 672x380, backdrop 3840x2160, logo 1200x464, placeholder 64. One 2x set for all devices; on a 1080p Apple TV this downloads more pixels than needed, accepted for simplicity. Same poster: 48,792 B against 419,887 B full size.
- **DEBUG Library check:** `-PerchFocusIndex N`, and screen scale on the status line. The fake transport draws 4:3 test cards.
- **Player:** the kid overlay re-asks for focus up to three times (`PlayerOverlayContent.swift`).
- **Evidence:** `wp08b-focus-1.png`, `wp08b-b-tint-pair.png`, `wp08b-ui-41-artwork-loaded.png`.

## Known issues
- `testCouldntPlayAsKidOffersBackOnly` is intermittent on the simulator. Gate outcome: TBC (to be added by the lead).
- A clear landing between a load finishing and Nuke storing it is a small race.
- Focused card artwork overlaps its caption (PerchCardButton, PerchDesign), for WP-09.
- No live mid-load screenshot, because LAN loads finish before the first frame. Placeholder states are shown through the fake household UI test instead.
- Note for WP-09 (design critic): Continue Watching should use landscape stills.
