import Foundation
import PerchCore

/// A video library on the server that Perch shows. Music and photo libraries are not listed.
public struct PlexLibrarySection: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case film, series
    }

    public let id: String
    public let title: String
    public let kind: Kind
    /// Home videos and clips (no agent): shown apart from films and series.
    public let isOtherVideos: Bool

    public init(id: String, title: String, kind: Kind, isOtherVideos: Bool = false) {
        self.id = id
        self.title = title
        self.kind = kind
        self.isOtherVideos = isOtherVideos
    }
}

// MARK: container helpers

extension PlexWireContainer {
    /// The server's total for the query, from `totalSize` (read it with `Size=1`).
    var totalCount: Int? { totalSize }

    /// How many rows the server returned on this page. Paging advances by this, not by the number
    /// of items that decoded.
    var rowCount: Int { size ?? metadata?.count ?? 0 }

    var hubs: [PlexWireHub] { hub ?? [] }

    /// Top-level items, or the items of every hub when the reply is a hub list.
    var items: [PlexWireMetadata] {
        metadata ?? hubs.flatMap { $0.metadata ?? [] }
    }
}

// MARK: mapping

enum PlexLibraryMapping {
    /// Movie and show sections only. Other videos are marked by subtype "clip", an agent ending
    /// ".none", or the "Plex Video Files" scanner (approach from Dusk, MIT).
    static func sections(_ directories: [PlexWireDirectory]) -> [PlexLibrarySection] {
        directories.compactMap { directory in
            guard let id = directory.key, !id.isEmpty else { return nil }
            let kind: PlexLibrarySection.Kind
            switch directory.type {
            case "movie": kind = .film
            case "show": kind = .series
            default: return nil
            }
            let other =
                directory.subtype == "clip" || (directory.agent?.hasSuffix(".none") ?? false)
                || directory.scanner == "Plex Video Files"
            return PlexLibrarySection(
                id: id, title: directory.title ?? "", kind: kind, isOtherVideos: other)
        }
    }

    static func kind(forType type: String?) -> MediaKind {
        switch type {
        case "movie": .film
        case "show": .series
        case "season": .season
        case "episode": .episode
        case "clip": .clip
        default: .other
        }
    }

    /// Nil when the item has no rating key, since nothing could open it.
    static func summary(_ item: PlexWireMetadata) -> MediaSummary? {
        guard let id = item.ratingKey, !id.isEmpty else { return nil }
        let kind = kind(forType: item.type)
        var summary = MediaSummary(
            id: id, kind: kind, title: item.title ?? "", year: item.year,
            certificate: item.contentRating, thumbPath: item.thumb, artPath: item.art,
            durationMs: durationMs(item), viewOffsetMs: item.viewOffset,
            viewCount: item.viewCount ?? 0, addedAt: date(seconds: item.addedAt),
            lastViewedAt: date(seconds: item.lastViewedAt))
        switch kind {
        case .episode:
            summary.seriesID = item.grandparentRatingKey
            summary.seriesTitle = item.grandparentTitle
            summary.seasonID = item.parentRatingKey
            summary.seasonNumber = item.parentIndex
            summary.episodeNumber = item.index
            summary.seriesThumbPath = item.grandparentThumb
        case .season:
            summary.seriesID = item.parentRatingKey
            summary.seriesTitle = item.parentTitle
            summary.seasonNumber = item.index
            // On a season, the parent's thumb is the series poster.
            summary.seriesThumbPath = item.parentThumb
        default:
            break
        }
        return summary
    }

    static func summaries(_ items: [PlexWireMetadata]) -> [MediaSummary] {
        items.compactMap(summary)
    }

    static func detail(_ item: PlexWireMetadata) -> MediaDetail? {
        guard let summary = summary(item) else { return nil }
        return MediaDetail(
            summary: summary, synopsis: item.summary, tagline: item.tagline,
            genres: (item.genre ?? []).compactMap(\.tag), studio: item.studio,
            releaseDate: releaseDate(item.originallyAvailableAt), childCount: item.childCount,
            leafCount: item.leafCount, viewedLeafCount: item.viewedLeafCount,
            markers: markers(item.marker ?? []), chapters: chapters(item.chapter ?? []),
            extras: extras(item.extras?.metadata ?? []),
            versions: versions(item.media ?? []),
            externalIDs: (item.guid ?? []).compactMap(\.id))
    }

    // MARK: parts of an item

    static func markers(_ markers: [PlexWireMarker]) -> [MediaMarker] {
        markers.compactMap { marker in
            guard let start = marker.startTimeOffset, let end = marker.endTimeOffset else { return nil }
            let kind: MediaMarker.Kind =
                switch marker.type {
                case "intro": .intro
                case "credits": .credits
                default: .other
                }
            return MediaMarker(kind: kind, startMs: start, endMs: end, isFinal: marker.isFinal ?? false)
        }
    }

    static func chapters(_ chapters: [PlexWireChapter]) -> [MediaChapter] {
        chapters.enumerated().compactMap { offset, chapter in
            guard let start = chapter.startTimeOffset else { return nil }
            return MediaChapter(
                index: chapter.index ?? offset + 1, title: chapter.tag, startMs: start,
                endMs: chapter.endTimeOffset ?? start, thumbPath: chapter.thumb)
        }
    }

    /// Keeps only extras that have a rating key, since the player opens them by it.
    static func extras(_ items: [PlexWireMetadata]) -> [MediaExtra] {
        items.compactMap { item in
            guard let id = item.ratingKey, !id.isEmpty else { return nil }
            return MediaExtra(
                id: id, kind: extraKind(extraType: item.extraType, subtype: item.subtype),
                title: item.title ?? "", durationMs: durationMs(item), thumbPath: item.thumb)
        }
    }

    /// The numeric `extraType` wins; servers that omit it give a string `subtype` instead.
    static func extraKind(extraType: Int?, subtype: String?) -> MediaExtra.Kind {
        if let extraType {
            switch extraType {
            case 1: return .trailer
            case 2: return .deletedScene
            case 3: return .interview
            case 5: return .behindTheScenes
            case 10: return .featurette
            case 11: return .short
            default: return .other
            }
        }
        switch subtype {
        case "trailer": return .trailer
        case "behindTheScenes": return .behindTheScenes
        case "deletedScene": return .deletedScene
        case "interview": return .interview
        case "featurette": return .featurette
        case "short": return .short
        case "clip": return .clip
        default: return .other
        }
    }

    static func versions(_ media: [PlexWireMedia]) -> [MediaVersion] {
        media.enumerated().map { offset, item in
            MediaVersion(
                id: item.id ?? "media-\(offset)", container: item.container,
                videoCodec: item.videoCodec, audioCodec: item.audioCodec,
                videoResolution: item.videoResolution, durationMs: item.duration,
                parts: (item.part ?? []).enumerated().map { part($1, fallback: "part-\($0)") })
        }
    }

    static func part(_ part: PlexWirePart, fallback: String) -> MediaPart {
        MediaPart(
            id: part.id ?? fallback, key: part.key, container: part.container,
            durationMs: part.duration, sizeBytes: part.size.map(Int64.init),
            isAccessible: part.accessible ?? part.exists,
            streams: (part.stream ?? []).compactMap(stream))
    }

    /// Drops a stream with no id or type, since the decision table cannot use it.
    static func stream(_ stream: PlexWireStream) -> MediaStream? {
        guard let id = stream.id, let type = stream.streamType else { return nil }
        let kind: MediaStream.Kind =
            switch type {
            case 1: .video
            case 2: .audio
            case 3: .subtitle
            default: .other
            }
        return MediaStream(
            id: id, kind: kind, codec: stream.codec, languageCode: stream.languageCode,
            title: stream.displayTitle ?? stream.title, isDefault: stream.isDefault ?? false,
            isSelected: stream.selected ?? false, bitDepth: stream.bitDepth,
            colourTransfer: stream.colorTrc, dolbyVisionProfile: stream.doviProfile,
            frameRate: stream.frameRate, width: stream.width, height: stream.height,
            channels: stream.channels, format: stream.format, isForced: stream.forced ?? false,
            key: stream.key)
    }

    // MARK: helpers

    /// The first part's duration is the file's, so it wins over the item's.
    private static func durationMs(_ item: PlexWireMetadata) -> Int? {
        item.media?.first?.part?.first?.duration ?? item.duration
    }

    private static func date(seconds: Int?) -> Date? {
        seconds.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    /// "YYYY-MM-DD" as midnight UTC.
    static func releaseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let numbers = text.split(separator: "-").compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: numbers[0], month: numbers[1], day: numbers[2]))
    }
}
