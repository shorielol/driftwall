import Foundation
import Testing
@testable import DriftwallCore

@Suite("Downloads filter")
struct DownloadFilterTests {
    private func file(_ name: String) -> URL { URL(filePath: "/Users/me/Downloads/\(name)") }

    @Test(arguments: [
        ("Eva-02 Live Wallpaper.mp4", true), ("clip.MOV", true), ("loop.m4v", true),
        ("clip.mp4.crdownload", false), ("clip.mp4.download", false), ("clip.part", false),
        (".hidden.mp4", false), ("~lock.mp4", false), ("clip.webm", false), ("photo.jpg", false),
    ])
    func finishedVideos(name: String, expected: Bool) {
        #expect(DownloadFilter.isFinishedVideo(file(name)) == expected)
    }

    @Test func `only files that appeared since the last look are new`() {
        let listing = [file("old.mp4"), file("new.mp4"), file("notes.txt"), file("half.mp4.crdownload")]
        #expect(DownloadFilter.newVideos(in: listing, known: ["old.mp4"]) == [file("new.mp4")])
    }

    @Test func `watching downloads is off by default and survives old settings files`() throws {
        #expect(AppSettings().watchDownloads == false)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(decoded.watchDownloads == false)
        let on = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"watchDownloads":true}"#.utf8))
        #expect(on.watchDownloads)
    }

    @Test func `animating the lock screen is off by default and survives old settings files`() throws {
        #expect(AppSettings().animateLockScreen == false)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(decoded.animateLockScreen == false)
        let on = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"animateLockScreen":true}"#.utf8))
        #expect(on.animateLockScreen)
    }
}
