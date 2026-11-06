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

- Films (section 16): 490 unfiltered; PG set (PG only) 1; firstCharacter follows the filter (27 buckets/490 to 1/1, sum equals total); `contentRating!=` (9 values) honoured, 1; collections: 94 unfiltered, 0 with the PG filter; collection children ignore the filter (20 and 20).
- Series (section 18): 132 unfiltered; PG set (TV-G, TV-Y) 4; firstCharacter follows (24/132 to 4/4); `contentRating!=` (10 values) honoured, 4; no collections.
- First run found `collections?type=1` returns the section's films, not collections: the `type` item is removed and the mapping keeps only `type == collection` rows (PerchPlex, test updated).
- First live launch also showed "Couldn't reach your library": the grid loaded while the session was still connecting. Grids now load when the session is ready, and retry when it becomes ready after a failure.

## Decisions

- Library grids in 0.3 use native `Menu`s for sort and filters (one value per menu), with a slim chip style (`PerchChipButtonStyle`, 52 pt) rather than the 68 pt action pills, because a header holds up to eight. Rejected: a side panel of filters (one more layer of focus for no gain).
- A letter jump reloads the grid from that letter's offset (the first item is the letter's first title, so focus lands on it). Titles before it are reached through the rail, not by scrolling up. Rejected: a sparse grid holding every position, which needed placeholders for unloaded gaps and a pager per window.
- The rating ceiling on library grids: a content-rating set only when Perch's ceiling is below the service's; otherwise nothing is sent and the server's own restriction stands (so unrated titles stay visible to adults). `RowContext.admits` guards every page, and a failed ratings lookup admits nothing.
- Select on a film in a grid resumes it when started, else plays from the start; a series plays its first unwatched episode, else S1 E1 (Home's rule), until WP-11's title pages. Long-press marks watched or unwatched (the first context menu in the app).
- The Collections row shows only while no filter is set; a collection is also a filter chip. With a lowered ceiling the row and chip are hidden: the live server returns no collections under a content-rating filter and ignores it on children, so Perch cannot tell which collections are safe without fetching each one (fails closed). A server-restricted kid (Plex restriction) still sees the collections the server gives him, and every collection's titles pass the final guard.
- Grids load once the session is ready (the shell can show while it connects), never before.
- No page title on the Films and Series grids: the collapsed tvOS 27 sidebar shows the tab's name in its own capsule at the top left, which covered a title at the 60 pt margin. Pushed collection grids keep their title.
- DEBUG `-PerchInitialTab <tab>` opens a tab at launch (live screenshots); `-PerchLibraryProbe` runs the read-only browse probe once the session is ready.
- The fake household's server tokens name the switched user, and the fake server applies a little_kid restriction (U only), so kid UI tests exercise the server-side ceiling.
