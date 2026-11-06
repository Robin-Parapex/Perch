# DESIGN

The bar is the Apple TV app on tvOS 26. If a choice wouldn't look at home there, don't make it. Read this before building any screen.

## Design language

- **Dark, cinematic, content first.** Backgrounds are near-black (`#0b0b0f` base) tinted by the focused title's artwork. UI chrome is translucent system material, not painted panels.
- **Native materials.** Use tvOS 26 system materials (Liquid Glass where the system offers it, `.ultraThinMaterial` / `.regularMaterial` otherwise) for overlays, menus, quick controls and the doorbell panel. Never fake glass with a static gradient.
- **Typography.** SF Pro via system fonts. Title logos replace text titles wherever a logo exists. Sizes: hero title 96 pt (logo height ~140 pt), section headers 26 to 30 pt semibold, body 26 pt, metadata 22 pt, badges 18 pt. Nothing under 17 pt. Ten-foot rule: readable from 3 m.
- **Colour.** White text at 85 to 100% on dark; secondary at 55 to 65%. One accent at most, taken from artwork. No brand colours of our own competing with posters.
- **Spacing.** 80 pt safe margins left and right, 60 pt top. Row gap 36 pt, item gap 24 pt. Posters 2:3 at 180 x 270 pt in rows, 240 x 360 pt in grids; landscape cards 16:9 at 336 x 190 pt.
- **Badges and pills.** Thin 1 pt outlined pills for format badges (4K, Dolby Vision, Atmos, HDR10+, certificate). Solid white pill for NEW. Keep to three badges per card.
- **Buttons.** White pill primary (dark text), translucent material secondary. Icon + label. Minimum 68 pt tall. One primary per screen.

## Focus and the remote

- Use the system focus engine. Focused cards scale 1.05 to 1.08 with a white ring and a long soft shadow; parallax via `hoverEffect`/`focusEffect` on layered images (poster, logo, glow layers).
- Focus restoration: every screen remembers its last focused item; Back lands there.
- Never trap focus. Overlays take focus on appear and hand it back on dismiss.
- Remote mapping inside the app: clickpad navigates; Select plays or opens; Back closes or goes up one level (never to Home unless already at the top); Play/Pause toggles playback; long-press Play/Pause opens quick controls on browsing screens (inside the player the system owns it, so quick controls live in the info panel); long-press Select on a card opens the context menu; double-tap Back goes Home. TV/Home button is Apple's and cannot be remapped.
- Siri button: dictation into any focused text field. Search uses the system keyboard so this works for free.

## Motion

- Default spring: response 0.45, damping 0.85. Crossfades 0.3 s. Nothing bounces.
- **Hero load:** backdrop fades in 0.5 s with a 20 s slow pan (Ken Burns, 4% scale). Logo scales from 0.96 to 1.0 and fades over 0.4 s, 0.1 s after the backdrop. Text and buttons slide up 12 pt and fade in 0.1 s later.
- **Trailer crossfade:** after 4 s of continuous focus on the hero, the backdrop crossfades (0.8 s) to the muted trailer; leaving focus crossfades back.
- **Poster to detail:** the poster card expands into the detail hero (matched geometry), backdrop fades under it. Back reverses it.
- **Rows:** horizontal scroll snaps to items; the focused row lifts slightly (4 pt) and others dim 10%.
- **Player end state:** video scales to 640 x 360 top-right over 0.5 s as picks fade in from the left.
- **Overlays:** doorbell panel slides 24 pt from the right edge and fades, 0.35 s. Corner notices slide down from the top-left.
- Respect Reduce Motion: replace scale and pan with fades.

## Artwork

- Resolution order: Admin override -> fanart.tv (logos, clearart, backgrounds) -> TMDB -> Plex.
- Pre-fetch the next row's images and the focused item's backdrop and logo; decode off the main thread; show a blurred low-res placeholder, never a grey box.
- Tint: extract dominant colours from the focused backdrop and tint the page background 8 to 12% so each title feels different.
- Kids' profile: brighter, rounder cards (radius 16 pt instead of 12), larger type, no horror artwork in seasonal rows.

## Screens (visual notes)

- **Profile picker:** centred avatars 200 pt, name beneath, focused avatar scales 1.1. Kids' avatar with a small lock glyph.
- **Sidebar:** the system tvOS 26/27 sidebar (SwiftUI sidebar-adaptable `TabView`), as in the Apple TV app. Collapsed, it is the system's tab pill at the top left (current tab's icon and name), with no avatar. Expanded on focus: a glass panel with icons and labels, the profile avatar and name at the top, left-aligned with the item column (tvOS 27 `tabViewSidebarHeader`). Content keeps its own 80 pt margin and does not shift; the hero backdrop runs underneath the panel, and while the panel has focus the hero's text fades back so it never reads through the glass.
- **Home:** hero + rows as `SPEC.md` 3.
- **Title page:** hero takes 60% height; cast circles 150 pt; rails below. The primary button is the first focus.
- **Person page:** backdrop from best-known title with heavy bottom gradient; 300 pt portrait left; bio max 3 lines with "More".
- **Player:** native transport. Custom additions sit in the info panel row: Skip, Audio, Subtitles, Lights, Who's that? (2.1). Skip Intro/Credits appears bottom-right as a material pill with a 6 s auto-hide.
- **Doorbell overlay:** 760 pt wide material panel, top-right; snapshot then live video 16:9; two equal actions (Unlock for parents, Dismiss); auto-dismiss ring on the Dismiss button.
- **Quick controls:** half-height sheet from the top with room name, light sliders as pills, scenes as chips, volume. Opened by long-press Play/Pause while browsing, or the Lights action in the player's info panel; over playback the video dims 30%.
- **Ask:** single bar 1200 pt wide centred; results as standard rows with a one-line reason under each title; suggestion chips at the bottom.
- **Setup wizard:** one question per screen, large native text fields, progress dots top-right, Skip for now as a secondary button, a short line under each field saying where to find the value.
- **Guide:** coach marks as a dimmed screen with one highlighted region, a single sentence in a material card, Next and Skip; the assistant avatar (placeholder Pip) at 120 pt beside the card.
- **Year in review:** full-screen cards, one stat each, auto-advancing every 5 s, swipe to control, big numbers (160 pt).

## Copy

- Short, warm, plain English. Sentence case. No exclamation marks. No jargon (`GLOSSARY.md`).
- Request states: Requested / Getting it ready / Some episodes ready / Ready to watch / Couldn't find this yet.
- Errors are actions: "Couldn't play this. Try again" not "Stream failed (HTTP 502)".

## Premium checklist (run before calling a screen done)

1. Launch to Home in under 1.5 s warm, no spinner.
2. Every focus move is 60 fps on hardware; no image pop-in on the first row.
3. Logo present for every hero in the test library; fallback text looks intentional.
4. Back returns to the exact item on every screen.
5. All text readable from 3 m; contrast >= 4.5:1.
6. Overlays use material, take and return focus correctly, and work during playback.
7. Reduce Motion honoured.
8. Nothing on screen names a backend.
