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
- Full-quality 4K, HEVC and Dolby Vision playback from the simulator (blocked by the Mac's DNS, see below).
- HEVC over TS versus fMP4 is still open.

## How it was checked
- The design had two Opus reviews; the final verdict was ready for household review.

## Remote SD transcodes and the connection fix
- On the Mac, the Pi-hole (192.168.70.7) blocks plex.direct names that resolve to private addresses (DNS rebind protection). The simulator could only reach the public address, so the server sent SD (decision line for item 61131, HEVC Dolby Vision 8: container=mpegts videoCodec=h264 audioCodec=mp3 videoResolution=SD).
- The household Apple TV network resolves the names fine; Robin confirmed on 4 Nov 2026 that the official Plex app plays locally there.
- Fix committed in 2b8a9e9 (prefer local connections, upgrade in the background).
- Not verified: full-quality 4K/HEVC/Dolby Vision playback from the simulator. The Mac's DNS blocks it; the fix would be `rebind-domain-ok=/plex.direct/` in Pi-hole or a hosts entry.

## Open items
- TLS resets on the public Plex endpoint.
- A one-shot automatic reload after a transport reset.
- Transcode sessions left behind when the app is killed.
- The startPlayback failure lets playback continue unreported (logged).
- The info panel lacks artwork when the image arrives late.

Decisions are in `docs/DECISIONS.md` (2026-11-04 sections).
