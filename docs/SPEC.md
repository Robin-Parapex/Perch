# SPEC

What Perch does, screen by screen. This is the *what*. The *how* is planned stage by stage (see `ROADMAP.md`). Each feature carries its target version in brackets so you can tell what belongs to the current stage.

Household: two adults, one young child (kids' profile). Primary device: Apple TV 4K in the living room / theatre room. Content: Plex library, Apple TV+ (rare), Apple Music, Apple Fitness+ (rare). No Netflix, Prime or live TV.

---

## 1. Principles

- **Apple TV app feel.** Dark, cinematic, large artwork, few buttons, white focus ring, native materials. See `DESIGN.md`.
- **Nightly actions in two clicks.** Resume, next episode, request, cameras.
- **Say it in plain words.** Request states are "Requested", "Getting it ready", "Some episodes ready", "Ready to watch", "Couldn't find this yet". Service names only in the wizard, Settings > Integrations, Help and Admin (`GLOSSARY.md`).
- **Everything is per profile.** Rows, recommendations, permissions, AI limits, watch state.
- **Fail plainly.** A broken stream says "Couldn't play this" with Try again and offers something else to watch. No error codes in the family's face.

## 1a. First-run setup wizard

**[0.1 shell and Plex steps; later steps land with their modules]**
A full-screen, step-by-step wizard with progress, Back, and "Skip for now" on every optional step. Every text entry is a native tvOS text field, so the iPhone's keyboard prompt appears for long values like API keys. Re-runnable from Settings.

1. **Welcome.** One screen, what Perch is, Continue.
2. **Connect Plex.** Two routes: *Sign in with Plex* (a code on screen, enter it at plex.tv/link on a phone) or *Enter server address* (IP or hostname, port, token). Then choose a server if the account has several. Confirms with the server name and library count.
3. **Admin PIN.** "Use your Plex profile PIN" (the account owner's Plex Home PIN, verified by plex.tv, nothing stored) or "Set a Perch PIN" (app-specific, hashed in the Keychain). If the owner has no Plex PIN, a Perch PIN is required; the Admin PIN can never be empty. Explains what it protects.
4. **Profiles and roles.** Lists Plex Home profiles with proposed roles (owner and unrestricted profiles parent, restricted profiles kid) and the rating ceiling derived from Plex; editable (roles freely, ceilings only downwards).
5. **Seerr** [1.0]. Server address; signs in with each profile's Plex token, API key as fallback; shows which Perch profiles matched Seerr accounts.
6. **Library refresh.** Shown when Seerr was skipped: refresh on app start (off / all / chosen libraries), with the note that it wakes the server's drives.
7. **Trakt** [1.1]. Device code on screen, activate on a phone.
8. **Home Assistant** [1.3]. Address and long-lived token, then an import step: choose Areas (rooms), cameras, the doorbell entity and scenes to bring into Perch. Nothing else is imported. Frigate streams use the Frigate address if given; events come through Home Assistant.
9. **Tautulli** [2.2]. Address and API key.
10. **AI** [2.1]. Provider preset (OpenRouter, OpenAI, Anthropic, Ollama, Other), base URL, key, model name with free and cheap suggestions first, Test connection, budget, who may use it.
11. **Done.** Hands over to the welcome guide.

## 1b. Welcome guide and in-app assistant

**[1.0 guide; 2.1 Q&A]**
- After setup, an interactive tour presented by the in-app assistant (placeholder name **Pip**): coach-mark overlays that highlight the sidebar, Home rows, how to request, Settings, Admin, and where to change rows and profiles. Each step is one sentence and one highlight. Skippable, replayable from Settings > Help.
- The tour is scripted; it works with no AI configured.
- With AI configured [2.1], the guide gains a question box ("How do I hide a row?") answered from a short built-in help text, media-only guardrails applying.
- **What's new** screen on first launch of a new version, three bullets at most.

## 1c. Support and feedback

**[1.0]**
- Settings > Help > Send feedback. A text field the user dictates into with the Siri button (the Apple TV has no built-in microphone; Siri dictation is the voice route), a category (bug, idea, question), and an optional diagnostics attachment (app version, tvOS version, device, module status, the last 200 lines of the playback log, no keys ever).
- Delivery, in order of preference: the **Perch feedback endpoint** (a small service we run for everyone once the website exists; returns a reference number shown on screen), a **QR code** that opens a pre-filled GitHub issue on the phone (fallback when the endpoint is unreachable or not yet live), or a **webhook URL** set in Admin (Discord, Home Assistant, anything that takes a POST). The app never depends on the endpoint for anything else.
- Help also lists remote shortcuts, third-party notices, and the setup guides (including enabling the Plex connection in Sonarr and Radarr, and Match Content on the Apple TV).

## 2. Profiles and launch

**[0.1 picker, PINs, roles; 1.0 kids' behaviour and Settings]**
- On launch: Apple TV-style profile picker (avatars, names). Last profile remembered per Apple TV; a tap switches.
- Profiles map to Plex Home users (watch state lives in Plex) and to a role in the app: `parent`, `teen`, `kid`. Roles drive permissions (`PERMISSIONS.md`).
- **PINs come from Plex.** Switching profiles uses each Plex Home profile's PIN, verified by plex.tv; PINs are never stored. The owner's token and each switched profile's token are kept in the Keychain so relaunch resumes the last profile. See `MODULES.md`.
- **Admin PIN** (Integrations, AI, roles, Admin, door and alarm) defaults to the Plex owner's Home PIN; if the owner has none, a Perch PIN is required; a Perch PIN can also replace it at any time. Admin itself needs the parent role as well as the PIN.
- Kids' profile: leaving it always needs a PIN (the chosen adult's Plex PIN, or the Admin PIN if they have none). Content filtered to the profile's rating ceiling (derived from Plex Home restrictions, table in `PERMISSIONS.md`).

**Settings [1.0]** (per profile, gear in the sidebar): subtitle style (size, background), preferred audio language, preferred subtitle language, autoplay next episode, auto-skip intro and credits, do not disturb default, theme music on/off. Admin PIN: **Integrations** (one page per module with fields, Test connection, status badge), **AI** (provider, base URL, key, model name, per-feature toggles, monthly budget, per-profile limits and levels), **Profiles and roles**, **Admin PIN** (use Plex owner PIN, or set a Perch PIN), Admin (parent role required). See `MODULES.md`.

**[1.3]** Guided lock-in: document and support Single App Mode (supervised Apple TV) so the Home button can't exit the app on a kids' TV. Optional per device.

## 3. Home

**[0.2 basic, 1.0 complete]**
The screen the TV wakes up to. One vertical scroll of rows, hero at top.

- **Hero (animated title card).** Full-bleed backdrop with slow pan, title logo (fanart.tv / TMDB, text fallback), badges (4K, Dolby Vision, Atmos, rating), one or two lines of synopsis, Play / More info / Add. After ~4 s of focus the backdrop crossfades into the muted local trailer when one exists. Logo, text and backdrop are separate layers with slight parallax on the clickpad.
- **Rows (default order, per profile, user-reorderable in 1.2):**
  1. Continue watching (progress bars, "31 min left")
  2. Requested and now ready [1.0] (NEW badge, cleared once played)
  3. Up next in your series [0.2] (next unwatched episode per series)
  4. Recently added
  5. Because you watched X [1.2]
  6. For you tonight [2.1 AI] (time- and day-aware)
  7. Seasonal row [1.2 calendar-driven: Halloween, Bonfire Night, Christmas, Easter, summer; 1.3 weather-aware "Rainy day" variant once Home Assistant is connected]
  8. New on Netflix / Apple TV+ / Disney+ / BBC [1.1] (request, never opens other apps)
  9. Coming this week [1.1] (what's on its way, in plain words)
  10. Your October [2.2 Tautulli monthly recap]
  11. Family favourites / Not watched in a while [2.2]
  12. Browse by network [1.2, optional row, off by default]
- Never show a spinner on Home. Cached rows render instantly; refresh in place.
- **Navigation: a collapsible left sidebar**, as the Apple TV app has used since tvOS 17.2 (SwiftUI `TabView` with the sidebar-adaptable style). Tabs by version: 0.3 Home, Films, Series, Search, Settings; 1.0 adds Requests (Mine and Waiting lists, where parents approve); 1.1 expands it (Family, Ready, filters); 1.3 adds Music and House (home control). Keep it to eight items plus the profile avatar at the top. The sidebar menu also carries **Refresh libraries** (0.3).

## 4. Library browsing (Films, Series)

**[0.3]**
- Poster grid, alphabetical jump, sort (recently added, title, year, rating, unwatched), filters (genre, decade, resolution, unwatched, collection).
- Collections as rows and as a grid. Custom collections created in the app [1.2] ("Christmas", "Arthur's favourites") stored in the app's settings document, not in Plex.
- **Library refresh [0.3]:** Perch never scans Plex on a timer. Settings offer *refresh on app start* (off / all libraries / chosen libraries; runs after Home has rendered so launch stays instant; copy says it wakes the server's drives) and a *manual refresh* in the sidebar menu and Admin, per library or all, with Plex's progress shown. When Seerr is connected the on-start refresh defaults to off; when it isn't, the wizard asks.
- Series page: seasons rail, episode list with thumbnails, progress and "watched" ticks; "Play next" at the top always does the right thing.
- Poster badges: NEW [1.0]; 4K, DV, HDR10+, Atmos [1.2].

## 5. Title page (film or series)

**[0.3 for library items, 1.0 for titles not in the library]**
- Hero like Home. Metadata row: year, runtime or episode count, genre, certificate, rating.
- **One primary button that reflects state:** Play (in library) / Resume / Request / Latest season only / Requested / Getting it ready (progress) / Some episodes ready / Ready to watch / Couldn't find this yet.
- Secondary: Trailer, Add to watchlist, Mark watched, Audio and subtitles defaults for this title [1.3], "Is this OK for the kids?" [2.1 AI].
- Long press on Request: request for another profile, or request a specific season.
- Cast rail (circular portraits) -> Person page.
- Similar titles rail with small state tags: "In your library", "Request", "Getting it ready".
- Series theme music plays softly on the series page when available (Plex themes) [0.3 hook, on by default from 1.2]; off for kids by default.
- Fun stats [2.2]: "You've watched this 4 times", "Arthur's most watched".

## 6. Player

**[0.2 first playable, 1.0 complete]**
- AVPlayerViewController with the native transport, info panel, subtitle/audio menus, PiP where allowed.
- **Playback decisions:** follow the decision table in `ARCHITECTURE.md` (Apple's player can't open MKV, DTS, TrueHD or image subtitles directly; Plex remuxes or transcodes audio for those, and image subtitles need burn-in). Frame-rate and dynamic-range matching requested before playback starts.
- **Skip Intro / Skip Credits** from Plex markers, appearing at the right moment, auto-skip optional per profile.
- **Next episode countdown** at the credits marker: video shrinks, "Next episode in 10", Back cancels.
- **End-of-film picks [1.2]:** at the credits marker the video shrinks top-right and three "Because you watched" titles appear with Play or Request. Back keeps the credits full screen.
- **Lighting hooks [1.3]:** play, pause, credits, stop events go to Home Assistant (see section 9).
- **Player chrome and overlays:** the player is presented inside our own full-screen container, and alerts draw in a dedicated overlay window above it, so the doorbell can appear over playback. The player's own swipe-down info panel is kept; our additions (Skip, Audio, Subtitles, Lights, Who's that?) are custom actions in that panel, not a competing gesture.
- **Resilience:** if a stream fails (for example an expired debrid link), show "Couldn't play this" with Try again (parents: re-request through Seerr) and offer the next item in Continue watching. No automatic repair in the app-only design.
- **Per-title memory [1.3]:** preferred audio track, subtitle track, and (in 2.0) audio offset.
- **Second engine [2.0]:** VLCKit (TVVLCKit) used automatically for files the native player can't play well (MKV with DTS/TrueHD, PGS subtitles) and whenever the user sets an audio offset. Both engines share the same UI chrome so they look like one player.
- **Night mode [2.0]:** dynamic range compression toggle for late viewing (only in the second engine).

## 7. Search and Ask

**[0.3 search, 1.0 request results, 1.2 people, 2.1 Ask]**
- Native tvOS search with the system keyboard, so holding the Siri button while the search field has focus dictates straight into it (outside a text field the Siri button calls Siri; that's Apple's behaviour).
- Results in one screen: In your library [0.3] / You could request [1.0] / People [1.2]. Same Play-or-Request button everywhere.
- **Ask [2.1]:** the same bar accepts natural language ("something like Severance but lighter", "a family film under 100 minutes", "what's new this week", "pick something for the three of us"). Results are ordinary poster rows with a one-line "why" under each. No chat window. Also handles home commands in 2.3 ("dim the lights and close the blinds").
- Siri can't be invoked from the Apple TV home screen into our app (Apple restricts that), so all of this is inside the app.

## 8. Discovery and requests

**[1.0 requesting, states, approvals, ready row; 1.1 discovery rows, Coming this week, Requests tab]**
- Seerr is the single request path. The app talks to Seerr directly (signed in with the Plex token) and to Plex for availability. The app never talks to Sonarr, Radarr, Decypharr or the Usenet client; progress is whatever Seerr reports.
- **Where a request starts in 1.0:** the title page of any title found through search ("You could request" results) or reached from a Similar titles rail; "New on" and "Coming this week" rows arrive in 1.1.
- "New on <service>" rows [1.1] from TMDB watch-provider data (region GB) through Seerr's discover API, deduplicated against the library.
- Request states shown in plain words, with a progress bar where the pipeline reports one. Real-Debrid cached titles often land within minutes.
- **How "ready" is detected:** Perch watches **Seerr only**, and only while at least one request is in Requested or Getting it ready: every 30 s for the first ten minutes after a request, then every 2 minutes, then every 5, one small call each time, only while the app is open. Seerr marks a title available once Plex has indexed it; getting Plex to index new files is Sonarr and Radarr's built-in Plex connection (Settings > Connect > Plex Media Server, partial scan on import), which the setup guide tells the user to enable. Perch never scans Plex for this. An optional safety net in Admin, off by default, refreshes the matching Plex library once if a title has been "Getting it ready" for more than 15 minutes.
- "Couldn't find this yet" after 24 hours with no progress, or on a declined or failed state. Parents get "Try again" (re-request through Seerr).
- **Seerr identity:** each profile signs in to Seerr with its own Plex token, so requests carry that profile's Seerr permissions and approval rules. API-key fallback creates requests with the matching Seerr account set explicitly; a profile with no matching Seerr account cannot request and sees "Ask a parent".
- Request approval [1.0]: kids' and teen requests queue for a parent; parents get a corner notice and a badge on the Requests tab, and approve from its Waiting list (or from Seerr on a phone).
- Requests tab: [1.0] Mine and Waiting; [1.1] Family and Ready, filters. Each item shows the plain-words state.
- "Requested and now ready" row on Home with NEW badges, per profile [1.0].
- Optional notification to the requester's phone via Home Assistant when a title lands [1.3].

## 9. Home integration (Home Assistant and Frigate)

**[1.3 core, 2.3 extended]**
- Persistent WebSocket to Home Assistant from the app (`PerchHome`), subscribed only to the Areas, cameras, doorbell entity and scenes chosen in setup; `PerchCore` filters what each role may see and call.
- **Doorbell overlay:** on the doorbell event, pause playback (configurable), show a frosted panel with the latest snapshot immediately and the live go2rtc stream as soon as it opens, the event label, and actions: Unlock (parent, Admin PIN entered in the last 5 minutes), Dismiss. No two-way talk: the Apple TV has no built-in microphone (Continuity mic from an iPhone exists but needs the phone in hand, which defeats the point). Auto-dismiss after 30 s. Back dismisses and resumes playback.
- **Two alert levels:** full overlay (doorbell, alarm) and small corner notice (person on driveway, parcel, washing machine done; "dinner's ready" messages from phones arrive in 2.3). Corner notices are held back while a film is playing and delivered on pause or credits, unless flagged urgent.
- **Do not disturb** per playback: on by default for films, off for TV.
- **Playback-driven lighting:** scene per event (play -> dim, pause -> 30%, credits -> fade up, stop -> normal). Only in rooms the profile may control. Configurable per room.
- **Movie night scene:** one tile and one remote shortcut (lights, blinds, amp input, DND).
- **Quick controls panel:** long-press Play/Pause on any browsing screen; during playback, the "Lights" action in the player's info panel. Shows the room's lights, scenes, volume. Closes on Back. (Swipe down is the player's own info panel and is left alone.)
- **House tab:** cameras (live grid, today's events as a timeline), rooms, scenes. Role-filtered.
- **Bedtime prompt [2.3]:** Home Assistant can trigger a gentle "it's bedtime" overlay on the kids' profile at a set time, then pause.
- **Receiver lip-sync [2.3]:** if an AV receiver is in Home Assistant, expose its lip-sync delay in the quick panel.
- **Ambient screensaver [2.3]:** when idle: what's new, weather, family calendar, now playing. Replaces the Apple aerials only inside our app.

## 10. Person pages

**[1.2]**
- Reached from a cast circle, search, or "Who's that?" [2.1].
- Hero: backdrop from their best-known title, portrait, bio, age, birthplace (TMDB).
- Rows: **Top rated** (TMDB score with a vote-count floor), **For you** (their credits ranked against this profile's history), **In your library**, **Filmography** (chronological, each with Play / Request / state).
- "You've watched 7 of their films" and "Last seen in <title>" [2.2].

## 11. Recommendations

- **[1.2] Because you watched:** recent Plex history per profile -> TMDB similar/recommended via Seerr -> merged, deduplicated, ranked. Library items first, then requestable ones.
- **[1.2] Seasonal:** calendar-driven rows (Halloween, Bonfire Night, Christmas from 1 Dec, Easter, summer holidays, back to school) built from TMDB keywords plus the library; weather-aware variants from Home Assistant; "Released 25 years ago this week". Kid-safe variants for the kids' profile. Subtle seasonal hero treatment, kept tasteful.
- **[2.1] AI picks:** "For you tonight" (day and time aware), "Movie night picker" (choose who's watching, suggests what none have seen), auto-collections ("Rainy Sunday films") refreshed weekly, with one-line reasons.
- **[1.1] Trakt** optional, per profile (device OAuth): scrobbling, watchlist and history sync, and a better signal for recommendations and AI ranking.

## 12. AI features

**[2.1 unless noted]**
Provider-agnostic and bring-your-own-key: an OpenAI-compatible endpoint (OpenRouter, OpenAI, Groq, Ollama and others) or Anthropic, with the model name entered by the user, never hardcoded, free and cheap models suggested first (no Perch feature needs a frontier model). Features are token-light: daily batch jobs cached per profile, small on-demand calls, **no free chat**. Parent-only, with a toggle in Admin for teens; never for kids. Monthly budget, per-profile rate limits, per-feature toggles and a rating filter, all behind the Admin PIN. Details in `MODULES.md`.

**Guardrails:** a media-only system prompt; the model returns structured results (title IDs, filters, one-line reasons), never free prose; anything off-topic gets "I can only help with what to watch"; no automatic retries; everything counted against the budget.

**AI permission levels** (per profile, set in Admin):
1. **Recommend only** (default): results and reasons, nothing else.
2. **Can request:** may create Seerr requests, still subject to that profile's approval rules.
3. **Can navigate:** may open a title page, start playback, switch to a tab.
4. **Home actions** [2.3]: may run allow-listed home actions. Parents only, off by default, never for teens.

**Personal by profile:** ranking uses that profile's Plex watch history, watchlist, ratings, Trakt data if connected, and the time of day. Nothing crosses profiles.

- **Ask** (section 7): dictate "find me something funny from the 60s"; the model turns it into a structured query (genre, decade, mood, people, runtime) and a ranking; Perch runs it against the library and Seerr and shows ordinary rows.
- **Movie night picker.**
- **Previously on:** spoiler-free recap of where this profile is in a series, shown before resume.
- **Who's that?:** while paused, a button in the info panel. Uses the cast list and the subtitles up to the current timestamp only, so no spoilers. Links to the Person page.
- **Is this OK for the kids?:** violence, language, scary scenes, in three lines, before play.
- **Who's who:** spoiler-safe character guide for a series, limited to episodes watched.
- **Weekly digest row:** what arrived and why each might suit this profile.
- **Smart requests:** "get the next season of everything we're watching".
- **Doorbell summaries [2.3]:** Frigate GenAI descriptions in the alert.
- **Voice home control [2.3]:** home commands through Ask.
- **Abuse controls:** budget, rate limits, permission levels, content rating filter, request approvals, local call log in Admin.

## 13. Music

**[1.3]**
- Apple Music via MusicKit: library, playlists, search, now playing with artwork, AirPlay to speakers through the Apple TV.
- Music Assistant / Home Assistant media players exposed as targets if present (optional, same WP).
- Now playing shows in the ambient screensaver [2.3].

## 14. Stats and insights (Tautulli)

**[2.2]**
- **Year in review:** animated, Wrapped-style, per profile and for the family: hours, top series, top actors, longest binge, favourite film night.
- **Monthly recap row** on Home.
- **Fun stats** on title and person pages.
- **Rewatch rows:** Family favourites, Not watched in a while.
- Tautulli is connected with its address and API key (it has no OAuth); named only in the wizard, Settings > Integrations and Admin.

## 15. Admin (Admin PIN)

**[1.0 minimal, 2.2 full]**
- Hidden behind the Admin PIN. Admin is the one screen allowed to name services, because its reader is the person who runs them.
- 1.0: stuck requests (with "Try again"), Plex health (up, disk, active streams), module status, Refresh libraries, the optional 15-minute refresh safety net, playback log (decision, engine, failures) for the acceptance checks, local audit log, third-party notices.
- 1.2: artwork overrides (poster, logo, backdrop from TMDB, fanart.tv or a pasted ThePosterDB/MediUX URL), row order and visibility per profile, a date override for testing seasonal rows.
- 2.2: AI spend this month, audit log of home actions, Tautulli link status, full diagnostics.

## 16. Top Shelf and system integration

- **[1.0]** Top Shelf extension: full-width rotating banner deep-linking into the app. Top Shelf sits on the tvOS home screen, outside any profile PIN, so it is **always family-safe**: Recently added and Requested-and-ready filtered to the lowest rating ceiling in the household, plus Continue watching items only when they are within that ceiling. It reads Plex with the owner token shared through an App Group Keychain access group and applies the household's lowest ceiling itself.
- **[0.3]** double-tap Back -> Home. **[1.2]** long-press on a poster -> context menu (request for, mark watched, add to collection, who's in this). **[1.3]** long-press Play/Pause -> quick controls.
- **[1.0]** Deep links (`perch://title/<id>`, `perch://play/<id>`) for Top Shelf and Home Assistant automations.

## 17. Out of scope

- Public App Store release, App Review compliance, other households.
- Live TV, DVR, Netflix/Prime playback.
- Overlays over other apps (tvOS forbids it). HomeKit remains the fallback for doorbell when Apple TV+ is in use.
- Replacing the tvOS home screen. Single App Mode is the closest option, opt-in per device and only with Robin's approval (it erases the device).
- Two-way talk through the doorbell (no built-in microphone on the Apple TV).
