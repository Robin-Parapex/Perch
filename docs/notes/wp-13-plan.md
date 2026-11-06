# WP-13 Sidebar and navigation: what was built and why

5 Nov 2026. Branch `wp-13-sidebar`.

## Built

- `PerchApp/Features/Shell/MainShell.swift`: replaces Home's shell. Sidebar-adaptable `TabView` (Home, Films, Series, Search, Settings; SF Symbols, sentence case), one NavigationStack per tab with its own path. Profile resolution, the per-profile Home model and the avatar load moved here from WP-09's HomeScreen (now `HomeStore.swift`). Kid profiles set `PerchStyle.kids` on the whole shell, sidebar header included.
- Sidebar header (tvOS 27 `tabViewSidebarHeader`): `SidebarProfileButton` (PerchDesign; was ProfileMenuButton) opens the profile picker.
- `PerchApp/Features/Settings/SettingsView.swift`: profile with Switch profile; Run setup again behind the Admin PIN, or the kid's "Ask a parent to change setup"; DEBUG Design gallery pushed on the Settings stack.
- Films, Series, Search: `PerchEmptyState` (PerchDesign) at HeroMessage scale (64/26 pt), title "Films" with "Browse your films here soon." (Search: "Search is on its way."), no buttons.
- Picker and Admin PIN: `perchFullScreen` (PerchDesign, a crossfading modal on `FocusTakingOverlay`), so focus moves in, the sidebar cannot be reached, Back closes, and focus returns to the trigger.
- Back rules: HomeView handles card to hero; the system moves focus from a tab root to the sidebar; `BackPressMonitor` (a non-cancelling Menu tap recogniser on the window) reports double-tap Back; the TabView's exit command makes Back in the sidebar a double press to leave, which returns to Home's root.
- `FocusMemory`: app-level, keyed by profile and screen, with per-group (row) items. Home records into it and uses it for `defaultFocus(priority: .userInitiated)`, so focus coming back from the sidebar lands on the last item.
- Gallery: "Sidebar and empty states" section and a full-screen overlay button.

## Why these shapes

- Each tab's root sits in `Color.clear.overlay { }`: Home's full-bleed scroll view inside a sidebar tab's NavigationStack otherwise grew 80 pt wider each layout pass (blank screen, 100% CPU).
- Full-screen presentations rather than in-tree swaps: in-tree overlays never take focus on tvOS 26+ (WP-03 finding) and would leave the sidebar reachable.

## Known gaps

- tvOS 27 gives the sidebar the first focus when the shell appears; SwiftUI and UIKit focus requests to the hero are ignored while the sidebar holds it. Accepted: launch lands on the sidebar's Home item, one Right from the hero (DECISIONS WP-13).
- Back in the sidebar needs a second press within 2 s to leave the app; the first shows a hint (Robin, 5 Nov 2026).
- "Right from Settings does not enter it" was the tests: Select already enters, the extra Right did nothing, and Down from Switch profile found nothing below it, so the focus helper wandered Left into the sidebar. Fixed with full-width focus sections in Settings.
- Nothing focused means Menu leaves the app. Empty tabs (focusable page, no effect) and pushed screens (`PushedScreen`: UIKit focus update once up, explicit pop on Back) now always hold focus.
- Double-tap Back from a pushed screen lands on Home's root with focus on Home's sidebar item (the second press reaches the sidebar first); one Right reaches the hero.
- Search is a plain tab, not `Tab(role: .search)`; WP for search decides.
- Needs a hardware look: Run setup again from Settings, where the Admin PIN keypad's full-screen dismissal is followed at once by the swap to the setup wizard. On the simulator it reads as one transition; check on the Apple TV that the two do not stutter or flash the shell between them.
- Review fixes (6 Nov 2026): the avatar clears and reloads per profile (no stale face); a profile change resets every tab's stack and selects Home; Settings treats an unresolved profile as a kid; double-tap Back disarms the leave hint; the hint moved top left, right of the expanded panel; the hero text fades back while the sidebar has focus; the avatar header is left-aligned. The dark block at the bottom right of the Home hero is the fake household's test card (`FakeHouseholdTransport.solidPNG` draws a 45% black corner block to judge crops), not a view.
