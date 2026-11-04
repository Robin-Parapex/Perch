# WP-07 PerchPlayer: report

4 Nov 2026. Branch `wp-07-player`. Plan: `docs/notes/wp-07-plan.md`.

## Acceptance
- **Decision table:** covered by 307 PerchPlex tests, including all 16 fixture clips. A honesty mutation was caught.
- **Live:** direct play and directStream play from Robin's server.
- **Resume:** about 0.9 s warm, 1.4 s first launch (target 2 s).
- **Timeline:** positions advance every 10 s (120, 130, 140, 150, 160, 170 s observed).
- **UI tests:** skip, up next, still watching, failure (parent, kid), resume and Back focus return are proven by PlayerUITests and PlayerSpikeUITests, offline on the fake household.
- **Gate:** passes, 30 UI tests, all packages.
- **Release build:** no debug strings, and the clip is excluded.

## Not done on the device
- Display-mode switching and the dropped-frames check on the 80 Mbit/s 4K sample (simulator-only runs since 2 Nov).
- The live codec matrix waits on the optional fixtures library.

## How it was checked
- The design had two Opus reviews; the final verdict was ready for household review.

## Open items
- TLS resets on the public Plex endpoint.
- A one-shot automatic reload after a transport reset.
- Transcode sessions left behind when the app is killed.
- The startPlayback failure lets playback continue unreported (logged).
- The info panel lacks artwork when the image arrives late.

Decisions are in `docs/DECISIONS.md` (2026-11-04 sections).
