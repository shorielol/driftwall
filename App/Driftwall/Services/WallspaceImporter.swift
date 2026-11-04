import Foundation

/// Finds wallpapers the user already downloaded with Wallspace on this Mac, so they can be
/// imported locally. Nothing here is uploaded or added to the public catalog.
enum WallspaceImporter {
    struct Candidate: Identifiable, Hashable {
        let id: String
        let file: URL
        let title: String
        let category: String
    }

    private static let suite = "wallspace.app"
    private static let modelKeys = ["likedWallpapersModels", "recentsWallpapersModels"]
    static let note = "Imported from your Wallspace downloads."

    static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Wallspace/Wallpapers")
    }

    /// Titles Wallspace stored for each downloaded key, read from its preferences.
    private static func knownTitles() -> [String: (title: String, category: String)] {
        guard let defaults = UserDefaults(suiteName: suite) else { return [:] }
        var titles: [String: (String, String)] = [:]
        for key in modelKeys {
            guard let data = defaults.data(forKey: key),
                  let models = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            for model in models {
                guard let id = (model["key"] as? NSNumber)?.stringValue ?? model["key"] as? String,
                      let title = model["title"] as? String else { continue }
                titles[id] = (title, model["category"] as? String ?? "Imported")
            }
        }
        return titles
    }

    static func discover() -> [Candidate] {
        let files = (try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        let titles = knownTitles()
        return files
            .filter { ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) }
            .map { file in
                let key = file.deletingPathExtension().lastPathComponent
                let known = titles[key]
                return Candidate(id: key, file: file, title: known?.title ?? "Wallspace \(key.suffix(4))", category: known?.category ?? "Imported")
            }
            .sorted { $0.title < $1.title }
    }
}
