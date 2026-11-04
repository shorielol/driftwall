import Foundation
import Testing
@testable import DriftwallCore

@Suite("Library state")
struct LibraryStateTests {
    @Test func `toggle like adds then removes, newest first`() {
        let state = LibraryState().togglingLike("a").togglingLike("b")
        #expect(state.liked == ["b", "a"])
        #expect(state.togglingLike("b").liked == ["a"])
        #expect(state.isLiked("a"))
    }

    @Test func `recents dedupe, move to front, cap at limit`() {
        var state = LibraryState()
        for index in 0..<(LibraryState.recentsLimit + 5) {
            state = state.recordingRecent("w\(index)")
        }
        state = state.recordingRecent("w10")
        #expect(state.recents.count == LibraryState.recentsLimit)
        #expect(state.recents.first == "w10")
        #expect(state.recents.filter { $0 == "w10" }.count == 1)
    }

    @Test func `my list toggles`() {
        let state = LibraryState().togglingMyList("x")
        #expect(state.isInMyList("x"))
        #expect(!state.togglingMyList("x").isInMyList("x"))
    }

    @Test func `playlists upsert and remove`() {
        let playlist = Playlist(name: "One", wallpaperIDs: ["a"], interval: 600)
        let added = LibraryState().upserting(playlist)
        let renamed = added.upserting(playlist.with(name: "Renamed"))
        #expect(renamed.playlists.count == 1)
        #expect(renamed.playlists.first?.name == "Renamed")
        #expect(renamed.removingPlaylist(id: playlist.id).playlists.isEmpty)
    }

    @Test func `marks drop seen`() {
        #expect(LibraryState().markingDropSeen("2026-11-23").lastSeenDropID == "2026-11-23")
    }

    @Test func `original value is never mutated`() {
        let original = LibraryState()
        _ = original.togglingLike("a").recordingRecent("b").togglingMyList("c")
        #expect(original == LibraryState())
    }

    @Test func `decodes older payload missing new fields`() throws {
        let json = #"{"liked":["a"]}"#
        let state = try JSONDecoder().decode(LibraryState.self, from: Data(json.utf8))
        #expect(state.liked == ["a"])
        #expect(state.recents.isEmpty && state.playlists.isEmpty)
    }
}

@Suite("Settings")
struct SettingsTests {
    @Test func `defaults are sensible`() {
        let settings = AppSettings()
        #expect(settings.playbackRate == 1.0)
        #expect(settings.autoPause.onFullscreen)
        #expect(settings.cacheLimitGB == 10)
        #expect(settings.rotateLatestDrop == false)
    }

    @Test func `playback rate and cache limit are clamped`() {
        let settings = AppSettings(playbackRate: 9, cacheLimitGB: -3)
        #expect(settings.playbackRate == AppSettings.playbackRateRange.upperBound)
        #expect(settings.cacheLimitGB == AppSettings.cacheLimitRange.lowerBound)
    }

    @Test func `decoding tolerates missing keys`() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"playbackRate":0.75}"#.utf8))
        #expect(settings.playbackRate == 0.75)
        #expect(settings.launchAtLogin == AppSettings().launchAtLogin)
    }

    @Test func `insecure catalog url override is ignored`() {
        let settings = AppSettings(catalogURLOverride: "http://evil.example/catalog.json")
        #expect(settings.effectiveCatalogURL(default: URL(string: "https://a.example/c.json")!).absoluteString == "https://a.example/c.json")
    }

    @Test func `local catalog url override allowed for development`() {
        let settings = AppSettings(catalogURLOverride: "http://localhost:8000/catalog.json")
        #expect(settings.effectiveCatalogURL(default: URL(string: "https://a.example/c.json")!).host() == "localhost")
    }
}

@Suite("JSON file store")
struct JSONFileStoreTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "driftwall-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func `saves and loads atomically`() throws {
        let store = JSONFileStore<LibraryState>(url: directory.appending(path: "library.json"))
        #expect(store.load() == nil)
        let state = LibraryState().togglingLike("a")
        try store.save(state)
        #expect(store.load() == state)
    }

    @Test func `corrupt file loads as nil instead of crashing`() throws {
        let url = directory.appending(path: "bad.json")
        try Data("{nope".utf8).write(to: url)
        #expect(JSONFileStore<LibraryState>(url: url).load() == nil)
    }
}
