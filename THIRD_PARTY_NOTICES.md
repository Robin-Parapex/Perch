# Third-party notices

No third-party code ships yet.

- **Dusk (MIT, github.com/marvinvr/dusk-player):** WP-04 (PerchPlex) took ideas only: the Plex endpoint set, connection tiers, and commit-on-success profile switching. No code was copied.
- **Dusk (MIT):** WP-06 (PerchPlex) took ideas only, no code copied: lenient int-or-string decoding, hub filtering and the continueWatching/onDeck approach, section paging (50 then 100), timeline cadence and buffering behaviour, scrobble at 90%, and next-episode order skipping season 0.
- **Swiftfin (MPL-2.0):** WP-06 (PerchPlex) took ideas only, no code copied: one progress report in flight with the newest pending replacing older ones, and a revision per item so a late read cannot undo a newer watched toggle.

Rules for when it does:

- **Dusk (MIT):** adapted code keeps its notice, "Copyright (c) 2026 Marvin von Rappard".
- **Swiftfin (MPL-2.0):** copied or modified files stay MPL-2.0, keep their header, and are listed here.
- **VLCKit (LGPL):** arrives in 2.0. The exact wording, "2.1" or "2.1 or later", is to be confirmed in WP-36.
- **Plezy (GPL-3.0):** never copied.
