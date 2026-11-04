import Foundation
import PerchCore
import Testing

@testable import PerchPlex

private func movieJSON(
    container: String, videoCodec: String = "h264", audioCodec: String = "aac", subtitleCodec: String? = nil
) -> String {
    let subtitle = subtitleCodec.map {
        #",{"id":30,"streamType":3,"codec":"\#($0)","forced":0}"#
    } ?? ""
    return #"""
        {"MediaContainer":{"Metadata":[{"ratingKey":"500","type":"movie","title":"Harbour Lights","duration":7200000,
        "Media":[{"id":1,"container":"\#(container)","duration":7200000,"Part":[{"id":2,"key":"/library/parts/2/1/file.\#(container)","container":"\#(container)","accessible":true,
        "Stream":[{"id":10,"streamType":1,"codec":"\#(videoCodec)","width":1920,"height":1080},
        {"id":20,"streamType":2,"codec":"\#(audioCodec)","selected":1}\#(subtitle)]}]}]}]}}
        """#
}

private let acceptedDecision =
    #"{"MediaContainer":{"generalDecisionCode":1000,"generalDecisionText":"ok","transcodeDecisionCode":1001,"transcodeDecisionText":"ok"}}"#

private func items(_ url: URL) -> [URLQueryItem] {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
}

private func value(_ url: URL, _ name: String) -> String? { items(url).first { $0.name == name }?.value }

@Suite("Playback source", .timeLimit(.minutes(1)))
struct PlexPlaybackSourceTests {
    private func rig(_ json: String) async throws -> LibraryRig {
        let rig = try await LibraryRig.make()
        await rig.transport.script(path: "/library/metadata/500", json: json)
        return rig
    }

    @Test func directPlayMP4GivesPartURLWithTokenOnlyInHeaders() async throws {
        let rig = try await rig(movieJSON(container: "mp4"))
        defer { rig.cleanup() }
        let source = try await rig.library.playbackSource(for: "500", startMs: 60_000, subtitleStreamID: nil)
        #expect(source.decision.method == .directPlay)
        #expect(!source.isTranscodeSession)
        #expect(source.url.path == "/library/parts/2/1/file.mp4")
        #expect(source.url.query == nil)
        #expect(!source.url.absoluteString.contains(testServerToken))
        #expect(source.headers["X-Plex-Token"] == testServerToken)
        #expect(source.startMs == 60_000 && source.durationMs == 7_200_000)
        #expect(await rig.transport.requests(forPath: "/video/:/transcode/universal/decision").isEmpty)
    }

    @Test func mkvAsksForADecisionThenStartsHLSWithTheSameItems() async throws {
        let rig = try await rig(movieJSON(container: "mkv"))
        defer { rig.cleanup() }
        await rig.transport.script(path: "/video/:/transcode/universal/decision", json: acceptedDecision)
        let source = try await rig.library.playbackSource(
            for: "500", startMs: nil, subtitleStreamID: nil, sessionID: "SESSION-1")
        let decision = try #require(await rig.transport.requests(forPath: "/video/:/transcode/universal/decision").first)
        #expect(source.isTranscodeSession && source.decision.method == .directStream)
        #expect(source.url.path == "/video/:/transcode/universal/start.m3u8")
        #expect(items(source.url) == items(decision.url!))
        #expect(value(source.url, "X-Plex-Client-Profile-Extra")?.contains("protocol=hls") == true)
        #expect(value(source.url, "directStream") == "1" && value(source.url, "directStreamAudio") == "1")
        #expect(value(source.url, "session") == "SESSION-1")
        #expect(!source.url.absoluteString.contains(testServerToken))
        #expect(!items(source.url).contains { $0.name == "X-Plex-Token" })
        #expect(decision.value(forHTTPHeaderField: "X-Plex-Token") == testServerToken)
        #expect(source.headers["X-Plex-Token"] == testServerToken)
    }

    @Test func refusedDecisionThrows() async throws {
        let rig = try await rig(movieJSON(container: "mkv"))
        defer { rig.cleanup() }
        await rig.transport.script(
            path: "/video/:/transcode/universal/decision",
            json: #"{"MediaContainer":{"generalDecisionCode":4005,"generalDecisionText":"No conversion profile","transcodeDecisionCode":4005}}"#)
        await #expect(throws: PlexPlaybackError.self) {
            _ = try await rig.library.playbackSource(for: "500", startMs: nil, subtitleStreamID: nil)
        }
    }

    @Test func burnInSubtitleAndOffsetParameters() async throws {
        let rig = try await rig(movieJSON(container: "mp4", subtitleCodec: "pgs"))
        defer { rig.cleanup() }
        await rig.transport.script(path: "/video/:/transcode/universal/decision", json: acceptedDecision)
        let source = try await rig.library.playbackSource(for: "500", startMs: 95_500, subtitleStreamID: 30)
        #expect(source.decision.subtitle == .burnIn(streamID: 30) && source.decision.method == .transcode)
        #expect(value(source.url, "subtitles") == "burn")
        #expect(value(source.url, "subtitleStreamID") == "30")
        #expect(value(source.url, "offset") == "95")
        // Burned-in subtitles transcode the video; the AAC track still passes through.
        #expect(value(source.url, "directStream") == "0" && value(source.url, "directStreamAudio") == "1")
    }

    @Test func videoTranscodeKeepsPassthroughAudio() async throws {
        let rig = try await rig(movieJSON(container: "mkv", videoCodec: "av1", audioCodec: "eac3"))
        defer { rig.cleanup() }
        await rig.transport.script(path: "/video/:/transcode/universal/decision", json: acceptedDecision)
        let source = try await rig.library.playbackSource(for: "500", startMs: nil, subtitleStreamID: nil)
        #expect(source.decision.method == .transcode && source.decision.audioPassthrough)
        #expect(value(source.url, "directStream") == "0" && value(source.url, "directStreamAudio") == "1")
    }

    @Test func decisionSummaryNamesWhatTheServerSendsAndNoPaths() {
        let body = Data(
            #"{"MediaContainer":{"transcodeDecisionText":"Direct play not available; Conversion OK.","Metadata":[{"key":"/library/metadata/500","Media":[{"container":"mpegts","protocol":"hls","videoCodec":"h264","audioCodec":"mp3","Part":[{"key":"/video/secret/path","Stream":[{"streamType":1,"codec":"h264","decision":"transcode"},{"streamType":2,"codec":"mp3","decision":"transcode"}]}]}]}]}}"#
                .utf8)
        let summary = PlexLibrary.decisionSummary(body)
        #expect(summary.contains("container=mpegts protocol=hls videoCodec=h264 audioCodec=mp3"))
        #expect(summary.contains("stream1=h264/transcode stream2=mp3/transcode"))
        #expect(summary.contains("transcodeDecisionText=Direct play not available; Conversion OK."))
        #expect(!summary.contains("/library") && !summary.contains("/video"))
    }

    @Test func convertedAudioIsNotDirectStreamed() async throws {
        let rig = try await rig(movieJSON(container: "mkv", audioCodec: "truehd"))
        defer { rig.cleanup() }
        await rig.transport.script(path: "/video/:/transcode/universal/decision", json: acceptedDecision)
        let source = try await rig.library.playbackSource(for: "500", startMs: nil, subtitleStreamID: nil)
        #expect(source.decision.method == .audioTranscode && !source.decision.audioPassthrough)
        #expect(value(source.url, "directStream") == "1" && value(source.url, "directStreamAudio") == "0")
    }

    @Test func stopTranscodeHitsTheStopEndpointWithTheSession() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: "/video/:/transcode/universal/stop", json: "{}")
        await rig.library.stopTranscode(sessionID: "SESSION-9")
        let stop = try #require(await rig.transport.requests(forPath: "/video/:/transcode/universal/stop").first)
        #expect(value(stop.url!, "session") == "SESSION-9")
        #expect(!stop.url!.absoluteString.contains(testServerToken))
    }

    @Test func deciderSmoke() {
        let sdr = MediaVersion(
            id: "1", parts: [
                MediaPart(id: "2", key: "/k", container: "mp4", streams: [
                    MediaStream(id: "1", kind: .video, codec: "h264", width: 1920, height: 1080),
                    MediaStream(id: "2", kind: .audio, codec: "aac", isSelected: true),
                ])
            ])
        #expect(PlexPlaybackDecider.decide(version: sdr, subtitleStreamID: nil).method == .directPlay)
        var truehd = sdr
        truehd.parts[0].streams[1] = MediaStream(
            id: "2", kind: .audio, codec: "truehd", isSelected: true, extendedDisplayTitle: "TrueHD 7.1 Atmos")
        let result = PlexPlaybackDecider.decide(version: truehd, subtitleStreamID: nil)
        #expect(result.method == .audioTranscode && result.notes.contains("Atmos lost"))
    }
}
