import Foundation
import PerchCore
import Testing

@testable import PerchPlex

@Suite("Stream extra fields")
struct PlexStreamFieldsTests {
    private func streams(json: String) throws -> [MediaStream] {
        let c = try PlexWireContainer.decode(from: Data(json.utf8))
        let item = try #require(c.metadata?.first)
        return try #require(PlexLibraryMapping.detail(item)).versions.flatMap(\.parts).flatMap(\.streams)
    }

    @Test func decodesFromFixture() throws {
        let c = try PlexWireContainer.decode(from: Fixture.data("lib-metadata-episode"))
        let item = try #require(c.metadata?.first)
        let detail = try #require(PlexLibraryMapping.detail(item))
        let video = try #require(detail.versions.flatMap(\.parts).flatMap(\.streams).first { $0.kind == .video })
        #expect(video.dolbyVisionPresent == true)
        #expect(video.dolbyVisionProfile == 8)
        #expect(video.colourSpace == "bt2020nc")
        #expect(video.displayTitle == "4K DoVi/HDR10 (HEVC Main 10)")
        #expect(video.profile == nil && video.scanType == nil && video.dolbyVisionLevel == nil)
    }

    @Test func decodesAllFieldsAndLenientBool() throws {
        let json = """
            {"MediaContainer":{"Metadata":[{"ratingKey":"1","type":"movie","title":"F","Media":[{"id":1,"Part":[{"id":2,"Stream":[
            {"id":1,"streamType":1,"codec":"hevc","profile":"main 10","DOVIPresent":1,"DOVILevel":6,"DOVIBLCompatID":1,"colorPrimaries":"bt2020","colorSpace":"bt2020nc","scanType":"progressive"},
            {"id":2,"streamType":2,"codec":"truehd","profile":"truehd","audioChannelLayout":"7.1","displayTitle":"English (TRUEHD 7.1)","extendedDisplayTitle":"English (TRUEHD 7.1 Atmos)"}
            ]}]}]}]}}
            """
        let all = try streams(json: json)
        let v = all[0], a = all[1]
        #expect(v.profile == "main 10" && v.dolbyVisionPresent == true)
        #expect(v.dolbyVisionLevel == 6 && v.dolbyVisionBLCompatID == 1)
        #expect(v.colourPrimaries == "bt2020" && v.colourSpace == "bt2020nc" && v.scanType == "progressive")
        #expect(a.audioChannelLayout == "7.1")
        #expect(a.extendedDisplayTitle == "English (TRUEHD 7.1 Atmos)")
    }

    @Test func toleratesAbsentFields() throws {
        let json = """
            {"MediaContainer":{"Metadata":[{"ratingKey":"1","type":"movie","title":"F","Media":[{"id":1,"Part":[{"id":2,"Stream":[
            {"id":1,"streamType":1,"codec":"h264"}]}]}]}]}}
            """
        let s = try #require(try streams(json: json).first)
        #expect(s.codec == "h264")
        #expect(s.profile == nil && s.audioChannelLayout == nil && s.dolbyVisionPresent == nil)
        #expect(s.dolbyVisionLevel == nil && s.dolbyVisionBLCompatID == nil)
        #expect(s.colourPrimaries == nil && s.colourSpace == nil && s.scanType == nil)
        #expect(s.displayTitle == nil && s.extendedDisplayTitle == nil)
    }
}
