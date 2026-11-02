import Testing

@testable import PerchCore

/// Expectations are written from docs/GLOSSARY.md, not from the implementation.
struct TitleAvailabilityTests {
    static let all: [TitleAvailability] = [
        .requested, .gettingReady(progress: nil), .gettingReady(progress: 0.4),
        .someEpisodesReady, .readyToWatch, .notFound,
    ]

    @Test func labelsMatchGlossary() {
        // docs/GLOSSARY.md:7
        #expect(TitleAvailability.requested.label() == "Requested")
        // docs/GLOSSARY.md:8
        #expect(TitleAvailability.gettingReady(progress: nil).label() == "Getting it ready")
        #expect(TitleAvailability.gettingReady(progress: 0.5).label() == "Getting it ready")
        // docs/GLOSSARY.md:9
        #expect(TitleAvailability.someEpisodesReady.label() == "Some episodes ready")
        // docs/GLOSSARY.md:10
        #expect(TitleAvailability.readyToWatch.label() == "Ready to watch")
        // docs/GLOSSARY.md:11
        #expect(TitleAvailability.notFound.label() == "Couldn't find this yet")
    }

    @Test func kidsRequestedLabelIsWaitingForAParent() {
        // docs/GLOSSARY.md:7 (only kids variant the glossary names)
        #expect(TitleAvailability.requested.label(forKids: true) == "Waiting for a parent")
    }

    @Test func kidsLabelsOtherThanRequestedMatchStandard() {
        // docs/GLOSSARY.md:8-11 name no kids variant
        for a in Self.all {
            if case .requested = a { continue }
            #expect(a.label(forKids: true) == a.label())
        }
    }

    @Test func progressClamps() {
        // docs/GLOSSARY.md:8 (progress bar when known)
        #expect(TitleAvailability.gettingReady(progress: -0.5).progress == 0)
        #expect(TitleAvailability.gettingReady(progress: 1.7).progress == 1)
        #expect(TitleAvailability.gettingReady(progress: 0.4).progress == 0.4)
        #expect(TitleAvailability.gettingReady(progress: nil).progress == nil)
    }

    @Test func progressIsNilForOtherStates() {
        // docs/GLOSSARY.md:8 (bar only while getting it ready)
        #expect(TitleAvailability.requested.progress == nil)
        #expect(TitleAvailability.someEpisodesReady.progress == nil)
        #expect(TitleAvailability.readyToWatch.progress == nil)
        #expect(TitleAvailability.notFound.progress == nil)
    }

    @Test func labelsHaveNoBackendJargon() {
        // CLAUDE.md non-negotiable 5; docs/GLOSSARY.md:8
        let banned = ["sonarr", "radarr", "indexer", "debrid", "symlink", "seerr", "plex", "usenet"]
        for a in Self.all {
            for kids in [false, true] {
                let label = a.label(forKids: kids)
                for word in banned {
                    #expect(!label.lowercased().contains(word), "\(label) contains \(word)")
                }
            }
        }
    }

    @Test func labelsDoNotEndWithExclamation() {
        // docs/GLOSSARY.md plain-wording rule (no shouting)
        for a in Self.all {
            for kids in [false, true] {
                #expect(!a.label(forKids: kids).hasSuffix("!"))
            }
        }
    }
}
