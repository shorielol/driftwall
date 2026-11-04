import Foundation

/// Decides which files in a watched Downloads folder are finished videos worth offering to import.
public enum DownloadFilter {
    public static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    /// Browsers write to these while a download is in progress.
    static let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial", "tmp", "opdownload"]

    public static func isFinishedVideo(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard !name.hasPrefix("."), !name.hasPrefix("~") else { return false }
        let ext = url.pathExtension.lowercased()
        return videoExtensions.contains(ext) && !partialExtensions.contains(ext)
    }

    /// Finished videos in `listing` that were not present in `known`, in listing order.
    public static func newVideos(in listing: [URL], known: Set<String>) -> [URL] {
        listing.filter { isFinishedVideo($0) && !known.contains($0.lastPathComponent) }
    }
}
