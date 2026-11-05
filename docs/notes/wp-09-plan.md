# WP-09 Basic Home: plan

Lead: Fable (design and judgement only; no Swift edits by the lead). Branch `wp-09-home` from `6400a21` (WP-08 merge). Spec: `docs/design/wp-09-home.md`. Started 5 Nov 2026.

## Slices (one owner per file, at most three helpers at once)

| Slice | Owner | Files | Depends on |
|---|---|---|---|
| A. Data | builder (Sonnet) | PerchCore `MediaModels.swift` (`summary`), `ModuleRegistry.swift` (`homeRowProviders` sorted by order then id), PerchPlex `PlexLibraryMapping.swift`, package tests; `PerchApp/Debug/FakeHouseholdTransport.swift` (clearLogo on film 1001, `-PerchFakeEmptyLibrary`) | none |
| B. Design | builder (Sonnet) | PerchDesign `HeroCard.swift` (metadata line, fixed synopsis height, text fallback), new `HeroMessage.swift`, new `ProfileMenuButton.swift`, `PerchCardButton.swift` (caption overlap), `DesignGallery.swift` (composed Home section), PerchDesign tests | none |
| C. Home screen | solver (Opus) | new `PerchApp/Features/Home/*` (HomeView, HomeModel, hero, rows, strings, focus memory, launch signpost), `AppRoot.swift`, `PlaceholderView.swift` (setup re-run flow extracted, placeholder removed), delete `LibraryCheckView.swift` and `-PerchLibraryCheck`, `PerchAppTests/HomeModelTests.swift` | A, B |
| D. Tests | tester (Sonnet) | `PerchUITests/HomeUITests.swift` (new), `ArtworkUITests.swift` (rewired to Home), delete `LibraryCheckUITests.swift`, PerchCore row-ordering test if A left a gap | C |
| E. Verify | verifier (Sonnet) | none (gate, screenshots S1 to S12, R1, R2, launch timing) | D |
| F. Records | scribe (Sonnet) | CHANGELOG, DECISIONS, wp-09-report | E |

## Fixed interfaces (so slices can run apart)

Accessibility identifiers: `home.root`, `home.hero`, `home.hero.action` (Play or Resume), `home.hero.title`, `home.row.<rowID>` (for example `home.row.plex.continueWatching`), `home.card.<itemID>`, `home.profileMenu` (label carries the profile name and keeps `home.profileName` on the text), `home.switchProfile`, `home.runSetup`, `home.message` (hero message block), `home.message.primary`, `home.message.secondary`, `home.retry` (the Try again button), `home.serverDown` (the offline corner notice text), `home.setupRefused`, `home.setupPIN`. No `ProgressView` anywhere on Home.

Launch signpost (DEBUG only): one log line `perch.launch home-first-frame=<ms>` on the first Home frame, measured from process start (kinfo_proc start time).

Row order: `ModuleRegistry.homeRowProviders` returns `.home(order:)` providers sorted by order, then id.

## Checklist

- [ ] A data slice green (package tests)
- [ ] B design slice green (PerchDesign tests, gallery section)
- [ ] C Home screen builds, HomeModel tests green, first frame from cache
- [ ] D UI tests green on 11ACEAE4 (focus, Back, two-click resume, no spinner)
- [ ] E gate green; S1 to S12, R1, R2 captured; three warm launch timings under 1.5 s on the live simulator
- [ ] lead judged screenshots against the spec; fixes applied
- [ ] reviewer (Opus) once on the whole diff; real defects fixed
- [ ] F CHANGELOG, DECISIONS, report; PR opened and readied; push on Robin's word
