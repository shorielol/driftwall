import Foundation
import Testing
@testable import DriftwallCore

func fixtureData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
    return try Data(contentsOf: url)
}

func loadFixtureCatalog() throws -> Catalog {
    try Catalog.decodeValidated(from: fixtureData("catalog.json"))
}

@Suite("Catalog decoding and validation")
struct CatalogDecodingTests {
    @Test func `keeps only https landscape wallpapers at 1080p or better`() throws {
        let catalog = try loadFixtureCatalog()
        #expect(catalog.wallpapers.map(\.id) == ["mixkit-1", "mixkit-2"])
        #expect(catalog.wallpapers.allSatisfy { $0.meetsMinimumResolution })
    }

    @Test func `decodes metadata fields`() throws {
        let wallpaper = try #require(try loadFixtureCatalog().wallpaper(id: "mixkit-2"))
        #expect(wallpaper.title == "Aurora Over Lake")
        #expect(wallpaper.category == "Space")
        #expect(wallpaper.durationSeconds == 30)
        #expect(wallpaper.videoURL.absoluteString.hasSuffix("-2160.mp4"))
        #expect(wallpaper.previewURL.absoluteString.hasSuffix("-720.mp4"))
        #expect(wallpaper.resolutionLabel == "4K")
    }

    @Test func `rejects unsupported schema version`() {
        let json = #"{"schemaVersion":99,"generatedAt":"","dropId":"","nextDropAt":"","featured":[],"drops":[],"wallpapers":[]}"#
        #expect(throws: CatalogError.unsupportedSchema(99)) {
            try Catalog.decodeValidated(from: Data(json.utf8))
        }
    }

    @Test func `rejects malformed json`() {
        #expect(throws: CatalogError.self) {
            try Catalog.decodeValidated(from: Data("not json".utf8))
        }
    }

    @Test func `drops dangling featured and drop ids after filtering`() throws {
        let catalog = try loadFixtureCatalog()
        #expect(catalog.featured == ["mixkit-2", "mixkit-1"])
        #expect(catalog.drops.first?.ids == ["mixkit-1"])
    }

    @Test func `encodes and decodes round trip`() throws {
        let catalog = try loadFixtureCatalog()
        let data = try JSONEncoder().encode(catalog)
        #expect(try Catalog.decodeValidated(from: data) == catalog)
    }
}

@Suite("Catalog drops")
struct CatalogDropTests {
    @Test func `latest drop and featured resolve to wallpapers`() throws {
        let catalog = try loadFixtureCatalog()
        #expect(catalog.latestDropWallpapers.map(\.id) == ["mixkit-2"])
        #expect(catalog.featuredWallpapers.map(\.id) == ["mixkit-2", "mixkit-1"])
    }

    @Test func `marks wallpapers from current drop as new`() throws {
        let catalog = try loadFixtureCatalog()
        let fresh = try #require(catalog.wallpaper(id: "mixkit-2"))
        let older = try #require(catalog.wallpaper(id: "mixkit-1"))
        #expect(catalog.isNew(fresh))
        #expect(!catalog.isNew(older))
    }

    @Test func `days until next drop`() throws {
        let catalog = try loadFixtureCatalog()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 4, hour: 10)))
        #expect(catalog.daysUntilNextDrop(from: now, calendar: calendar) == 10)
    }

    @Test func `new drop detection compares drop ids`() throws {
        let catalog = try loadFixtureCatalog()
        #expect(catalog.hasNewDrop(comparedTo: "2026-11-02"))
        #expect(!catalog.hasNewDrop(comparedTo: "2026-11-23"))
        #expect(!catalog.hasNewDrop(comparedTo: nil))
    }
}

@Suite("Catalog query")
struct CatalogQueryTests {
    let wallpapers: [Wallpaper]

    init() throws {
        wallpapers = try loadFixtureCatalog().wallpapers
    }

    @Test func `search matches title case insensitively`() {
        let result = CatalogQuery(text: "aurora").apply(to: wallpapers)
        #expect(result.map(\.id) == ["mixkit-2"])
    }

    @Test func `search matches tags`() {
        #expect(CatalogQuery(text: "RAIN").apply(to: wallpapers).count == 2)
    }

    @Test func `category filter`() {
        #expect(CatalogQuery(category: "Nature").apply(to: wallpapers).map(\.id) == ["mixkit-1"])
    }

    @Test(arguments: [
        (WallpaperSort.popular, ["mixkit-2", "mixkit-1"]),
        (WallpaperSort.newest, ["mixkit-2", "mixkit-1"]),
        (WallpaperSort.longest, ["mixkit-2", "mixkit-1"]),
        (WallpaperSort.title, ["mixkit-2", "mixkit-1"]),
    ])
    func sorting(sort: WallpaperSort, expected: [String]) {
        #expect(CatalogQuery(sort: sort).apply(to: wallpapers).map(\.id) == expected)
    }

    @Test func `title sort is alphabetical not input order`() {
        let reversed = Array(wallpapers.reversed())
        #expect(CatalogQuery(sort: .title).apply(to: reversed).map(\.title) == ["Aurora Over Lake", "Misty Forest Morning"])
    }

    @Test func `blank query returns everything`() {
        #expect(CatalogQuery(text: "   ").apply(to: wallpapers).count == wallpapers.count)
    }

    @Test func `categories are distinct and ordered by known taxonomy`() throws {
        let catalog = try loadFixtureCatalog()
        #expect(catalog.categories == ["Space", "Nature"])
    }
}

@Suite("Catalog hardening")
struct CatalogHardeningTests {
    private func entry(id: String, host: String = "assets.mixkit.co", license: String = "https://mixkit.co/license/#videoFree",
                       title: String = "Ok", duration: Int = 20, width: Int = 3840, height: Int = 2160) -> String {
        """
        {"id":"\(id)","title":"\(title)","description":"","category":"Nature","tags":[],"source":"mixkit",
         "sourcePageUrl":"https://mixkit.co/free-stock-video/x-1/","previewUrl":"https://\(host)/p-720.mp4",
         "videoUrl":"https://\(host)/v-2160.mp4","posterUrl":"https://\(host)/p.jpg","author":"Mixkit",
         "license":"Free","licenseUrl":"\(license)","durationSeconds":\(duration),"width":\(width),"height":\(height),
         "fileSizeMB":10,"uploadedAt":"","sourceRank":0,"addedInDrop":"d"}
        """
    }

    private func decode(_ entries: [String]) throws -> Catalog {
        let json = #"{"schemaVersion":1,"generatedAt":"","dropId":"d","nextDropAt":"","featured":[],"drops":[],"wallpapers":["#
            + entries.joined(separator: ",") + "]}"
        return try Catalog.decodeValidated(from: Data(json.utf8))
    }

    @Test func `media on unknown hosts is dropped`() throws {
        let catalog = try decode([entry(id: "good"), entry(id: "evil", host: "tracker.example")])
        #expect(catalog.wallpapers.map(\.id) == ["good"])
    }

    @Test func `ids in the custom namespace are rejected`() throws {
        #expect(try decode([entry(id: "custom-x")]).wallpapers.isEmpty)
    }

    @Test func `unsafe license links are removed but the entry is kept`() throws {
        let catalog = try decode([entry(id: "a", license: "smb://attacker/share"), entry(id: "b", license: "file:///etc/passwd")])
        #expect(catalog.wallpapers.count == 2)
        #expect(catalog.wallpapers.allSatisfy { $0.licenseURL == nil })
    }

    @Test func `absurd values are rejected`() throws {
        let longTitle = String(repeating: "x", count: 500)
        let catalog = try decode([entry(id: "a", title: longTitle), entry(id: "b", duration: -5), entry(id: "c")])
        #expect(catalog.wallpapers.map(\.id) == ["c"])
    }
}

@Suite("New badge")
struct NewBadgeTests {
    @Test func `first ever drop marks nothing as new`() throws {
        let full = try loadFixtureCatalog()
        let single = Catalog(dropId: full.dropId, drops: [try #require(full.drops.last)], wallpapers: full.wallpapers)
        #expect(single.wallpapers.allSatisfy { !single.isNew($0) })
    }
}

@Suite("Resolution policy")
struct ResolutionPolicyTests {
    private func wallpaper(_ width: Int, _ height: Int) -> Wallpaper {
        Wallpaper(
            id: "w", title: "w", category: "Anime", source: "pixabay",
            sourcePageURL: URL(string: "https://pixabay.com/videos/w-1/")!,
            previewURL: URL(string: "https://cdn.pixabay.com/p.mp4")!,
            videoURL: URL(string: "https://cdn.pixabay.com/v.mp4")!,
            posterURL: URL(string: "https://cdn.pixabay.com/p.jpg")!,
            author: "a", license: "Pixabay Content License", durationSeconds: 10, width: width, height: height
        )
    }

    @Test(arguments: [(3840, 2160, "4K", true), (2560, 1440, "2K", true), (1920, 1080, "1080p", true), (1280, 720, "HD", false), (1080, 1920, "1080p", false)])
    func policy(width: Int, height: Int, label: String, allowed: Bool) {
        let item = wallpaper(width, height)
        #expect(item.resolutionLabel == label)
        #expect(item.meetsMinimumResolution == allowed)
    }

    @Test func `pixabay media hosts are allowed`() {
        #expect(wallpaper(3840, 2160).hasSecureURLs)
    }
}
