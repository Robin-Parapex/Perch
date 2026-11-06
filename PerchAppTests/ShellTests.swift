import Foundation
import Testing

@testable import PerchApp

/// WP-13: the app-level focus memory and the double-tap Back timing.
@MainActor @Suite("Shell")
struct ShellTests {
    @Test func focusMemoryIsPerProfileAndScreen() {
        let memory = FocusMemory()
        let robinHome = FocusMemory.Scope(profileID: "1001", screen: HomeFocus.screen)
        let samHome = FocusMemory.Scope(profileID: "1003", screen: HomeFocus.screen)
        let robinFilms = FocusMemory.Scope(profileID: "1001", screen: "films")
        let card = HomeFocus.card(row: "plex.continueWatching", item: "1001")
        memory.record(card, in: robinHome, group: card.rowID, item: card.itemID)
        #expect(memory.lastFocus(HomeFocus.self, in: robinHome) == card)
        #expect(memory.rememberedItem(group: "plex.continueWatching", in: robinHome) == "1001")
        #expect(memory.lastFocus(HomeFocus.self, in: samHome) == nil, "another profile starts fresh")
        #expect(memory.lastFocus(HomeFocus.self, in: robinFilms) == nil, "another screen starts fresh")
        #expect(memory.lastFocus(String.self, in: robinHome) == nil, "a different focus type reads nothing")

        memory.record(HomeFocus.hero, in: robinHome)
        #expect(memory.lastFocus(HomeFocus.self, in: robinHome) == .hero)
        #expect(memory.rememberedItem(group: "plex.continueWatching", in: robinHome) == "1001", "the row keeps its card")

        memory.forget(robinHome)
        #expect(memory.lastFocus(HomeFocus.self, in: robinHome) == nil)
        #expect(memory.rememberedItem(group: "plex.continueWatching", in: robinHome) == nil)
    }

    @Test func doubleBackNeedsTwoPressesInsideTheWindow() {
        var timer = BackPressTimer()
        let results = [10.0, 10.3, 10.5, 11.0, 11.35].map { timer.press(at: $0) }
        // Second press within 0.4 s doubles; a third starts again; 0.5 s later is too slow; then within again.
        #expect(results == [false, true, false, false, true])
    }
}
