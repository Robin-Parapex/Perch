import Foundation
import PerchCore

/// The playback decision table (ARCHITECTURE.md): one pure function from a file version to a
/// `PlaybackDecision`. For each dimension the first matching row applies; the method is the largest
/// of the dimensions (directPlay < directStream < audioTranscode < transcode).
public enum PlexPlaybackDecider {
    private static let textSubtitles: Set<String> = ["srt", "ass", "ssa", "webvtt", "vtt", "mov_text", "tx3g", "subrip"]
    private static let directContainers: Set<String> = ["mp4", "mov", "m4v"]
    /// Audio the HLS target carries as is, so a video transcode keeps it (Atmos in EAC3 survives).
    private static let passthroughAudio: Set<String> = ["aac", "ac3", "eac3"]

    private static func rank(_ method: PlaybackMethod) -> Int {
        switch method {
        case .directPlay: 0
        case .directStream: 1
        case .audioTranscode: 2
        case .transcode: 3
        }
    }

    public static func decide(version: MediaVersion, subtitleStreamID: Int?) -> PlaybackDecision {
        let part = version.parts.first
        let streams = part?.streams ?? []
        var decision = PlaybackDecision(method: .directPlay)

        func raise(_ method: PlaybackMethod) {
            if rank(method) > rank(decision.method) { decision.method = method }
        }

        // Container
        let containerName = (part?.container ?? version.container ?? "").lowercased()
        let containers = containerName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if !containerName.isEmpty, !containers.contains(where: directContainers.contains) {
            raise(.directStream)
            decision.reasons.append("container \(containerName): direct stream")
        }

        // Video
        let video = streams.first { $0.kind == .video }
        if let video {
            decision.frameRate = video.frameRate
            decision.width = video.width
            decision.height = video.height
            let codec = (video.codec ?? version.videoCodec ?? "").lowercased()
            if ["av1", "vp9", "mpeg2video", "vc1"].contains(codec) {
                raise(.transcode)
                decision.reasons.append("video \(codec): transcode")
            }
            let dvProfile = video.dolbyVisionProfile
            let titles = [video.displayTitle, video.extendedDisplayTitle].compactMap { $0 }.joined(separator: " ")
            if let dvProfile, dvProfile == 5 || dvProfile == 8 {
                decision.videoRange = .dolbyVision
                decision.dolbyVisionProfile = dvProfile
                decision.reasons.append("Dolby Vision \(dvProfile): kept")
            } else if dvProfile == 7 {
                raise(.directStream)
                decision.videoRange = .hdr10
                decision.dolbyVisionProfile = 7
                decision.reasons.append("Dolby Vision 7: direct stream as HDR10")
                decision.notes.append("Dolby Vision 7 plays as HDR10")
            } else {
                switch (video.colourTransfer ?? "").lowercased() {
                case "smpte2084":
                    decision.videoRange = titles.contains("HDR10+") ? .hdr10Plus : .hdr10
                case "arib-std-b67":
                    decision.videoRange = .hdr10
                    decision.notes.append("HLG")
                default:
                    decision.videoRange = .sdr
                }
            }
        }

        // Audio
        let audioStreams = streams.filter { $0.kind == .audio }
        let audio = audioStreams.first(where: \.isSelected) ?? audioStreams.first(where: \.isDefault) ?? audioStreams.first
        if let audio {
            let codec = (audio.codec ?? version.audioCodec ?? "").lowercased()
            let titles = [audio.displayTitle, audio.extendedDisplayTitle, audio.title].compactMap { $0 }
                .joined(separator: " ")
            let isDTS = codec.hasPrefix("dts") || codec.hasPrefix("dca")
            decision.audioPassthrough = passthroughAudio.contains(codec)
            if ["truehd", "flac", "opus"].contains(codec) || codec.hasPrefix("pcm") || isDTS {
                raise(.audioTranscode)
                decision.reasons.append("audio \(codec): convert to EAC3 5.1")
                if titles.localizedCaseInsensitiveContains("DTS:X") {
                    decision.notes.append("DTS:X lost")
                } else if titles.localizedCaseInsensitiveContains("Atmos") {
                    decision.notes.append("Atmos lost")
                }
            }
        }

        // Subtitles
        let subtitleStreams = streams.filter { $0.kind == .subtitle }
        func isText(_ stream: MediaStream) -> Bool {
            let name = (stream.codec ?? stream.format ?? "").lowercased()
            return textSubtitles.contains(name)
        }
        let chosen: MediaStream?
        if let subtitleStreamID {
            chosen = subtitleStreams.first { $0.id == String(subtitleStreamID) }
        } else {
            chosen = subtitleStreams.first { $0.isForced && isText($0) }
        }
        if let chosen, let chosenID = Int(chosen.id) {
            if isText(chosen) {
                decision.subtitle = .text(streamID: chosenID)
                if decision.method == .directPlay {
                    raise(.directStream)
                    decision.reasons.append("text subtitles: direct stream")
                }
            } else if (decision.width ?? 0) >= 3800 {
                decision.subtitle = .none
                decision.notes.append("Image subtitles off for 4K")
                decision.reasons.append("image subtitles on 4K: left off")
            } else {
                decision.subtitle = .burnIn(streamID: chosenID)
                raise(.transcode)
                decision.reasons.append("image subtitles: burned in")
            }
        }
        return decision
    }
}
