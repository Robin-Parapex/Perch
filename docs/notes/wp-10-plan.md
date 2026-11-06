# WP-10 Films and Series: plan and notes

Branch `wp-10-library`, on top of 377fafc (PerchPlex section queries, letters, filters, collections). Built by the WP-10 solver (Claude) from the lead's brief, 6 Nov 2026.

## What was built

- **Fake household browse data** (`PerchApp/Debug/FakeLibraryCatalogue.swift`): 28 films (section 1, ids 1001 to 1028) and 13 series (section 2), spread over "#" and A to Z, 1992 to 2024, seven genres, 4K / 1080p / SD, U, PG, 12, 15, 18 and one unrated film, some watched; collections 9001 "Harbour stories" and 9002 "Family nights" (films) and 9003 "Island life" (series). Serves `/library/sections/{id}/all` (sort, genre, decade, resolution, unwatched, collection, `contentRating`, `contentRating!`, paging with `totalSize`), `firstCharacter`, the four filter value lists, `collections` and collection children. A switched user's server token now names the user (`FAKE-SERVER-TOKEN-<id>`), so the fake server applies Sam's little_kid restriction (U only) as Plex does. Hubs, onDeck and the detail answer are unchanged.
- **`LibraryGridScreen`** (Films and Series tabs, replaces the placeholders): page title, section chips when a kind has more than one section, a Sort menu, Genre / Decade / Resolution / Collection menus, an Unwatched toggle and "Clear filters (n)". Native `Menu`s with `PerchChipButtonStyle`. A Collections row above the grid (hidden while filters are set). `LazyVGrid` of six 240 x 360 `PosterCard`s, 80 pt leading margin, `.focusSection()`. Paged through `PlexSectionPager`; the next page is asked for when focus is within 18 items of the end; poster-shaped placeholders while a page is on its way, never a spinner. The page that arrives is prefetched; the page tint follows the focused poster.
- **Letter rail** (`PerchDesign/LetterRail`): trailing edge, only when sorted by title, letters from `firstCharacters` with the same filters. A letter reloads the grid from `letterOffsets` and focuses its first title.
- **`CollectionGridScreen`**, pushed on the tab's stack (`ShellRoute.collection`); Back pops to the same collection card.
- **Ceiling**: `LibraryQueryBuilder`. Lowered (Perch ceiling below the service ceiling): `contentRatings = admittedContentRatings(sectionID:ceiling:)`; a failed lookup fails closed (empty set, nothing requested). Not lowered: no content-rating filter. Every page then passes `RowContext.admits` (unrated counts as 15).
- **Select**: a film plays (resuming when started); a series plays its first unwatched episode, else S1 E1. Play/Pause does the same. Long-press: Mark as watched / Mark as unwatched.
- **Focus memory**: `FocusMemory` scope `library.<section>.<sort>.<filters>` per profile; a sort or filter change targets the first item.
- **DEBUG `-PerchLibraryProbe`** (`PerchApp/Debug/LibraryProbe.swift`): one `PROBE` line per check for the first film and series sections. Small PerchPlex additions for it: `sectionTotal(query:extraItems:)`, `collectionChildCount(collectionID:contentRatings:)`.

## Live probe (C6E85DCA, normal signed launch, 6 Nov 2026)

Superseded by the second pass below: the first-pass numbers counted prefixed rating keys as unknown.

- Films (section 16): 490 unfiltered; PG set (PG only) 1; firstCharacter follows the filter (27 buckets/490 to 1/1, sum equals total); `contentRating!=` (9 values) honoured, 1; collections: 94 unfiltered, 0 with the PG filter; collection children ignore the filter (20 and 20).
- Series (section 18): 132 unfiltered; PG set (TV-G, TV-Y) 4; firstCharacter follows (24/132 to 4/4); `contentRating!=` (10 values) honoured, 4; no collections.
- First run found `collections?type=1` returns the section's films, not collections: the `type` item is removed and the mapping keeps only `type == collection` rows (PerchPlex, test updated).
- First live launch also showed "Couldn't reach your library": the grid loaded while the session was still connecting. Grids now load when the session is ready, and retry when it becomes ready after a failure.

## Second pass (review and design fixes, 6 Nov 2026)

Live re-probe (C6E85DCA, normal signed launch, `-PerchLibraryProbe`):
- The server lists prefixed ratings with percent-encoded keys: films `Not%20Rated`, `PG`, `R`, `gb%2F12`, `gb%2F12A`, `gb%2F15`, `gb%2F18`, `gb%2FPG`, `gb%2FU`, `None` (titles decoded, `gb/PG` and so on); series `TV-14`, `TV-G`, `TV-MA`, `TV-Y`, `gb%2F12` to `gb%2F18` (with `gb/16`), `gb%2FPG`, `gb%2FU`, `None`. Classifying the raw key made every prefixed value unknown (15), so a PG ceiling admitted only the bare ones.
- Admitted now: films PG `PG, gb/PG, gb/U`, 12 `PG, gb/12, gb/12A, gb/PG, gb/U`; series PG `TV-G, TV-Y, gb/PG, gb/U`, 12 adds `gb/12, gb/12A`.
- Totals: films 490 unfiltered; PG 1 before, 223 after; 12 338. Series 132; PG 4 before, 25 after; 12 41. firstCharacter sums match; `contentRating!=` with the decoded excluded set gives the same totals.
- Collections (films): 94 unfiltered, 50 under the fixed PG set (the list honours the filter now); children of the largest still ignore it (20 and 20). Loading every collection's members one by one took 6.7 s; 36 of 94 keep two or more PG titles (120 titles).

## Decisions

- Library grids in 0.3 use native `Menu`s for sort and filters (one value per menu), with a slim chip style (`PerchChipButtonStyle`, 52 pt) rather than the 68 pt action pills, because a header holds up to eight. Rejected: a side panel of filters (one more layer of focus for no gain).
- A letter jump reloads the grid from that letter's offset (the first item is the letter's first title, so focus lands on it). Titles before it are reached through the rail, not by scrolling up. Rejected: a sparse grid holding every position, which needed placeholders for unloaded gaps and a pager per window.
- The rating ceiling on library grids: a content-rating set only when Perch's ceiling is below the service's; otherwise nothing is sent and the server's own restriction stands (so unrated titles stay visible to adults). `RowContext.admits` guards every page. Each filter key is percent-decoded before it is classified and sent (the query item encodes it once); a key that does not parse is classified by its title; unknown and unrated count as 15. A failed ratings lookup requests nothing and shows "Couldn't reach your library" with Try again, which looks the ratings up again (never "No films yet"); no query is built while they are unresolved.
- Select on a film in a grid resumes it when started, else plays from the start; a series plays its first unwatched episode, else S1 E1 (Home's rule), until WP-11's title pages. Long-press marks watched or unwatched (the first context menu in the app).
- The Collections row shows only while no filter is set. There is no Collection filter chip (the row covers it). A collection needs two or more titles; a trailing " Collection" is dropped from its name.
- Collections under a lowered ceiling are shown, guarded on the client: the list is asked for with the content-rating set (the server narrows 94 to 50), then each candidate's members are loaded four at a time and pass the final guard; a card shows only with two or more admitted titles and counts only those. Evidence: children ignore the filter (20 and 20), and a full member load is about 6.7 s sequential for 94, so about 2 s for 50 at four at a time, after the grid's first page (the grid never waits for it). Rejected: hiding collections (the first pass) now that the list filter works.
- Kids, belt and braces: for a kid's profile every collection card and every collection grid title also passes `RatingCeiling.forTitle` against the profile ceiling, whether or not it is lowered (Plex already restricts managed users); unrated fails closed. A server-restricted kid keeps the collections the server gives him that pass.
- Paging never stops silently: a pager is bound to its session, so after an error (a reconnect throws `CancellationError`) one fresh pager from the same server position tries again at once; if that fails while titles show, placeholders stay and paging resumes on the next focus move or when the session is ready again.
- Grid layout: six 240 pt columns spread from x 80 to x 1840 (64 pt gaps). With the letter rail, a 96 pt gutter (56 pt rail plus 40 pt) is kept inside the right margin and the columns fill the rest (44 pt gaps); the Collections row uses the same columns and gap, so both end at the same edge, and is masked at that edge while the rail shows. The rail sits inside the 80 pt margin.
- Focus on the grid's first row scrolls the Collections row fully out of view (first row at y 72); focus on the header or a collection brings the page back to the top. No half-clipped row in the top margin.
- Letter rail: one highlight (the focused letter) while the rail has focus; the current letter is marked only when it does not; unfocused letters at body brightness. A native index was not used: SwiftUI on tvOS offers none for a lazy grid.
- Watched shows as a small tick on the poster, not "Watched" in the caption. A focused caption whose title needs two lines takes the subtitle's line, in the same height (grid posters and collection cards).
- Collection screen: a backdrop hero (the collection's art, else its first title's), name, summary when Plex has one, and the title count, then the grid.
- Empty and no-match states centre on the full width; with filters set, the message's "Clear filters" pill is the only clear action (the header chip hides).
- Page tint: yellow-green to green hues are held to saturation 0.45 and brightness 0.55 in `ArtworkTint.tint` (other hues keep 0.75 and 0.80), so a green poster no longer turns the page muddy green.
- Grid posters use the same `PosterCard` / `PerchCardButton` as Home (same ring and system highlight); nothing grid-specific.
- Grids load once the session is ready (the shell can show while it connects), never before.
- No page title on the Films and Series grids: the collapsed tvOS 27 sidebar shows the tab's name in its own capsule at the top left, which covered a title at the 60 pt margin. Pushed collection grids keep their title.
- DEBUG `-PerchInitialTab <tab>` opens a tab at launch (live screenshots); `-PerchLibraryProbe` runs the read-only browse probe once the session is ready.
- The fake household's server tokens name the switched user, and the fake server applies a little_kid restriction (U only), so kid UI tests exercise the server-side ceiling.
