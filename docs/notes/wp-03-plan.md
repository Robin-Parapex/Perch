# WP-03 PerchDesign: plan

## Context
WP-03 is the third of five WPs in 0.1.0 (ROADMAP:47). Today `Packages/PerchDesign` is a stub. Every later screen (wizard, Home, title page, doorbell overlay) needs shared tokens and components so the app looks consistent and native from the start. WP-03 delivers tokens, materials, focus styles, the core components, overlay containers, Reduce Motion variants, and a debug-only gallery to see them on the Apple TV. It does not end the version, so there is no release or tag.

Branch `wp-03-perchdesign`, commits `feat(WP-03): ...`, one PR against main.

## Decisions I am taking (recorded in DECISIONS.md)
1. **Dark only.** DESIGN.md is dark only; `project.yml` changes `UIUserInterfaceStyle` from Automatic to Dark (regenerate project).
2. **Liquid Glass always.** Minimum is tvOS 26, so chrome uses `.glassEffect()`; no fallback materials.
3. **Focus = system highlight.** Artwork uses the system highlight hover effect (lift, shadow, parallax, as in the TV app), plus DESIGN's white focus ring (3 pt stroke). Labels below artwork do not scale. Reduce Motion is then handled by the system for focus.
4. **Reduce Motion rule:** scale, Ken Burns and slides become 0.3 s crossfades; row lift becomes dim-only. One pure function `PerchMotion.resolve(_:reduceMotion:)` so it is testable.
5. **No images library yet.** Components take a generic artwork view (`@ViewBuilder`), so WP-08 can pass Nuke views without PerchDesign depending on Nuke. Gallery uses generated gradients and SF Symbols as placeholder art.
6. **Availability wording lives in PerchCore.** `TitleAvailability` enum (Requested / Waiting for a parent, Getting it ready + optional progress, Some episodes ready, Ready to watch, Couldn't find this yet) with GLOSSARY strings, because Seerr and Plex modules may import PerchCore only. PerchDesign renders it.
7. **Gallery flag:** compiled only in `#if DEBUG` (never in TestFlight). Opened from a "Design gallery" button on the debug placeholder, or straight in with launch argument `-PerchDesignGallery`. Back returns to the placeholder.
8. **Out of scope:** the overlay UIWindow host (PerchPlayer, WP-07) and FocusCoordinator / per-screen remembered focus (app, first real screen). WP-03 overlays are SwiftUI containers only.
9. **Kids style** via an environment value (`perchStyle = .kids`): radius 16, brighter cards, larger type.

## Files (PerchDesign unless noted)
- `Tokens/`: `PerchColor` (base #0b0b0f, text 100/85/60%, page tint 10%), `PerchFont` (hero 96, section 28 semibold, body 26, metadata 22, badge 18; floor 17), `PerchSpacing` (margins 80/60, row gap 36, item gap 24), `PerchRadius` (12, kids 16), `PerchSize` (poster row 180x270, grid 240x360, landscape 336x190, button min height 68), `PerchMotion` (spring 0.45/0.85, crossfade 0.3, hero stagger 0.5/0.1/0.1, Ken Burns 20 s 4%, panel 0.35 s/24 pt).
- `Environment/`: `perchStyle`, `perchTint` (artwork accent, default none), `PageBackground` (base + tint).
- `Focus/`: `PerchCardButtonStyle` (highlight + ring), `PerchPrimaryButtonStyle` (white pill, dark text), `PerchSecondaryButtonStyle` (glass), focus ring modifier.
- `Components/`: `Pill` (outlined format pill, solid NEW pill, availability pill with progress), `BadgeStrip` (caps at three), `PosterCard` (row/grid size, title, optional progress, badges, availability), `LandscapeCard` (16:9, progress + "31 min left"), `Row` (header + `ScrollView(.horizontal)` + `LazyHStack` + `.focusSection()`, after Dusk MediaCarousel), `RowList` (vertical stack; focused row lifts 4 pt, others dim 10%), `HeroCard` (backdrop with Ken Burns, logo or text title, badges, 2-line synopsis, action slot, staged entrance).
- `Overlays/`: `SidePanel` (760 pt, top-trailing, slide 24 pt + fade), `CornerNotice` (top-leading, slides down), `TopSheet` (half height, dims behind 30%), `CornerPill` (bottom-trailing, optional auto-hide). Each takes focus on appear via `defaultFocus`.
- `Gallery/DesignGallery.swift` (`#if DEBUG`): one section per component, kids toggle, overlay demo buttons.
- PerchCore: `Availability/TitleAvailability.swift` + tests.
- App: `PerchMain.swift` / `PlaceholderView.swift` (gallery entry, base colour from token), `project.yml` (Dark).
- `PerchUITests`: gallery test.
- Docs: `CHANGELOG.md` Unreleased, `DECISIONS.md` (items above), `THIRD_PARTY_NOTICES.md` unchanged unless code is copied (ideas only, with one-line source comments).

## Build order (helpers)
1. **builder A:** tokens, environment, focus/button styles, Pill, BadgeStrip, `TitleAvailability` in PerchCore. **tester** alongside: token values match DESIGN numbers, badge cap, kids radius, motion resolver, availability strings match GLOSSARY and contain no backend jargon.
2. **builder B** (cards, Row, RowList, Hero) and **builder C** (overlays) in parallel, disjoint files.
3. **builder D:** gallery, app entry, project.yml, UI test.
4. **verifier:** `scripts/gate.sh` (xcodegen drift check, every package's tests, UI tests).
5. **reviewer** (Opus) once on the full diff. **scribe** for CHANGELOG and DECISIONS.

## Verification
- `scripts/gate.sh` green; no new warnings.
- UI test: launch with `-PerchDesignGallery`, gallery visible, remote right/down moves focus, Menu returns to "Perch".
- **On the Apple TV 4K (Debug, Xcode over network):** walk the gallery; focus lift, ring and parallax on posters; rows snap and dim; hero entrance; each overlay takes focus and Back returns it; repeat with Reduce Motion on. I will need Robin to judge the focus feel by eye.
- Then PR via `/pr open` (draft). Push needs Robin's word.
