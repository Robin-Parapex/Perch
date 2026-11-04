import Foundation
import PerchCore
import Testing

@testable import PerchPlex

/// Decision table from docs/ARCHITECTURE.md, with the lead's refinements. Inputs are built from the spec,
/// not from the decider's branches.
@Suite("Playback decider")
struct PlexPlaybackDeciderTests {
    // MARK: Builders

    private static func video(
        _ codec: String = "h264", transfer: String? = nil, dv: Int? = nil,
        width: Int = 1920, height: Int = 1080, fps: Double = 23.976, title: String? = nil
    ) -> MediaStream {
        MediaStream(
            id: "1", kind: .video, codec: codec, colourTransfer: transfer, dolbyVisionProfile: dv,
            frameRate: fps, width: width, height: height,
            displayTitle: title, extendedDisplayTitle: title)
    }

    private static func audio(_ codec: String = "aac", title: String? = nil) -> MediaStream {
        MediaStream(
            id: "2", kind: .audio, codec: codec, channels: 6,
            displayTitle: title, extendedDisplayTitle: title)
    }

    private static func sub(
        _ id: Int, _ codec: String, forced: Bool = false
    ) -> MediaStream {
        MediaStream(
            id: String(id), kind: .subtitle, codec: codec, format: codec, isForced: forced)
    }

    private static func version(
        container: String, video v: MediaStream = video(), audio a: MediaStream? = audio(),
        subs: [MediaStream] = []
    ) -> MediaVersion {
        let streams = [v] + (a.map { [$0] } ?? []) + subs
        return MediaVersion(
            id: "v", container: container, videoCodec: v.codec, audioCodec: a?.codec,
            parts: [MediaPart(id: "p", key: "/p", container: container, streams: streams)])
    }

    private static func decide(
        _ container: String, video v: MediaStream = video(), audio a: MediaStream? = audio(),
        subs: [MediaStream] = [], pick: Int? = nil
    ) -> PlaybackDecision {
        PlexPlaybackDecider.decide(
            version: version(container: container, video: v, audio: a, subs: subs),
            subtitleStreamID: pick)
    }

    // MARK: Container

    @Test(arguments: ["mp4", "mov", "m4v", "mov,mp4", "mov,mp4,m4a,3gp,3g2,mj2"])
    func appleContainersDirectPlay(container: String) {
        let d = Self.decide(container)
        #expect(d.method == .directPlay)
        #expect(d.videoRange == .sdr)
        #expect(d.subtitle == .none)
    }

    @Test(arguments: ["matroska,webm", "mkv", "avi", "mpegts", "ts", "wmv", "asf", "flv"])
    func otherContainersDirectStream(container: String) {
        let d = Self.decide(container)
        #expect(d.method == .directStream)
        #expect(!d.reasons.isEmpty)
    }

    // MARK: Video

    @Test(arguments: ["h264", "hevc"])
    func supportedVideoCodecs(codec: String) {
        #expect(Self.decide("mp4", video: Self.video(codec)).method == .directPlay)
        #expect(Self.decide("mkv", video: Self.video(codec)).method == .directStream)
    }

    @Test(arguments: ["av1", "vp9", "mpeg2video", "vc1"])
    func unsupportedVideoTranscodes(codec: String) {
        let d = Self.decide("mp4", video: Self.video(codec))
        #expect(d.method == .transcode)
        #expect(!d.reasons.isEmpty)
    }

    @Test(arguments: [5, 8])
    func dolbyVisionProfiles5And8KeepDV(profile: Int) {
        let d = Self.decide(
            "mp4", video: Self.video("hevc", transfer: "smpte2084", dv: profile))
        #expect(d.method == .directPlay)
        #expect(d.videoRange == .dolbyVision)
        #expect(d.dolbyVisionProfile == profile)
        #expect(!d.notes.contains { $0.localizedCaseInsensitiveContains("lost") })
    }

    @Test func dolbyVision7IsHDR10DirectStream() {
        let d = Self.decide(
            "mp4", video: Self.video("hevc", transfer: "smpte2084", dv: 7))
        #expect(d.method >= .directStream)
        #expect(d.videoRange == .hdr10)
        #expect(d.notes.contains { $0.contains("Dolby Vision 7") })
    }

    @Test func hdr10() {
        let d = Self.decide("mp4", video: Self.video("hevc", transfer: "smpte2084"))
        #expect(d.videoRange == .hdr10)
        #expect(d.method == .directPlay)
    }

    @Test(arguments: ["HEVC Main 10 HDR10+ 4K", "hevc HDR10+"])
    func hdr10Plus(title: String) {
        let d = Self.decide(
            "mp4", video: Self.video("hevc", transfer: "smpte2084", title: title))
        #expect(d.videoRange == .hdr10Plus)
    }

    @Test func hlgIsHDR10WithNote() {
        let d = Self.decide("mp4", video: Self.video("hevc", transfer: "arib-std-b67"))
        #expect(d.videoRange == .hdr10)
        #expect(d.notes.contains { $0.contains("HLG") })
    }

    @Test(arguments: [nil, "bt709", "smpte170m"] as [String?])
    func otherTransferIsSDR(transfer: String?) {
        #expect(Self.decide("mp4", video: Self.video("hevc", transfer: transfer)).videoRange == .sdr)
    }

    @Test func videoDetailsCopied() {
        let d = Self.decide(
            "mp4", video: Self.video("hevc", width: 3840, height: 2160, fps: 59.94))
        #expect(d.frameRate == 59.94)
        #expect(d.width == 3840)
        #expect(d.height == 2160)
    }

    // MARK: Audio

    @Test(arguments: ["aac", "ac3", "eac3"])
    func passthroughAudio(codec: String) {
        #expect(Self.decide("mp4", audio: Self.audio(codec)).method == .directPlay)
        #expect(Self.decide("mkv", audio: Self.audio(codec)).method == .directStream)
    }

    @Test(arguments: ["truehd", "dts", "dca", "flac", "pcm_s16le", "pcm_s24le", "opus"])
    func nonPassthroughAudioTranscodes(codec: String) {
        let mp4 = Self.decide("mp4", audio: Self.audio(codec))
        #expect(mp4.method == .audioTranscode)
        #expect(!mp4.reasons.isEmpty)
        #expect(Self.decide("mkv", audio: Self.audio(codec)).method == .audioTranscode)
    }

    @Test func atmosOnTrueHDNote() {
        let d = Self.decide("mkv", audio: Self.audio("truehd", title: "English (TRUEHD 7.1 Atmos)"))
        #expect(d.method == .audioTranscode)
        #expect(d.notes.contains { $0.contains("Atmos lost") })
    }

    @Test func dtsXNote() {
        let d = Self.decide("mkv", audio: Self.audio("dts", title: "English (DTS-HD MA 7.1 DTS:X)"))
        #expect(d.method == .audioTranscode)
        #expect(d.notes.contains { $0.contains("DTS:X lost") })
    }

    // MARK: Subtitles

    @Test func noSubtitleSelectedNoChange() {
        let d = Self.decide("mp4", subs: [Self.sub(10, "srt")])
        #expect(d.method == .directPlay)
        #expect(d.subtitle == .none)
    }

    @Test(arguments: ["srt", "ass", "ssa", "webvtt"])
    func textSubtitleSelectedDirectStream(codec: String) {
        let d = Self.decide("mp4", subs: [Self.sub(10, codec)], pick: 10)
        #expect(d.method == .directStream)
        #expect(d.subtitle == .text(streamID: 10))
        #expect(!d.reasons.isEmpty)
    }

    @Test func mkvWithSRTSelected() {
        let d = Self.decide("mkv", subs: [Self.sub(10, "srt")], pick: 10)
        #expect(d.method == .directStream)
        #expect(d.subtitle == .text(streamID: 10))
    }

    @Test(arguments: ["pgs", "vobsub", "dvdsub", "dvbsub"])
    func imageSubtitleBurnsIn1080p(codec: String) {
        let d = Self.decide("mkv", subs: [Self.sub(11, codec)], pick: 11)
        #expect(d.method == .transcode)
        #expect(d.subtitle == .burnIn(streamID: 11))
        #expect(!d.reasons.isEmpty)
    }

    @Test func imageSubtitleOffOn4K() {
        let d = Self.decide(
            "mkv", video: Self.video("hevc", width: 3840, height: 2160),
            subs: [Self.sub(11, "pgs")], pick: 11)
        #expect(d.subtitle == .none)
        #expect(d.method != .transcode)
        #expect(d.notes.contains { $0.contains("Image subtitles off for 4K") })
    }

    @Test func imageSubtitleStillBurnsInJustBelow4KThreshold() {
        let d = Self.decide(
            "mkv", video: Self.video("hevc", width: 3799, height: 2160),
            subs: [Self.sub(11, "pgs")], pick: 11)
        #expect(d.subtitle == .burnIn(streamID: 11))
        #expect(d.method == .transcode)
    }

    @Test func imageSubtitleOffAt3800Wide() {
        let d = Self.decide(
            "mkv", video: Self.video("hevc", width: 3800, height: 1600),
            subs: [Self.sub(11, "pgs")], pick: 11)
        #expect(d.subtitle == .none)
    }

    @Test func unknownSubtitleIDGivesNone() {
        let d = Self.decide("mp4", subs: [Self.sub(10, "srt")], pick: 999)
        #expect(d.subtitle == .none)
        #expect(d.method == .directPlay)
    }

    @Test func forcedTextSubtitleAutoPicked() {
        let d = Self.decide("mp4", subs: [Self.sub(10, "srt", forced: true)], pick: nil)
        #expect(d.subtitle == .text(streamID: 10))
        #expect(d.method == .directStream)
    }

    @Test func forcedImageSubtitleNotAutoPicked() {
        let d = Self.decide("mkv", subs: [Self.sub(11, "pgs", forced: true)], pick: nil)
        #expect(d.subtitle == .none)
        #expect(d.method == .directStream)
    }

    @Test func nonForcedTextNotAutoPicked() {
        let d = Self.decide("mkv", subs: [Self.sub(10, "srt")], pick: nil)
        #expect(d.subtitle == .none)
    }

    // MARK: Combinations

    @Test func mp4DTSIsAudioTranscode() {
        let d = Self.decide("mp4", audio: Self.audio("dts"))
        #expect(d.method == .audioTranscode)
        #expect(!d.reasons.isEmpty)
    }

    @Test func av1AACInMP4Transcodes() {
        let d = Self.decide("mp4", video: Self.video("av1"), audio: Self.audio("aac"))
        #expect(d.method == .transcode)
    }

    @Test func mkvHEVCDV7TrueHDAtmos() {
        let d = Self.decide(
            "mkv", video: Self.video("hevc", transfer: "smpte2084", dv: 7, width: 3840, height: 2160),
            audio: Self.audio("truehd", title: "English (TRUEHD 7.1 Atmos)"))
        #expect(d.method == .audioTranscode)
        #expect(d.videoRange == .hdr10)
        #expect(d.notes.contains { $0.contains("Dolby Vision 7") })
        #expect(d.notes.contains { $0.contains("Atmos lost") })
    }

    @Test func dv81MP4EAC3AtmosDirectPlay() {
        let d = Self.decide(
            "mp4", video: Self.video("hevc", transfer: "smpte2084", dv: 8, width: 3840, height: 2160),
            audio: Self.audio("eac3", title: "English (EAC3 5.1 Atmos)"))
        #expect(d.method == .directPlay)
        #expect(d.videoRange == .dolbyVision)
        #expect(!d.notes.contains { $0.localizedCaseInsensitiveContains("lost") })
    }

    @Test func reasonsPresentWheneverNotDirectPlay() {
        let cases: [PlaybackDecision] = [
            Self.decide("mkv"),
            Self.decide("mp4", audio: Self.audio("flac")),
            Self.decide("mp4", video: Self.video("vp9")),
            Self.decide("mp4", subs: [Self.sub(1, "srt")], pick: 1),
        ]
        for d in cases {
            #expect(d.method != .directPlay)
            #expect(!d.reasons.isEmpty)
        }
    }

    // MARK: Fixture clips (build/fixtures/Perch Fixtures/README.txt)

    struct Clip: Sendable, CustomTestStringConvertible {
        let name: String
        let container: String
        let video: String
        let audio: String
        let width: Int
        let height: Int
        let transfer: String?
        let subCodec: String?
        let pick: Bool
        let expected: PlaybackMethod
        var testDescription: String { name }
    }

    static let clips: [Clip] = [
        Clip(name: "01 MP4 H264 AAC", container: "mov,mp4,m4a,3gp,3g2,mj2", video: "h264", audio: "aac", width: 1920, height: 1080, transfer: nil, subCodec: nil, pick: false, expected: .directPlay),
        Clip(name: "02 MP4 HEVC SDR AAC", container: "mp4", video: "hevc", audio: "aac", width: 1920, height: 1080, transfer: nil, subCodec: nil, pick: false, expected: .directPlay),
        Clip(name: "03 MKV HEVC HDR10 EAC3", container: "matroska,webm", video: "hevc", audio: "eac3", width: 1920, height: 1080, transfer: "smpte2084", subCodec: nil, pick: false, expected: .directStream),
        Clip(name: "04 MKV H264 AC3", container: "matroska,webm", video: "h264", audio: "ac3", width: 1920, height: 1080, transfer: nil, subCodec: nil, pick: false, expected: .directStream),
        Clip(name: "05 MKV H264 EAC3", container: "matroska,webm", video: "h264", audio: "eac3", width: 1920, height: 1080, transfer: nil, subCodec: nil, pick: false, expected: .directStream),
        Clip(name: "06 MKV H264 TrueHD", container: "matroska,webm", video: "h264", audio: "truehd", width: 1920, height: 1080, transfer: nil, subCodec: nil, pick: false, expected: .audioTranscode),
        Clip(name: "07 MKV H264 DTS", container: "matroska,webm", video: "h264", audio: "dts", width: 1920, height: 1080, transfer: nil, subCodec: nil, pick: false, expected: .audioTranscode),
        Clip(name: "08 MKV H264 FLAC", container: "matroska,webm", video: "h264", audio: "flac", width: 1920, height: 1080, transfer: nil, subCodec: nil, pick: false, expected: .audioTranscode),
        Clip(name: "09 MKV H264 SRT selected", container: "matroska,webm", video: "h264", audio: "aac", width: 1920, height: 1080, transfer: nil, subCodec: "srt", pick: true, expected: .directStream),
        Clip(name: "10 MKV H264 ASS selected", container: "matroska,webm", video: "h264", audio: "aac", width: 1920, height: 1080, transfer: nil, subCodec: "ass", pick: true, expected: .directStream),
        Clip(name: "11a MKV H264 VOBSUB off", container: "matroska,webm", video: "h264", audio: "aac", width: 1920, height: 1080, transfer: nil, subCodec: "dvd_subtitle", pick: false, expected: .directStream),
        Clip(name: "11b MKV H264 VOBSUB selected", container: "matroska,webm", video: "h264", audio: "aac", width: 1920, height: 1080, transfer: nil, subCodec: "vobsub", pick: true, expected: .transcode),
        Clip(name: "12 MKV AV1 AAC", container: "matroska,webm", video: "av1", audio: "aac", width: 1920, height: 1080, transfer: nil, subCodec: nil, pick: false, expected: .transcode),
        Clip(name: "13 WEBM VP9 Opus", container: "matroska,webm", video: "vp9", audio: "opus", width: 1920, height: 1080, transfer: nil, subCodec: nil, pick: false, expected: .transcode),
        Clip(name: "14 TS MPEG2 AC3", container: "mpegts", video: "mpeg2video", audio: "ac3", width: 720, height: 576, transfer: nil, subCodec: nil, pick: false, expected: .transcode),
        Clip(name: "15a MP4 H264 AAC SRT off", container: "mov,mp4,m4a,3gp,3g2,mj2", video: "h264", audio: "aac", width: 1920, height: 1080, transfer: nil, subCodec: "srt", pick: false, expected: .directPlay),
        Clip(name: "15b MP4 H264 AAC SRT selected", container: "mov,mp4,m4a,3gp,3g2,mj2", video: "h264", audio: "aac", width: 1920, height: 1080, transfer: nil, subCodec: "srt", pick: true, expected: .directStream),
        Clip(name: "16 MKV HEVC HDR10 EAC3 4K", container: "matroska,webm", video: "hevc", audio: "eac3", width: 3840, height: 2160, transfer: "smpte2084", subCodec: nil, pick: false, expected: .directStream),
    ]

    @Test(arguments: clips)
    func fixtureClip(clip: Clip) {
        let subs = clip.subCodec.map { [Self.sub(20, $0)] } ?? []
        let d = Self.decide(
            clip.container,
            video: Self.video(clip.video, transfer: clip.transfer, width: clip.width, height: clip.height),
            audio: Self.audio(clip.audio), subs: subs, pick: clip.pick ? 20 : nil)
        #expect(d.method == clip.expected)
        if clip.expected != .directPlay { #expect(!d.reasons.isEmpty) }
    }
}

extension PlaybackMethod {
    fileprivate var rank: Int {
        switch self {
        case .directPlay: 0
        case .directStream: 1
        case .audioTranscode: 2
        case .transcode: 3
        }
    }
    fileprivate static func >= (l: PlaybackMethod, r: PlaybackMethod) -> Bool { l.rank >= r.rank }
}
