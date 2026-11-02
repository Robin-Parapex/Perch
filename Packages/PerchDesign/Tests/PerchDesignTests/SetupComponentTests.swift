import Testing
@testable import PerchDesign

@Suite struct SetupComponentTests {
    @Test func progressLabel() {
        #expect(ProgressDots.label(current: 2, total: 6) == "Step 2 of 6")
    }

    @Test func initialsFallback() {
        #expect(ProfileAvatarImage.initials(for: "Sam Brown") == "SB")
        #expect(ProfileAvatarImage.initials(for: "mum") == "M")
        #expect(ProfileAvatarImage.initials(for: "  ") == "?")
        #expect(ProfileAvatarImage.initials(for: "Anne Marie Smith") == "AM")
    }

    @Test func pickerWraps() {
        #expect(ProfilePickerRow.lineLengths(count: 0) == [])
        #expect(ProfilePickerRow.lineLengths(count: 5) == [5])
        #expect(ProfilePickerRow.lineLengths(count: 6) == [6])
        #expect(ProfilePickerRow.lineLengths(count: 7) == [4, 3])
        #expect(ProfilePickerRow.lineLengths(count: 10) == [5, 5])
    }
}
