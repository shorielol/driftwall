import Foundation

/// One live wallpaper. Media stays at its source; we only carry links and attribution.
public struct Wallpaper: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
    public let category: String
    public let tags: [String]
    public let source: String
    public let sourcePageURL: URL
    public let previewURL: URL
    public let videoURL: URL
    public let posterURL: URL
    public let author: String
    public let license: String
    public let licenseURL: URL?
    public let durationSeconds: Int
    public let width: Int
    public let height: Int
    public let fileSizeMB: Double
    public let uploadedAt: String
    public let sourceRank: Int
    public let addedInDrop: String

    enum CodingKeys: String, CodingKey {
        case id, title, description, category, tags, source, author, license
        case sourcePageURL = "sourcePageUrl"
        case previewURL = "previewUrl"
        case videoURL = "videoUrl"
        case posterURL = "posterUrl"
        case licenseURL = "licenseUrl"
        case durationSeconds, width, height
        case fileSizeMB, uploadedAt, sourceRank, addedInDrop
    }

    public init(
        id: String, title: String, description: String = "", category: String, tags: [String] = [],
        source: String, sourcePageURL: URL, previewURL: URL, videoURL: URL, posterURL: URL,
        author: String, license: String, licenseURL: URL? = nil, durationSeconds: Int,
        width: Int, height: Int, fileSizeMB: Double = 0, uploadedAt: String = "",
        sourceRank: Int = 0, addedInDrop: String = ""
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.tags = tags
        self.source = source
        self.sourcePageURL = sourcePageURL
        self.previewURL = previewURL
        self.videoURL = videoURL
        self.posterURL = posterURL
        self.author = author
        self.license = license
        self.licenseURL = licenseURL
        self.durationSeconds = durationSeconds
        self.width = width
        self.height = height
        self.fileSizeMB = fileSizeMB
        self.uploadedAt = uploadedAt
        self.sourceRank = sourceRank
        self.addedInDrop = addedInDrop
    }

    public static let minimum4KHeight = 2160
    /// Nothing below Full HD is ever shown; 4K is preferred.
    public static let minimumHeight = 1080

    public var is4K: Bool { height >= Self.minimum4KHeight && width > height }

    /// Human name of where the clip comes from, for "View on …" links.
    public var sourceName: String {
        switch source {
        case "nasa": "NASA"
        case "esa": sourcePageURL.host() == "esahubble.org" ? "ESA/Hubble" : "ESA/Webb"
        case "blender": "Blender Studio"
        default: source.capitalized
        }
    }
    public var meetsMinimumResolution: Bool { height >= Self.minimumHeight && width > height }

    /// Labelled by the short side, so a portrait clip isn't mislabelled by its height.
    public var resolutionLabel: String {
        switch min(width, height) {
        case 4320...: "8K"
        case 2880...: "5K"
        case 2160...: "4K"
        case 1440...: "2K"
        case 1080...: "1080p"
        default: "HD"
        }
    }

    public var durationLabel: String {
        String(format: "%d:%02d", durationSeconds / 60, durationSeconds % 60)
    }

    /// Hosts the app will fetch media from or open in the browser. Anything else is dropped.
    public static let allowedHosts: Set<String> = [
        // Every loop's media is published as a GitHub Release asset.
        "github.com",
        // Source pages and licences, for credit links.
        "svs.gsfc.nasa.gov", "www.nasa.gov", "esawebb.org", "esahubble.org",
        "studio.blender.org", "commons.wikimedia.org", "creativecommons.org",
    ]
    static let reservedIDPrefix = "custom-"
    static let maxTitleLength = 200
    static let maxDescriptionLength = 2_000
    static let maxTags = 40
    static let durationRange = 1...3_600
    static let dimensionRange = 1...16_384

    static func isAllowed(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && allowedHosts.contains(url.host()?.lowercased() ?? "")
    }

    /// Every URL we fetch or open must be https on an allow-listed host.
    var hasSecureURLs: Bool {
        [sourcePageURL, previewURL, videoURL, posterURL].allSatisfy(Self.isAllowed)
    }

    /// Plausible values only; protects layout and arithmetic from a hostile catalog.
    var hasSaneValues: Bool {
        !id.hasPrefix(Self.reservedIDPrefix)
            && !title.isEmpty && title.count <= Self.maxTitleLength
            && description.count <= Self.maxDescriptionLength
            && tags.count <= Self.maxTags
            && Self.durationRange.contains(durationSeconds)
            && Self.dimensionRange.contains(width) && Self.dimensionRange.contains(height)
            && fileSizeMB >= 0
    }

    /// Same entry with an unsafe license link removed.
    func withSafeLicenseLink() -> Wallpaper {
        guard let licenseURL, !Self.isAllowed(licenseURL) else { return self }
        return Wallpaper(
            id: id, title: title, description: description, category: category, tags: tags, source: source,
            sourcePageURL: sourcePageURL, previewURL: previewURL, videoURL: videoURL, posterURL: posterURL,
            author: author, license: license, licenseURL: nil, durationSeconds: durationSeconds,
            width: width, height: height, fileSizeMB: fileSizeMB, uploadedAt: uploadedAt,
            sourceRank: sourceRank, addedInDrop: addedInDrop
        )
    }
}

public struct CatalogDrop: Codable, Hashable, Sendable {
    public let dropId: String
    public let date: String
    public let ids: [String]

    public init(dropId: String, date: String, ids: [String]) {
        self.dropId = dropId
        self.date = date
        self.ids = ids
    }
}

public enum CatalogError: Error, Equatable, Sendable {
    case malformed(String)
    case unsupportedSchema(Int)
}

public struct Catalog: Codable, Hashable, Sendable {
    public static let supportedSchemaVersion = 1
    public static let maxWallpapers = 5_000
    public static let categoryOrder = [
        "Space", "Cinematic", "Animated", "Fantasy", "Sci-fi", "Nature", "Abstract",
    ]

    public let schemaVersion: Int
    public let generatedAt: String
    public let dropId: String
    public let nextDropAt: String
    public let featured: [String]
    public let drops: [CatalogDrop]
    public let wallpapers: [Wallpaper]

    public init(
        schemaVersion: Int = Catalog.supportedSchemaVersion, generatedAt: String = "", dropId: String = "",
        nextDropAt: String = "", featured: [String] = [], drops: [CatalogDrop] = [], wallpapers: [Wallpaper] = []
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.dropId = dropId
        self.nextDropAt = nextDropAt
        self.featured = featured
        self.drops = drops
        self.wallpapers = wallpapers
    }

    public static let empty = Catalog()

    /// Decode untrusted catalog bytes, then keep only secure, landscape entries at 1080p or better.
    public static func decodeValidated(from data: Data) throws(CatalogError) -> Catalog {
        let raw: Catalog
        do {
            raw = try JSONDecoder().decode(Catalog.self, from: data)
        } catch {
            throw .malformed(String(describing: error))
        }
        guard raw.schemaVersion == supportedSchemaVersion else {
            throw .unsupportedSchema(raw.schemaVersion)
        }
        return raw.sanitized()
    }

    func sanitized() -> Catalog {
        var seen = Set<String>()
        let valid = wallpapers.prefix(Self.maxWallpapers).filter { wallpaper in
            guard wallpaper.meetsMinimumResolution, wallpaper.hasSecureURLs, wallpaper.hasSaneValues, !seen.contains(wallpaper.id) else { return false }
            seen.insert(wallpaper.id)
            return true
        }.map { $0.withSafeLicenseLink() }
        return Catalog(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            dropId: dropId,
            nextDropAt: nextDropAt,
            featured: featured.filter(seen.contains),
            drops: drops.map { CatalogDrop(dropId: $0.dropId, date: $0.date, ids: $0.ids.filter(seen.contains)) },
            wallpapers: valid
        )
    }

    public func wallpaper(id: String) -> Wallpaper? {
        wallpapers.first { $0.id == id }
    }

    public func wallpapers(ids: [String]) -> [Wallpaper] {
        let lookup = Dictionary(wallpapers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { lookup[$0] }
    }

    public var featuredWallpapers: [Wallpaper] { wallpapers(ids: featured) }

    public var latestDropWallpapers: [Wallpaper] {
        guard let latest = drops.last(where: { $0.dropId == dropId }) ?? drops.last else { return [] }
        return wallpapers(ids: latest.ids)
    }

    /// "New" only means something once there is an older drop to compare against.
    public func isNew(_ wallpaper: Wallpaper) -> Bool {
        drops.count > 1 && !dropId.isEmpty && wallpaper.addedInDrop == dropId
    }

    public func hasNewDrop(comparedTo lastSeenDropId: String?) -> Bool {
        guard let lastSeenDropId, !dropId.isEmpty else { return false }
        return dropId != lastSeenDropId
    }

    public func daysUntilNextDrop(from now: Date, calendar: Calendar = .current) -> Int? {
        let parser = DateFormatter()
        parser.calendar = calendar
        parser.timeZone = calendar.timeZone
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let next = parser.date(from: nextDropAt) else { return nil }
        let start = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: next)).day
        return days.map { max(0, $0) }
    }

    public var categories: [String] {
        let present = Set(wallpapers.map(\.category))
        let known = Self.categoryOrder.filter(present.contains)
        let unknown = present.subtracting(Self.categoryOrder).sorted()
        return known + unknown
    }
}
