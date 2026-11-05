# WP-08 plan: artwork pipeline

## Context

WP-07 is merged. WP-08 is the second WP of stage **0.2.0 First playback**. Images were fetched without sizing and cached by an older image cache, so posters were large and boxes could show grey. Home (WP-09) needs fast posters, placeholders, clear logos and a tint. Branch `wp-08-artwork`.

## Decisions (recorded in `docs/DECISIONS.md`, 5 Nov 2026)

- **Nuke 12.9.0**, pinned exactly, app target only (Nuke and NukeUI). PerchDesign stays free of image libraries. 12.x until there is a reason to move to 13.x.
- **Sized images** from Plex's photo transcoder in fixed buckets: poster 300x450, landscape 640x360, backdrop 1920x1080, logo 800x310, placeholder 64x64. Token only in a header.
- **Cache key** serverID|path|size (`ArtworkCacheKey`, PerchCore), never the URL. Disk cache in the App Group `Library/Caches/Artwork`, 300 MB LRU, no 7-day timer.
- **Source order** override, fanart.tv, TMDB, Plex kept as a list in `ArtworkService`; only Plex is implemented.
- **Tint** from the 64 px placeholder average, clamped, 10%, 0.4 s fade, debounced 150 ms, none under Reduce Motion.
- **DEBUG launch arguments** `-PerchLibraryCheck` and `-PerchSlowArtwork`.

## Slices

- **A, builder (Sonnet):** PerchPlex and PerchCore. Sized Plex image requests, `clearLogo`, `ArtworkSize`, `ArtworkCacheKey`.
- **B, builder (Sonnet):** PerchDesign. Artwork tint maths and the blurred placeholder.
- **C, solver (Opus):** app glue. Nuke pipeline, placeholders crossfading to full images, prefetch, focus tint, disk cache lifecycle, moving avatars and the picker backdrop over, removing the old cache.

## Acceptance

- Posters are requested at the sized bucket and are much smaller than the original.
- A placeholder shows before every full image, never a grey box or a spinner.
- The cache survives relaunch and clears on sign-out and reset.
- The gate passes.
