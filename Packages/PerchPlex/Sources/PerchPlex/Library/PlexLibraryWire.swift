import Foundation

// Internal wire models for Plex library JSON. Every field is optional and numbers, ids and flags
// are decoded leniently, because servers differ on int-or-string and 0/1-or-bool. Elements of an
// array that fail to decode are dropped, never the whole response. Lenient ids and numbers
// approach from Dusk (MIT); nothing is copied.

// MARK: lenient decoding

/// Decodes an array and drops any element that fails, so one odd stream cannot fail an item.
struct PlexLossy<Element: Decodable>: Decodable {
    private struct Skip: Decodable {}

    var elements: [Element] = []

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // A failed decode does not advance; skip the element so the loop ends.
                _ = try? container.decode(Skip.self)
            }
        }
    }
}

extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return Int(value)
        }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if let value = Int(trimmed) { return value }
            if let value = Double(trimmed), value.isFinite { return Int(value) }
        }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return Double(text.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    func lenientBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            switch text.lowercased() {
            case "1", "true": return true
            case "0", "false": return false
            default: return nil
            }
        }
        return nil
    }

    func lossyArray<T: Decodable>(_ key: Key, of type: T.Type) -> [T]? {
        (try? decodeIfPresent(PlexLossy<T>.self, forKey: key))?.elements
    }

    func object<T: Decodable>(_ key: Key, of type: T.Type) -> T? {
        try? decodeIfPresent(T.self, forKey: key)
    }
}

// MARK: envelope

struct PlexWireEnvelope: Decodable {
    var container: PlexWireContainer?

    enum CodingKeys: String, CodingKey { case container = "MediaContainer" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        container = c.object(.container, of: PlexWireContainer.self)
    }
}

struct PlexWireContainer: Decodable {
    var size: Int?
    var totalSize: Int?
    var offset: Int?
    var metadata: [PlexWireMetadata]?
    var directory: [PlexWireDirectory]?
    var hub: [PlexWireHub]?

    enum CodingKeys: String, CodingKey {
        case size, totalSize, offset
        case metadata = "Metadata"
        case directory = "Directory"
        case hub = "Hub"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = c.lenientInt(.size)
        totalSize = c.lenientInt(.totalSize)
        offset = c.lenientInt(.offset)
        metadata = c.lossyArray(.metadata, of: PlexWireMetadata.self)
        directory = c.lossyArray(.directory, of: PlexWireDirectory.self)
        hub = c.lossyArray(.hub, of: PlexWireHub.self)
    }

    /// Decodes `{"MediaContainer": {...}}`. A missing container is an empty one.
    static func decode(from data: Data) throws -> PlexWireContainer {
        try PlexJSON.decode(PlexWireEnvelope.self, from: data).container ?? PlexWireContainer()
    }
}

struct PlexWireDirectory: Decodable {
    var key: String?
    var title: String?
    var type: String?
    var agent: String?
    var scanner: String?
    var subtype: String?
    /// Item count, on firstCharacter buckets.
    var size: Int?

    enum CodingKeys: String, CodingKey { case key, title, type, agent, scanner, subtype, size }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.lenientString(.key)
        title = c.lenientString(.title)
        type = c.lenientString(.type)
        agent = c.lenientString(.agent)
        scanner = c.lenientString(.scanner)
        subtype = c.lenientString(.subtype)
        size = c.lenientInt(.size)
    }
}

struct PlexWireHub: Decodable {
    var hubIdentifier: String?
    var title: String?
    var type: String?
    var key: String?
    var size: Int?
    var more: Bool?
    var metadata: [PlexWireMetadata]?

    enum CodingKeys: String, CodingKey {
        case hubIdentifier, title, type, key, size, more
        case metadata = "Metadata"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hubIdentifier = c.lenientString(.hubIdentifier)
        title = c.lenientString(.title)
        type = c.lenientString(.type)
        key = c.lenientString(.key)
        size = c.lenientInt(.size)
        more = c.lenientBool(.more)
        metadata = c.lossyArray(.metadata, of: PlexWireMetadata.self)
    }
}

struct PlexWireTag: Decodable {
    var tag: String?

    enum CodingKeys: String, CodingKey { case tag }

    init(from decoder: Decoder) throws {
        tag = try decoder.container(keyedBy: CodingKeys.self).lenientString(.tag)
    }
}

/// A cast entry (`Role`): `tag` is the person, `role` the part, `thumb` the portrait.
struct PlexWireRole: Decodable {
    var id: String?
    var tag: String?
    var role: String?
    var thumb: String?

    enum CodingKeys: String, CodingKey { case id, tag, role, thumb }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id)
        tag = c.lenientString(.tag)
        role = c.lenientString(.role)
        thumb = c.lenientString(.thumb)
    }
}

struct PlexWireGuid: Decodable {
    var id: String?

    enum CodingKeys: String, CodingKey { case id }

    init(from decoder: Decoder) throws {
        id = try decoder.container(keyedBy: CodingKeys.self).lenientString(.id)
    }
}

struct PlexWireExtras: Decodable {
    var size: Int?
    var metadata: [PlexWireMetadata]?

    enum CodingKeys: String, CodingKey {
        case size
        case metadata = "Metadata"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = c.lenientInt(.size)
        metadata = c.lossyArray(.metadata, of: PlexWireMetadata.self)
    }
}

// MARK: items

struct PlexWireMetadata: Decodable {
    var ratingKey: String?
    var key: String?
    var type: String?
    var subtype: String?
    var title: String?
    var grandparentTitle: String?
    var grandparentRatingKey: String?
    var grandparentThumb: String?
    var grandparentArt: String?
    var parentTitle: String?
    var parentRatingKey: String?
    var parentThumb: String?
    var parentIndex: Int?
    var index: Int?
    var year: Int?
    var contentRating: String?
    var summary: String?
    var tagline: String?
    var studio: String?
    var thumb: String?
    var art: String?
    var duration: Int?
    var viewOffset: Int?
    var viewCount: Int?
    var leafCount: Int?
    var viewedLeafCount: Int?
    var childCount: Int?
    /// Unix seconds.
    var addedAt: Int?
    /// Unix seconds.
    var lastViewedAt: Int?
    /// "YYYY-MM-DD".
    var originallyAvailableAt: String?
    var librarySectionID: String?
    var extraType: Int?
    var genre: [PlexWireTag]?
    var guid: [PlexWireGuid]?
    var marker: [PlexWireMarker]?
    var chapter: [PlexWireChapter]?
    var media: [PlexWireMedia]?
    var extras: PlexWireExtras?
    var image: [PlexWireImage]?
    /// The theme tune's server path, e.g. "/library/metadata/2000/theme/1700000000".
    var theme: String?
    var role: [PlexWireRole]?

    enum CodingKeys: String, CodingKey {
        case ratingKey, key, type, subtype, title
        case grandparentTitle, grandparentRatingKey, grandparentThumb, grandparentArt
        case parentTitle, parentRatingKey, parentThumb, parentIndex, index
        case year, contentRating, summary, tagline, studio, thumb, art, theme
        case duration, viewOffset, viewCount, leafCount, viewedLeafCount, childCount
        case addedAt, lastViewedAt, originallyAvailableAt, librarySectionID, extraType
        case role = "Role"
        case genre = "Genre"
        case guid = "Guid"
        case marker = "Marker"
        case chapter = "Chapter"
        case media = "Media"
        case extras = "Extras"
        case image = "Image"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ratingKey = c.lenientString(.ratingKey)
        key = c.lenientString(.key)
        type = c.lenientString(.type)
        subtype = c.lenientString(.subtype)
        title = c.lenientString(.title)
        grandparentTitle = c.lenientString(.grandparentTitle)
        grandparentRatingKey = c.lenientString(.grandparentRatingKey)
        grandparentThumb = c.lenientString(.grandparentThumb)
        grandparentArt = c.lenientString(.grandparentArt)
        parentTitle = c.lenientString(.parentTitle)
        parentRatingKey = c.lenientString(.parentRatingKey)
        parentThumb = c.lenientString(.parentThumb)
        parentIndex = c.lenientInt(.parentIndex)
        index = c.lenientInt(.index)
        year = c.lenientInt(.year)
        contentRating = c.lenientString(.contentRating)
        summary = c.lenientString(.summary)
        tagline = c.lenientString(.tagline)
        studio = c.lenientString(.studio)
        thumb = c.lenientString(.thumb)
        art = c.lenientString(.art)
        duration = c.lenientInt(.duration)
        viewOffset = c.lenientInt(.viewOffset)
        viewCount = c.lenientInt(.viewCount)
        leafCount = c.lenientInt(.leafCount)
        viewedLeafCount = c.lenientInt(.viewedLeafCount)
        childCount = c.lenientInt(.childCount)
        addedAt = c.lenientInt(.addedAt)
        lastViewedAt = c.lenientInt(.lastViewedAt)
        image = c.lossyArray(.image, of: PlexWireImage.self)
        originallyAvailableAt = c.lenientString(.originallyAvailableAt)
        librarySectionID = c.lenientString(.librarySectionID)
        extraType = c.lenientInt(.extraType)
        genre = c.lossyArray(.genre, of: PlexWireTag.self)
        guid = c.lossyArray(.guid, of: PlexWireGuid.self)
        marker = c.lossyArray(.marker, of: PlexWireMarker.self)
        chapter = c.lossyArray(.chapter, of: PlexWireChapter.self)
        media = c.lossyArray(.media, of: PlexWireMedia.self)
        extras = c.object(.extras, of: PlexWireExtras.self)
        theme = c.lenientString(.theme)
        role = c.lossyArray(.role, of: PlexWireRole.self)
    }
}

struct PlexWireMedia: Decodable {
    var id: String?
    var container: String?
    var videoCodec: String?
    var audioCodec: String?
    var videoResolution: String?
    var duration: Int?
    var part: [PlexWirePart]?

    enum CodingKeys: String, CodingKey {
        case id, container, videoCodec, audioCodec, videoResolution, duration
        case part = "Part"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id)
        container = c.lenientString(.container)
        videoCodec = c.lenientString(.videoCodec)
        audioCodec = c.lenientString(.audioCodec)
        videoResolution = c.lenientString(.videoResolution)
        duration = c.lenientInt(.duration)
        part = c.lossyArray(.part, of: PlexWirePart.self)
    }
}

/// One entry of a metadata item's `Image` array (coverPoster, background, clearLogo, snapshot).
struct PlexWireImage: Decodable {
    var type: String?
    var url: String?

    enum CodingKeys: String, CodingKey { case type, url }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = c.lenientString(.type)
        url = c.lenientString(.url)
    }
}

struct PlexWirePart: Decodable {
    var id: String?
    var key: String?
    var container: String?
    var duration: Int?
    var size: Int?
    var accessible: Bool?
    var exists: Bool?
    var stream: [PlexWireStream]?

    enum CodingKeys: String, CodingKey {
        case id, key, container, duration, size, accessible, exists
        case stream = "Stream"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id)
        key = c.lenientString(.key)
        container = c.lenientString(.container)
        duration = c.lenientInt(.duration)
        size = c.lenientInt(.size)
        accessible = c.lenientBool(.accessible)
        exists = c.lenientBool(.exists)
        stream = c.lossyArray(.stream, of: PlexWireStream.self)
    }
}

struct PlexWireStream: Decodable {
    var id: String?
    /// 1 video, 2 audio, 3 subtitle.
    var streamType: Int?
    var codec: String?
    var languageCode: String?
    var displayTitle: String?
    var title: String?
    var isDefault: Bool?
    var selected: Bool?
    var bitDepth: Int?
    var colorTrc: String?
    var doviProfile: Int?
    var frameRate: Double?
    var width: Int?
    var height: Int?
    var channels: Int?
    var format: String?
    var forced: Bool?
    var key: String?
    var profile: String?
    var audioChannelLayout: String?
    var doviPresent: Bool?
    var doviLevel: Int?
    var doviBLCompatID: Int?
    var colorPrimaries: String?
    var colorSpace: String?
    var scanType: String?
    var extendedDisplayTitle: String?

    enum CodingKeys: String, CodingKey {
        case profile, audioChannelLayout, colorPrimaries, colorSpace, scanType, extendedDisplayTitle
        case doviPresent = "DOVIPresent", doviLevel = "DOVILevel", doviBLCompatID = "DOVIBLCompatID"
        case id, streamType, codec, languageCode, displayTitle, title
        case isDefault = "default"
        case selected, bitDepth, colorTrc
        case doviProfile = "DOVIProfile"
        case frameRate, width, height, channels, format, forced, key
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id)
        streamType = c.lenientInt(.streamType)
        codec = c.lenientString(.codec)
        languageCode = c.lenientString(.languageCode)
        displayTitle = c.lenientString(.displayTitle)
        title = c.lenientString(.title)
        isDefault = c.lenientBool(.isDefault)
        selected = c.lenientBool(.selected)
        bitDepth = c.lenientInt(.bitDepth)
        colorTrc = c.lenientString(.colorTrc)
        doviProfile = c.lenientInt(.doviProfile)
        frameRate = c.lenientDouble(.frameRate)
        width = c.lenientInt(.width)
        height = c.lenientInt(.height)
        channels = c.lenientInt(.channels)
        format = c.lenientString(.format)
        forced = c.lenientBool(.forced)
        key = c.lenientString(.key)
        profile = c.lenientString(.profile)
        audioChannelLayout = c.lenientString(.audioChannelLayout)
        doviPresent = c.lenientBool(.doviPresent)
        doviLevel = c.lenientInt(.doviLevel)
        doviBLCompatID = c.lenientInt(.doviBLCompatID)
        colorPrimaries = c.lenientString(.colorPrimaries)
        colorSpace = c.lenientString(.colorSpace)
        scanType = c.lenientString(.scanType)
        extendedDisplayTitle = c.lenientString(.extendedDisplayTitle)
    }
}

struct PlexWireMarker: Decodable {
    var id: String?
    var type: String?
    var startTimeOffset: Int?
    var endTimeOffset: Int?
    var isFinal: Bool?

    enum CodingKeys: String, CodingKey { case id, type, startTimeOffset, endTimeOffset
        case isFinal = "final"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id)
        type = c.lenientString(.type)
        startTimeOffset = c.lenientInt(.startTimeOffset)
        endTimeOffset = c.lenientInt(.endTimeOffset)
        isFinal = c.lenientBool(.isFinal)
    }
}

struct PlexWireChapter: Decodable {
    var index: Int?
    var tag: String?
    var startTimeOffset: Int?
    var endTimeOffset: Int?
    var thumb: String?

    enum CodingKeys: String, CodingKey { case index, tag, startTimeOffset, endTimeOffset, thumb }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = c.lenientInt(.index)
        tag = c.lenientString(.tag)
        startTimeOffset = c.lenientInt(.startTimeOffset)
        endTimeOffset = c.lenientInt(.endTimeOffset)
        thumb = c.lenientString(.thumb)
    }
}
