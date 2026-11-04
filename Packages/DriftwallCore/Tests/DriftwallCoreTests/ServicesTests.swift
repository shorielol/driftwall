import Foundation
import Synchronization
import Testing
@testable import DriftwallCore

private func tempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "driftwall-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func sampleWallpaper(_ id: String, video: String = "https://cdn.example/v.mp4") -> Wallpaper {
    Wallpaper(
        id: id, title: id, category: "Nature", source: "mixkit",
        sourcePageURL: URL(string: "https://studio.blender.org/x-1/")!,
        previewURL: URL(string: "https://cdn.example/p.mp4")!,
        videoURL: URL(string: video)!,
        posterURL: URL(string: "https://cdn.example/p.jpg")!,
        author: "Mixkit", license: "Free", durationSeconds: 10, width: 3840, height: 2160
    )
}

/// Writes `size` bytes to a temp file per call and counts calls.
final class FakeDownloader: VideoDownloading {
    let size: Int
    let delay: Duration
    let calls = Mutex(0)

    init(size: Int, delay: Duration = .zero) {
        self.size = size
        self.delay = delay
    }

    func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        calls.withLock { $0 += 1 }
        try await Task.sleep(for: delay)
        progress(0.5)
        let file = FileManager.default.temporaryDirectory.appending(path: "dl-\(UUID().uuidString).tmp")
        try Data(repeating: 7, count: size).write(to: file)
        progress(1.0)
        return file
    }
}

@Suite("Video cache")
struct VideoCacheTests {
    @Test(arguments: ["../../etc/passwd", "a/b", "", "id with space", String(repeating: "x", count: 200)])
    func `rejects unsafe identifiers`(id: String) {
        #expect(throws: VideoCacheError.invalidIdentifier(id)) {
            _ = try VideoCache.fileName(for: id)
        }
    }

    @Test func `accepts catalog identifiers`() throws {
        #expect(try VideoCache.fileName(for: "mixkit-100417") == "mixkit-100417.mp4")
    }

    @Test func `downloads once then serves from disk`() async throws {
        let downloader = FakeDownloader(size: 1_000)
        let cache = VideoCache(directory: try tempDirectory(), limitBytes: 1_000_000, downloader: downloader)
        let wallpaper = sampleWallpaper("w1")

        #expect(await cache.localURL(for: "w1") == nil)
        let first = try await cache.download(wallpaper) { _ in }
        let second = try await cache.download(wallpaper) { _ in }

        #expect(first == second)
        #expect(FileManager.default.fileExists(atPath: first.path(percentEncoded: false)))
        #expect(downloader.calls.withLock { $0 } == 1)
        #expect(await cache.totalBytes() == 1_000)
    }

    @Test func `works in directories whose path contains spaces`() async throws {
        let spaced = try tempDirectory().appending(path: "Application Support/Driftwall Videos")
        let cache = VideoCache(directory: spaced, limitBytes: 1_000_000, downloader: FakeDownloader(size: 10))
        _ = try await cache.download(sampleWallpaper("w1")) { _ in }
        #expect(await cache.localURL(for: "w1") != nil)
        #expect(await cache.cachedIDs() == ["w1"])
    }

    @Test func `concurrent requests share one download`() async throws {
        let downloader = FakeDownloader(size: 10, delay: .milliseconds(50))
        let cache = VideoCache(directory: try tempDirectory(), limitBytes: 1_000_000, downloader: downloader)
        let wallpaper = sampleWallpaper("w1")

        async let a = cache.download(wallpaper) { _ in }
        async let b = cache.download(wallpaper) { _ in }
        let (urlA, urlB) = try await (a, b)

        #expect(urlA == urlB)
        #expect(downloader.calls.withLock { $0 } == 1)
    }

    @Test func `refuses insecure video urls`() async throws {
        let cache = VideoCache(directory: try tempDirectory(), limitBytes: 1_000, downloader: FakeDownloader(size: 1))
        await #expect(throws: VideoCacheError.insecureURL) {
            _ = try await cache.download(sampleWallpaper("w1", video: "http://cdn.example/v.mp4")) { _ in }
        }
    }

    @Test func `evicts least recently used but never protected`() async throws {
        let cache = VideoCache(directory: try tempDirectory(), limitBytes: 2_500, downloader: FakeDownloader(size: 1_000))
        for id in ["old", "mid"] {
            _ = try await cache.download(sampleWallpaper(id)) { _ in }
            try await Task.sleep(for: .milliseconds(20))
        }
        await cache.protect(["old"])
        _ = try await cache.download(sampleWallpaper("new")) { _ in }

        let ids = await cache.cachedIDs()
        #expect(Set(ids) == ["old", "new"])
        #expect(await cache.totalBytes() <= 2_500)
    }

    @Test func `clear keeps protected files`() async throws {
        let cache = VideoCache(directory: try tempDirectory(), limitBytes: 1_000_000, downloader: FakeDownloader(size: 10))
        _ = try await cache.download(sampleWallpaper("keep")) { _ in }
        _ = try await cache.download(sampleWallpaper("drop")) { _ in }
        await cache.protect(["keep"])
        await cache.clear()
        #expect(await cache.cachedIDs() == ["keep"])
    }
}

/// Scripted fetcher: returns queued responses and records the ETag it was sent.
final class FakeFetcher: CatalogFetching {
    let responses: Mutex<[Result<CatalogFetchResult, any Error>]>
    let sentETags = Mutex<[String?]>([])

    init(_ responses: [Result<CatalogFetchResult, any Error>]) {
        self.responses = Mutex(responses)
    }

    func fetch(_ url: URL, etag: String?) async throws -> CatalogFetchResult {
        sentETags.withLock { $0.append(etag) }
        let next = responses.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        guard let next else { throw URLError(.notConnectedToInternet) }
        return try next.get()
    }
}

@Suite("Catalog service")
struct CatalogServiceTests {
    let remote = URL(string: "https://driftwall.example/catalog.json")!

    private func seedURL() throws -> URL {
        try #require(Bundle.module.url(forResource: "Fixtures/catalog.json", withExtension: nil))
    }

    @Test func `falls back to bundled seed when nothing cached`() async throws {
        let service = CatalogService(remoteURL: remote, cacheDirectory: try tempDirectory(), bundledSeedURL: try seedURL(), fetcher: FakeFetcher([]))
        #expect(await service.loadCachedOrSeed().wallpapers.count == 2)
    }

    @Test func `empty catalog when no seed and no cache`() async throws {
        let service = CatalogService(remoteURL: remote, cacheDirectory: try tempDirectory(), bundledSeedURL: nil, fetcher: FakeFetcher([]))
        #expect(await service.loadCachedOrSeed() == .empty)
    }

    @Test func `refresh stores catalog and etag, then sends etag`() async throws {
        let data = try fixtureData("catalog.json")
        let fetcher = FakeFetcher([.success(.fetched(data, etag: "\"v1\"")), .success(.notModified)])
        let directory = try tempDirectory()
        let service = CatalogService(remoteURL: remote, cacheDirectory: directory, bundledSeedURL: nil, fetcher: fetcher)

        let first = await service.refresh()
        let second = await service.refresh()

        guard case .updated(let catalog) = first else { Issue.record("expected update, got \(first)"); return }
        #expect(catalog.dropId == "2026-11-23")
        #expect(second == .notModified)
        #expect(fetcher.sentETags.withLock { $0 } == [nil, "\"v1\""])
        #expect(await service.loadCachedOrSeed().dropId == "2026-11-23")
    }

    @Test func `network failure keeps last good catalog`() async throws {
        let data = try fixtureData("catalog.json")
        let fetcher = FakeFetcher([.success(.fetched(data, etag: nil)), .failure(URLError(.timedOut))])
        let service = CatalogService(remoteURL: remote, cacheDirectory: try tempDirectory(), bundledSeedURL: nil, fetcher: fetcher)

        _ = await service.refresh()
        let outcome = await service.refresh()

        guard case .failed = outcome else { Issue.record("expected failure, got \(outcome)"); return }
        #expect(await service.loadCachedOrSeed().wallpapers.count == 2)
    }

    @Test func `invalid payload is rejected and not cached`() async throws {
        let fetcher = FakeFetcher([.success(.fetched(Data("garbage".utf8), etag: "x"))])
        let directory = try tempDirectory()
        let service = CatalogService(remoteURL: remote, cacheDirectory: directory, bundledSeedURL: nil, fetcher: fetcher)

        let outcome = await service.refresh()

        guard case .failed = outcome else { Issue.record("expected failure"); return }
        #expect(await service.loadCachedOrSeed() == .empty)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "catalog.etag").path(percentEncoded: false)))
    }

    @Test func `newer bundled seed beats older cache`() async throws {
        let directory = try tempDirectory()
        let old = Catalog(generatedAt: "2020-01-01T00:00:00+00:00", dropId: "old")
        try JSONEncoder().encode(old).write(to: directory.appending(path: "catalog.json"))
        let service = CatalogService(remoteURL: remote, cacheDirectory: directory, bundledSeedURL: try seedURL(), fetcher: FakeFetcher([]))
        #expect(await service.loadCachedOrSeed().dropId == "2026-11-23")
    }
}
