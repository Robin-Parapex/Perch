import Foundation
import Testing

@testable import PerchCore

@Suite("Artwork sizes and logo path")
struct ArtworkSizeTests {
    @Test func pixelSizesMatchTheSpec() {
        let expected: [ArtworkSize: (Int, Int)] = [
            .poster: (300, 450), .landscape: (640, 360), .backdrop: (1920, 1080),
            .logo: (800, 310), .placeholder: (64, 64),
        ]
        #expect(ArtworkSize.allCases.count == expected.count)
        for size in ArtworkSize.allCases {
            #expect(size.pixelSize.width == expected[size]?.0)
            #expect(size.pixelSize.height == expected[size]?.1)
        }
    }

    @Test func logoPathRoundTripsAndDefaultsToNil() throws {
        let item = MediaSummary(id: "1", kind: .film, title: "T", logoPath: "/library/metadata/1/clearLogo/9")
        let back = try JSONDecoder().decode(MediaSummary.self, from: JSONEncoder().encode(item))
        #expect(back.logoPath == "/library/metadata/1/clearLogo/9")
        #expect(MediaSummary(id: "2", kind: .film, title: "U").logoPath == nil)
    }

    @Test func anOldSnapshotWithoutLogoPathStillDecodes() throws {
        let json = #"{"id":"1","kind":"film","title":"Old","viewCount":2}"#
        let item = try JSONDecoder().decode(MediaSummary.self, from: Data(json.utf8))
        #expect(item.title == "Old")
        #expect(item.logoPath == nil)
    }
}
