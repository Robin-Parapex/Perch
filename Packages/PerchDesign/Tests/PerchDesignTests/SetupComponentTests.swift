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

    @Test func tintIsStableAndInRange() {
        let first = ProfileAvatarImage.tintIndex(for: "Sam")
        #expect(first == ProfileAvatarImage.tintIndex(for: "Sam"))
        #expect(first == ProfileAvatarImage.tintIndex(for: " sam "))
        for name in ["Sam", "Alex Brown", "Kit", "Guest", "", "Zoë"] {
            #expect((0..<ProfileAvatarImage.tintPalette.count).contains(ProfileAvatarImage.tintIndex(for: name)))
        }
        #expect(Set(["Sam", "Alex", "Kit", "Guest", "Mum", "Dad"].map(ProfileAvatarImage.tintIndex(for:))).count > 1)
    }

    @Test func countdownFormat() {
        #expect(PINEntryScreen.countdownText(remaining: 45) == "Try again in 0:45")
        #expect(PINEntryScreen.countdownText(remaining: 44.2) == "Try again in 0:45")
        #expect(PINEntryScreen.countdownText(remaining: 125) == "Try again in 2:05")
        #expect(PINEntryScreen.countdownText(remaining: -3) == "Try again in 0:00")
    }

    @Test func stepTitleToken() {
        #expect(PerchFont.stepTitleSize == 64)
    }
}
