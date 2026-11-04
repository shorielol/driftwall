import Foundation

/// Every on-disk location the app uses, created on first access.
nonisolated struct AppPaths: Sendable {
    let support: URL
    let caches: URL
    let videos: URL
    let posters: URL
    let customPosters: URL
    let customVideos: URL
    let stills: URL
    let logFile: URL

    static let live = AppPaths(fileManager: .default)

    init(fileManager: FileManager) {
        let supportBase = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cachesBase = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let logsBase = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0].appending(path: "Logs")
        support = supportBase.appending(path: "Driftwall")
        caches = cachesBase.appending(path: "Driftwall")
        videos = caches.appending(path: "Wallpapers")
        posters = caches.appending(path: "Posters")
        customPosters = support.appending(path: "CustomPosters")
        customVideos = support.appending(path: "CustomVideos")
        stills = support.appending(path: "Stills")
        logFile = logsBase.appending(path: "Driftwall.log")
        for directory in [support, caches, videos, posters, customPosters, customVideos, stills, logsBase] {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    var libraryFile: URL { support.appending(path: "library.json") }
    var settingsFile: URL { support.appending(path: "settings.json") }
    var assignmentsFile: URL { support.appending(path: "assignments.json") }
    var customFile: URL { support.appending(path: "custom-wallpapers.json") }
}
