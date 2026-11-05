# Third-party notices

## Shipped packages

- **Nuke and NukeUI 12.9.0 (MIT, github.com/kean/Nuke):** WP-08, image loading, caching and prefetching in the app target.

  > The MIT License (MIT)
  >
  > Copyright (c) 2015-2026 Alexander Grebenyuk
  >
  > Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
  >
  > The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
  >
  > THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Ideas taken, no code copied

- **Dusk (MIT, github.com/marvinvr/dusk-player):** WP-04 (PerchPlex) took ideas only: the Plex endpoint set, connection tiers, and commit-on-success profile switching. No code was copied.
- **Dusk (MIT):** WP-06 (PerchPlex) took ideas only, no code copied: lenient int-or-string decoding, hub filtering and the continueWatching/onDeck approach, section paging (50 then 100), timeline cadence and buffering behaviour, scrobble at 90%, and next-episode order skipping season 0.
- **Swiftfin (MPL-2.0):** WP-06 (PerchPlex) took ideas only, no code copied: one progress report in flight with the newest pending replacing older ones, and a revision per item so a late read cannot undo a newer watched toggle.

Rules for when it does:

- **Dusk (MIT):** adapted code keeps its notice, "Copyright (c) 2026 Marvin von Rappard".
- **Swiftfin (MPL-2.0):** copied or modified files stay MPL-2.0, keep their header, and are listed here.
- **VLCKit (LGPL):** arrives in 2.0. The exact wording, "2.1" or "2.1 or later", is to be confirmed in WP-36.
- **Plezy (GPL-3.0):** never copied.
