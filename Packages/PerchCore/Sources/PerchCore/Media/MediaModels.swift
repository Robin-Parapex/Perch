import Foundation

// Neutral media types. Modules map their own wire formats into these, so Home, the player and
// later modules need nothing service-shaped (MODULES.md, PerchCore owns models). All times are ms.

public enum MediaKind: String, Codable, Sendable, Hashable {
    case film, series, season, episode, clip, other
}

/// One title as a row or grid shows it.
public struct MediaSummary: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: MediaKind
    public var title: String
    public var seriesID: String?
    public var seriesTitle: String?
    public var seasonID: String?
    public var seasonNumber: Int?
    public var episodeNumber: Int?
    public var year: Int?
    public var certificate: String?
    public var thumbPath: String?
    public var artPath: String?
    public var seriesThumbPath: String?
    /// Transparent title logo (Plex clearLogo). Nil when the server has none.
    public var logoPath: String?
    public var durationMs: Int?
    public var viewOffsetMs: Int?
    public var viewCount: Int
    public var addedAt: Date?
    public var lastViewedAt: Date?
    /// Short synopsis for the Home hero. Optional so older snapshot files still decode.
    public var summary: String?

    public init(
        id: String, kind: MediaKind, title: String, seriesID: String? = nil,
        seriesTitle: String? = nil, seasonID: String? = nil, seasonNumber: Int? = nil,
        episodeNumber: Int? = nil, year: Int? = nil, certificate: String? = nil,
        thumbPath: String? = nil, artPath: String? = nil, seriesThumbPath: String? = nil,
        durationMs: Int? = nil, viewOffsetMs: Int? = nil, viewCount: Int = 0,
        addedAt: Date? = nil, lastViewedAt: Date? = nil, logoPath: String? = nil,
        summary: String? = nil
    ) {
        self.summary = summary
        self.id = id
        self.kind = kind
        self.title = title
        self.seriesID = seriesID
        self.seriesTitle = seriesTitle
        self.seasonID = seasonID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.year = year
        self.certificate = certificate
        self.thumbPath = thumbPath
        self.artPath = artPath
        self.seriesThumbPath = seriesThumbPath
        self.logoPath = logoPath
        self.durationMs = durationMs
        self.viewOffsetMs = viewOffsetMs
        self.viewCount = viewCount
        self.addedAt = addedAt
        self.lastViewedAt = lastViewedAt
    }

    /// Started and not finished.
    public var isInProgress: Bool { (viewOffsetMs ?? 0) > 0 }

    public var isWatched: Bool { viewCount > 0 && !isInProgress }

    /// Nil when the duration is missing or shorter than the offset, which some files report
    /// until first played (INTEGRATIONS.md). Callers then show no time left.
    public var remainingMs: Int? {
        guard let durationMs, durationMs > 0 else { return nil }
        let offset = viewOffsetMs ?? 0
        guard offset <= durationMs else { return nil }
        return durationMs - offset
    }

    /// 0 to 1, or nil when `remainingMs` is nil.
    public var progress: Double? {
        guard let durationMs, remainingMs != nil else { return nil }
        return Double(viewOffsetMs ?? 0) / Double(durationMs)
    }
}

/// A titled list of titles, such as Continue watching.
public struct MediaRow: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var items: [MediaSummary]

    public init(id: String, title: String, items: [MediaSummary]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

public struct MediaMarker: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case intro, credits, other
    }

    public var kind: Kind
    public var startMs: Int
    public var endMs: Int
    /// True for the credits that run to the end, as opposed to mid-film credits.
    public var isFinal: Bool

    public init(kind: Kind, startMs: Int, endMs: Int, isFinal: Bool = false) {
        self.kind = kind
        self.startMs = startMs
        self.endMs = endMs
        self.isFinal = isFinal
    }
}

public struct MediaChapter: Codable, Sendable, Hashable {
    public var index: Int
    public var title: String?
    public var startMs: Int
    public var endMs: Int
    public var thumbPath: String?

    public init(index: Int, title: String?, startMs: Int, endMs: Int, thumbPath: String? = nil) {
        self.index = index
        self.title = title
        self.startMs = startMs
        self.endMs = endMs
        self.thumbPath = thumbPath
    }
}

public struct MediaExtra: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case trailer, behindTheScenes, deletedScene, interview, featurette, short, clip, other
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var durationMs: Int?
    public var thumbPath: String?

    public init(id: String, kind: Kind, title: String, durationMs: Int? = nil, thumbPath: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.durationMs = durationMs
        self.thumbPath = thumbPath
    }
}

/// One video, audio or subtitle track, with what the playback decision table reads
/// (ARCHITECTURE.md, decision table).
public struct MediaStream: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case video, audio, subtitle, other
    }

    public var id: String
    public var kind: Kind
    public var codec: String?
    public var languageCode: String?
    public var title: String?
    public var isDefault: Bool
    public var isSelected: Bool
    // Video
    public var bitDepth: Int?
    public var colourTransfer: String?
    public var dolbyVisionProfile: Int?
    public var frameRate: Double?
    public var width: Int?
    public var height: Int?
    // Audio
    public var channels: Int?
    // Subtitle
    public var format: String?
    public var isForced: Bool
    /// Path of a sidecar subtitle file; nil when embedded.
    public var key: String?
    // Extra detail for the playback decision and the playback log.
    /// Codec profile, e.g. "main 10", "dts-hd ma", "truehd".
    public var profile: String?
    public var audioChannelLayout: String?
    public var dolbyVisionPresent: Bool?
    public var dolbyVisionLevel: Int?
    public var dolbyVisionBLCompatID: Int?
    public var colourPrimaries: String?
    public var colourSpace: String?
    public var scanType: String?
    public var displayTitle: String?
    /// Atmos and DTS:X show up in the display titles.
    public var extendedDisplayTitle: String?

    public init(
        id: String, kind: Kind, codec: String? = nil, languageCode: String? = nil,
        title: String? = nil, isDefault: Bool = false, isSelected: Bool = false,
        bitDepth: Int? = nil, colourTransfer: String? = nil, dolbyVisionProfile: Int? = nil,
        frameRate: Double? = nil, width: Int? = nil, height: Int? = nil, channels: Int? = nil,
        format: String? = nil, isForced: Bool = false, key: String? = nil,
        profile: String? = nil, audioChannelLayout: String? = nil, dolbyVisionPresent: Bool? = nil,
        dolbyVisionLevel: Int? = nil, dolbyVisionBLCompatID: Int? = nil,
        colourPrimaries: String? = nil, colourSpace: String? = nil, scanType: String? = nil,
        displayTitle: String? = nil, extendedDisplayTitle: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.codec = codec
        self.languageCode = languageCode
        self.title = title
        self.isDefault = isDefault
        self.isSelected = isSelected
        self.bitDepth = bitDepth
        self.colourTransfer = colourTransfer
        self.dolbyVisionProfile = dolbyVisionProfile
        self.frameRate = frameRate
        self.width = width
        self.height = height
        self.channels = channels
        self.format = format
        self.isForced = isForced
        self.key = key
        self.profile = profile
        self.audioChannelLayout = audioChannelLayout
        self.dolbyVisionPresent = dolbyVisionPresent
        self.dolbyVisionLevel = dolbyVisionLevel
        self.dolbyVisionBLCompatID = dolbyVisionBLCompatID
        self.colourPrimaries = colourPrimaries
        self.colourSpace = colourSpace
        self.scanType = scanType
        self.displayTitle = displayTitle
        self.extendedDisplayTitle = extendedDisplayTitle
    }
}

/// One file of a version.
public struct MediaPart: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    /// Server path of the file, for the player to build its request from.
    public var key: String?
    public var container: String?
    public var durationMs: Int?
    public var sizeBytes: Int64?
    /// Nil until checked; set when the metadata was fetched for playback.
    public var isAccessible: Bool?
    public var streams: [MediaStream]

    public init(
        id: String, key: String?, container: String? = nil, durationMs: Int? = nil,
        sizeBytes: Int64? = nil, isAccessible: Bool? = nil, streams: [MediaStream] = []
    ) {
        self.id = id
        self.key = key
        self.container = container
        self.durationMs = durationMs
        self.sizeBytes = sizeBytes
        self.isAccessible = isAccessible
        self.streams = streams
    }
}

/// One edition or encode of a title.
public struct MediaVersion: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var container: String?
    public var videoCodec: String?
    public var audioCodec: String?
    public var videoResolution: String?
    public var durationMs: Int?
    public var parts: [MediaPart]

    public init(
        id: String, container: String? = nil, videoCodec: String? = nil, audioCodec: String? = nil,
        videoResolution: String? = nil, durationMs: Int? = nil, parts: [MediaPart] = []
    ) {
        self.id = id
        self.container = container
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.videoResolution = videoResolution
        self.durationMs = durationMs
        self.parts = parts
    }
}

/// Everything a title page or the player needs about one title.
public struct MediaDetail: Codable, Sendable, Hashable, Identifiable {
    public var summary: MediaSummary
    public var synopsis: String?
    public var tagline: String?
    public var genres: [String]
    public var studio: String?
    public var releaseDate: Date?
    public var childCount: Int?
    public var leafCount: Int?
    public var viewedLeafCount: Int?
    public var markers: [MediaMarker]
    public var chapters: [MediaChapter]
    public var extras: [MediaExtra]
    public var versions: [MediaVersion]
    /// External ids such as "imdb://tt0111161" or "tmdb://278".
    public var externalIDs: [String]

    public var id: String { summary.id }

    public init(
        summary: MediaSummary, synopsis: String? = nil, tagline: String? = nil,
        genres: [String] = [], studio: String? = nil, releaseDate: Date? = nil,
        childCount: Int? = nil, leafCount: Int? = nil, viewedLeafCount: Int? = nil,
        markers: [MediaMarker] = [], chapters: [MediaChapter] = [], extras: [MediaExtra] = [],
        versions: [MediaVersion] = [], externalIDs: [String] = []
    ) {
        self.summary = summary
        self.synopsis = synopsis
        self.tagline = tagline
        self.genres = genres
        self.studio = studio
        self.releaseDate = releaseDate
        self.childCount = childCount
        self.leafCount = leafCount
        self.viewedLeafCount = viewedLeafCount
        self.markers = markers
        self.chapters = chapters
        self.extras = extras
        self.versions = versions
        self.externalIDs = externalIDs
    }

    public var introMarker: MediaMarker? { markers.first { $0.kind == .intro } }

    /// The final credits if marked, else the last credits marker.
    public var creditsMarker: MediaMarker? {
        let credits = markers.filter { $0.kind == .credits }
        return credits.first(where: \.isFinal) ?? credits.max { $0.startMs < $1.startMs }
    }
}
