import AVFoundation
import DriftwallCore
import Foundation

/// Imports a user's own video as a wallpaper: copies it into the cache and builds a poster.
enum CustomImporter {
    nonisolated enum ImportError: LocalizedError {
        case noVideoTrack
        case unreadable

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: "That file doesn't contain a playable video track."
            case .unreadable: "That video couldn't be read. Try an .mp4 or .mov file."
            }
        }
    }

    @concurrent
    static func importVideo(
        at source: URL, videosDirectory: URL, postersDirectory: URL,
        title overrideTitle: String? = nil, category: String = "Custom", note: String = "Imported from your Mac."
    ) async throws -> Wallpaper {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ImportError.noVideoTrack }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let oriented = naturalSize.applying(transform)
        let duration = try await asset.load(.duration).seconds

        let id = "custom-\(UUID().uuidString.lowercased())"
        let destination = videosDirectory.appending(path: try VideoCache.fileName(for: id))
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw ImportError.unreadable
        }
        let poster = try await DesktopPicture.still(for: destination, id: id, directory: postersDirectory)
        let title = overrideTitle ?? source.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        return Wallpaper(
            id: id,
            title: title.isEmpty ? "My wallpaper" : title,
            description: note,
            category: category,
            source: "custom",
            sourcePageURL: destination,
            previewURL: destination,
            videoURL: destination,
            posterURL: poster,
            author: "You",
            license: "Your own video",
            durationSeconds: Int(duration.isFinite ? duration.rounded() : 0),
            width: Int(abs(oriented.width)),
            height: Int(abs(oriented.height)),
            addedInDrop: ""
        )
    }
}
