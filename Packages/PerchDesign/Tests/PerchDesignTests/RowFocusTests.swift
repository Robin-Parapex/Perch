import Testing
@testable import PerchDesign

@MainActor
struct RowFocusTests {
    @Test func trueForBThenFalseForAGivesB() {
        let context = RowFocusContext()
        context.report(rowID: "A", focused: true)
        context.report(rowID: "B", focused: true)
        context.report(rowID: "A", focused: false)
        #expect(context.focusedRowID == AnyHashable("B"))
    }

    @Test func falseForAThenTrueForBGivesB() {
        let context = RowFocusContext()
        context.report(rowID: "A", focused: true)
        context.report(rowID: "A", focused: false)
        context.report(rowID: "B", focused: true)
        #expect(context.focusedRowID == AnyHashable("B"))
    }

    @Test func movingWithinARowKeepsItFocused() {
        let context = RowFocusContext()
        context.report(rowID: "A", focused: true)   // card 1
        context.report(rowID: "A", focused: true)   // card 2 gains first
        context.report(rowID: "A", focused: false)  // card 1 loses
        #expect(context.focusedRowID == AnyHashable("A"))
    }

    @Test func lastFalseClears() {
        let context = RowFocusContext()
        context.report(rowID: "A", focused: true)
        context.report(rowID: "A", focused: true)
        context.report(rowID: "A", focused: false)
        context.report(rowID: "A", focused: false)
        #expect(context.focusedRowID == nil)
    }

    @Test func extraFalseNeverGoesNegativeOrClearsAnotherRow() {
        let context = RowFocusContext()
        context.report(rowID: "B", focused: true)
        context.report(rowID: "A", focused: false)
        #expect(context.focusedRowID == AnyHashable("B"))
        // A stayed at zero, so one true then one false still clears A cleanly.
        context.report(rowID: "A", focused: true)
        context.report(rowID: "A", focused: false)
        #expect(context.focusedRowID == nil)
    }
}
