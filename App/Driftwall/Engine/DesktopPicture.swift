import AppKit
import AVFoundation
import DriftwallCore
import ImageIO
import UniformTypeIdentifiers

/// Static fallback: a still frame of the live wallpaper becomes the system desktop picture,
/// so the lock screen, login window and Mission Control match what is playing.
enum DesktopPicture {
    private static let originalsKey = "originalDesktopPictures"
    nonisolated private static let stillTime = CMTime(seconds: 1, preferredTimescale: 600)
    nonisolated private static let jpegQuality = 0.9

    /// Extract (once) a full-resolution still from a local video.
    @concurrent
    static func still(for videoURL: URL, id: String, directory: URL) async throws -> URL {
        let destination = directory.appending(path: "\(try VideoCache.fileName(for: id)).jpg")
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) { return destination }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        let (image, _) = try await generator.image(at: stillTime)
        try writeJPEG(image, to: destination)
        return destination
    }

    nonisolated private static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    static func apply(_ still: URL, to screen: NSScreen) {
        rememberOriginal(for: screen)
        do {
            try NSWorkspace.shared.setDesktopImageURL(still, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ])
        } catch {
            AppLog.error("Could not set desktop picture: \(error.localizedDescription)")
        }
    }

    /// Save the user's own desktop picture the first time we replace it.
    private static func rememberOriginal(for screen: NSScreen) {
        var originals = UserDefaults.standard.dictionary(forKey: originalsKey) as? [String: String] ?? [:]
        let key = screen.displayKey.rawValue
        guard originals[key] == nil, let current = NSWorkspace.shared.desktopImageURL(for: screen) else { return }
        guard !current.path(percentEncoded: false).hasPrefix(AppPaths.live.stills.path(percentEncoded: false)) else { return }
        originals[key] = current.absoluteString
        UserDefaults.standard.set(originals, forKey: originalsKey)
    }

    static func restoreOriginals() {
        let originals = UserDefaults.standard.dictionary(forKey: originalsKey) as? [String: String] ?? [:]
        for screen in NSScreen.screens {
            guard let raw = originals[screen.displayKey.rawValue], let url = URL(string: raw),
                  FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
        UserDefaults.standard.removeObject(forKey: originalsKey)
    }
}
