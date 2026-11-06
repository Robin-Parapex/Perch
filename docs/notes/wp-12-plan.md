# WP-12 Search: plan and notes

Branch `wp-12-search` from main 0baa0de (WP-13 sidebar, WP-10 grids, WP-11 title pages). Built by the WP-12 solver
(Claude) from the lead's approved brief, 6 Nov 2026.

## What it does
- **Search tab** (`PerchApp/Features/Search/SearchScreen.swift`): SwiftUI `.searchable(text:)` on the tab's root, so
  tvOS shows its own search field and keyboard; holding the Siri button with the field focused dictates into it
  (SPEC 7, DESIGN:21). No custom keyboard.
- **Results** in rows below the keyboard: Films and Series (`PosterCard`), Episodes (`LandscapeCard`, episode title
  over "Series · S1 E3"), Collections (`PosterCard`, adults with the server's own ceiling only).
- **Select** opens a film's title page or a series page; an episode plays at once (resuming when started), as on
  Home. **Play/Pause** plays at once, as on the grids (a series plays its next episode via `SeriesNext`). Long-press
  on an episode offers "Go to series".
- **Debounce** 300 ms; each keystroke cancels the request in flight or waiting. A stale answer never replaces newer
  results (checked against the current query after the await).
- **No spinner:** the previous results stay while the next query loads. Nothing typed: Home's Recently added row
  (review pass; the first build had a quiet hint). Nothing found: "No matches" with the query. Failure with nothing shown: "Search isn't available
  right now"; with results shown, they stay.
- **State:** `SearchStore` keeps the current profile's `SearchModel` (query, results) for the app's lifetime, so leaving
  the tab or opening a page and coming back finds them. A different profile, ceiling or role gets a new, empty model:
  a profile switch clears the search. Focus is recorded in `FocusMemory` (scope "search"); Back from a page or the
  player restores the result it was opened from.

## PerchPlex
- `PlexEndpoints.search(base:token:query:limit:contentRatings:)`: `GET /hubs/search?query=&limit=&includeCollections=1
  &includeExternalMedia=0[&contentRating=]`, token in the `X-Plex-Token` header only, a literal "+" sent as %2B.
- `PlexLibrary.search(query:limit:contentRatings:)` maps hubs to `PlexSearchResults` (films, series, episodes,
  `PlexSearchCollection`s with section and kind). Hub type and item type must agree; duplicates dropped; people,
  music and other hubs ignored. Collections are read from `Metadata` or `Directory` rows (`PlexWireHub.directory`).
- Blank query or an empty rating set asks for nothing.

## Rating ceiling (PERMISSIONS 70)
- Every result passes `LibraryQueryBuilder.guardCollectionItems`: `RowContext.admits` (filters when the ceiling is
  lowered; unrated counts as 15) and, for a kid, the certificate check against the profile ceiling whatever the server
  returned, unrated failing closed.
- A lowered ceiling sends `contentRating=` only if the server honours it on search (`SearchModel.serverHonoursRatingFilter`,
  set from the probe); the admitted set is the union of the film and series sections' admitted ratings, loaded once per
  model. A failed lookup sends no filter; the client guard still holds.
- Collections carry no certificate: a kid or a lowered ceiling sees none in search.

## DEBUG
- `-PerchSearchProbe`: logs group counts (films/series/episodes/collections) for "the" and "a", unfiltered, with the PG
  ceiling's ratings, and with an impossible rating, plus the unfiltered request time. Counts only.
- `-PerchSearchQuery <text>`: the search starts with this query (live screenshots).
- Fake household serves `/hubs/search` (substring match, `contentRating=` and `limit` honoured, restricted users see U
  only). `-PerchFakeSearchIgnoresRestriction` makes it leak every title to a kid, so the UI test proves the app's guard.

## Live findings (6 Nov 2026, signed Debug on the live simulator)
- `-PerchSearchProbe`: the PG ceiling admits 5 rating labels across the film and series sections. "the": 20/20/20/20
  (films/series/episodes/collections; the limit is per hub) in 175 ms, the same with the PG set and with an impossible
  rating. **`/hubs/search` ignores `contentRating=`**, so `serverHonoursRatingFilter` stays false and the client
  guard is the only filter. "a": 0/0/0/0 (the server returns nothing for a single letter; a one-letter query shows
  "No matches").
- A query present at launch (`-PerchSearchQuery`, and equally one restored or typed while connecting) failed because
  the session was not ready, and stayed failed. Fixed: `SearchModel.sessionReady()` re-runs a failed query when the
  session becomes ready (SearchScreen `.task(id: sessionReady)`), with a model test.
- Results rows sat at x 160 (the searchable content is already inset; `Row` adds 80 pt); pulled back 40 pt to line up
  with the keyboard's first key.

## Tests
- PerchPlex `PlexSearchTests` (7): URL building, encoding, rating filter, decoding and grouping, blank queries.
- PerchAppTests `SearchModelTests` (14): retry when the session becomes ready, the library's cancellation as a
  failure, an edited query run on ready, one retry for a failure while ready, adult collections without section, debounce, stale answers, results kept while loading, blank query, no results,
  kid guard with a leaking server, lowered ceiling with and without the filter, adult, per-profile store.
- PerchUITests `SearchUITests` (4): type, results, Select a film, Back to the same result, leave and return; Play/Pause
  a result, Back from the player to the same card; no results;
  kid with a leaking server sees no 15/18 title.
- Manual (Robin): with the search field focused, hold the Siri button, say a title, results appear.

## Decisions
- Search uses `.searchable` on the Search tab's root view, not `Tab(role: .search)`, to keep the WP-13 sidebar as is.
- Episodes play on Select (as on Home); films and series open their pages; Play/Pause plays everything.
- Collections appear only for adults whose ceiling is the server's own; kids and lowered ceilings see none in search.
- The search is kept per profile in memory only (not across launches); a profile switch clears it.
- A failed admitted-ratings lookup sends no filter (the client guard holds), rather than showing "No matches".
- No `contentRating=` is sent on search: the live server ignores it (probe). The code path stays behind
  `SearchModel.serverHonoursRatingFilter` in case a later server honours it.
- A failed search re-runs when the session becomes ready; there is no retry button (typing again also retries).
  Review pass: ready also re-runs a query whose results are not on screen (edited while connecting), the library's
  own `CancellationError` (session changed under the request) counts as a failure, and a failure while the session
  is ready gets one retry after 1 s.
- Search aligns with the keyboard's left edge (rows pulled back 40 pt, to about x 120), not the 80 pt margin: the
  system's divider sits on 80. Messages are centred on the screen (x 960); only the rows are offset.
- Nothing typed shows Home's Recently added row (same guard), no hint: the field's placeholder and the system's
  "Hold to dictate" already say what to do. No data, nothing below the keyboard.
- Rows use Home's `RowList` and `Row` as they are (36 pt between rows, Row's own title-to-card spacing).
- Poster captions: title, then the year; focused, a long title takes both lines (`expandsTitleWhenFocused`, as on
  the grids), so nothing below moves. Episodes keep title over series and number.
- Search has a plain base background, no artwork tint.
- The Search view's identity is the profile plus ceiling plus role (also the Films and Series grids), so a changed
  ceiling makes a new model.
- An adult keeps a collection the server sent without its section or type; it opens with fallbacks the collection
  page does not use at the server's ceiling. Kids and lowered ceilings still see no collections.
- The teen and managed-account restriction on `/hubs/search` is left to the server and is unverified live (no such
  account in the household); the client guard covers kids and lowered ceilings only.
