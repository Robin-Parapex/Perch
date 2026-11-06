# WP-11 Series and title pages: plan and notes

Built 6 Nov 2026 on `wp-11-title-pages` (from main 7786c14) by the WP-11 solver, from the lead's approved brief.

## What was built

- **Data.** `MediaDetail` gains `cast: [MediaCastMember]` (name, part, portrait path) and `themePath`. PerchPlex decodes `Role` and `theme` on the metadata reply; a theme path is kept only when it is a plain server path. `PlexLibrary.themeSource(ratingKey:path:)` returns a URL plus headers (token in the `X-Plex-Token` header only), authorised like playback.
- **Pages** (`PerchApp/Features/Title/`). `TitleScreen` (film) and `SeriesScreen` share `TitlePage`. Pushed on the current tab's stack as `ShellRoute.title(TitleRoute)` and `.series(TitleRoute)`; a `TitleRoute` carries the opener's `MediaSummary` so the first frame has the name and art, and a season id when a season or episode card opens the series.
- **Hero.** Fixed 1920 x 648 (60% of 1080): backdrop faded in by a mask, logo or title, facts line (year, certificate, runtime or seasons, first genre), badges (4K or HD; Dolby Vision, HDR10 or HLG from the first version), a three-line synopsis that is focusable and opens the full text on Select ("More" shows when it is long), then the actions. Fixed sizes, not `HeroCard`, because container-relative frames inside a scroll view re-laid out every frame on the grids (WP-10) and HeroCard caps the synopsis at two lines.
- **Film actions.** Primary: Play / Resume · time left / Play again (`FilmPrimaryAction`), first focus. Secondary: Play from the start (only when resuming), Mark watched / Mark unwatched.
- **Series actions.** Primary: Play · S1 E1, Play next · S2 E3, Resume · S2 E3 or Play again · S1 E1 (`SeriesNext`). Season chips, then the season's episodes as a shelf of landscape cards (thumbnail, "3. Title", runtime or time left, progress bar, watched tick, one-line synopsis). Select plays (resuming when started), Play/Pause plays, long-press offers Mark watched / unwatched.
- **Cast rail.** 150 pt circles, name and part, focusable (lift 1.1 and ring) with no action yet. Server portraits through the artwork service, https portraits as public images, initials otherwise.
- **Theme music.** `ThemeMusicPlayer`: `AVURLAsset` with `AVURLAssetHTTPHeaderFieldsKey` (as NativeEngine), volume 0.25, 1 s fade in and out, stops on leaving the page or when playback starts and never restarts on that page. Off for a kid.
- **Entry points.** Grid and collection posters: Select opens the page, Play/Pause plays. Home: series and season cards open the series page; film, Continue watching and Up next cards still play on Select; long-press on a film card offers "Details", on an episode card "Go to series". Back from a page lands on the card or poster that opened it; Back from the player lands on the button or episode that started it.
- **DEBUG.** `-PerchTitleProbe` logs cast, theme and season/episode counts for the first film and series (counts and yes/no only). `-PerchOpenFirstTitle` opens the first grid title's page (live screenshots). Fake household: a detail per title (`FakeTitleCatalogue`), series 2000 with two seasons, themes on 2000 and 1004, Recently added TV now holds series 2000 instead of episode 2104.

## Acceptance evidence

See the solver's report (suites, counts, screenshots). UI coverage: `PerchUITests/TitleUITests.swift`.

## Changed expectations in existing tests

- `LibraryUITests.testPosterPlaysAndBackReturnsToThePoster` now starts playback with Play/Pause (Select opens the title page).

## Decisions (for DECISIONS.md)

## 2026-11-06 Title and series pages (WP-11)
- Select on a grid or collection poster opens its title or series page; Play/Pause on a poster still plays at once. On Home, series and season cards open the series page; film, Continue watching and Up next cards still play on Select (two-click resume). Long-press on a Home film card offers "Details", on an episode card "Go to series". Supersedes "Select on Home cards in 0.2" for series and seasons and its "Long-press does nothing until WP-11"; the Home hero's button still plays a series directly.
- Play next rule (`SeriesNext`): an episode in progress resumes when it is the latest viewing; otherwise the first unwatched episode after the most recently watched one, wrapping to the first unwatched; nothing watched plays S1 E1; everything watched offers Play again from S1 E1. Specials count only when a series has nothing else. Computed from one `allLeaves` call, not `nextEpisode`, so the page needs no second request. Grid Play/Pause on a series uses the same rule (replaces `HomeModel.episodeToPlay` there).
- "Play next always on the right" (SPEC 4): the hero's primary button is Play next and takes first focus; a second Play next chip sits at the trailing end of the season row, beside the episodes, so it is one move away wherever focus is in the episode area.
- The page hero is the page's own fixed-size view (648 pt), not `HeroCard`: three-line synopsis, focusable, Select opens the full text in a glass panel.
- Cast circles are focusable with no action until person pages; https portraits (Plex's metadata server) load as public images, server paths through the artwork service.
- Theme music plays on film and series pages when the title has a theme (SPEC 5 says "0.3 hook, on by default from 1.2"; the WP-11 brief asked for it on). 0.25 volume, 1 s fades, stops for good on leaving or when playback starts. Off for kids. There is no global setting yet; `ThemeMusicPolicy.plays(switchedOff:)` is the hook WP-18 fills.
- A page re-checks the rating guard on its detail (`RowContext.admits`, and the certificate check for a kid); a title above the ceiling shows "Not available on this profile" with Go back. Mark watched stays allowed for every role (it is authorised as Play).
- "More in this collection" was left out (optional in the brief): the detail reply would need its collection tags and a second browse call.
- Grids restore focus after playback only while on screen, so a page pushed over a grid keeps the grid's pending restore for the Back that pops it.
- Full detail: `docs/notes/wp-11-plan.md`.
