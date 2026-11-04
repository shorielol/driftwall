import AppKit
import CryptoKit
import SwiftUI

/// Poster loader: memory cache (NSCache) → disk cache → network. Decodes off the main actor.
actor ImageLoader {
    static let shared = ImageLoader(directory: AppPaths.live.posters)

    private static let maxPixelSize: CGFloat = 1280
    private static let maxPosterBytes = 10_000_000
    private static let localRoots = [AppPaths.live.customPosters, AppPaths.live.stills, AppPaths.live.posters]
    private let memory = NSCache<NSURL, NSImage>()
    private let directory: URL
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    init(directory: URL) {
        self.directory = directory
        memory.countLimit = 400
    }

    func image(for url: URL) async -> NSImage? {
        if let cached = memory.object(forKey: url as NSURL) { return cached }
        if let pending = inFlight[url] { return await pending.value }
        let cacheFile = diskURL(for: url)
        let task = Task { await Self.load(url, cacheFile: cacheFile) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { memory.setObject(image, forKey: url as NSURL) }
        return image
    }

    private func diskURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(digest).img")
    }

    /// Runs on the concurrent pool so disk reads and decoding never serialise on the actor.
    @concurrent
    private static func load(_ url: URL, cacheFile: URL) async -> NSImage? {
        if url.isFileURL {
            let path = url.standardizedFileURL.path(percentEncoded: false)
            guard localRoots.contains(where: { path.hasPrefix($0.standardizedFileURL.path(percentEncoded: false)) }) else { return nil }
            return decode(try? Data(contentsOf: url))
        }
        if let data = try? Data(contentsOf: cacheFile), let image = decode(data) { return image }
        guard url.scheme?.lowercased() == "https" else { return nil }
        do {
            let (bytes, response) = try await URLSession.shared.bytes(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, response.expectedContentLength <= maxPosterBytes else { return nil }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxPosterBytes { return nil }
            }
            try? data.write(to: cacheFile, options: .atomic)
            return decode(data)
        } catch {
            return nil
        }
    }

    nonisolated private static func decode(_ data: Data?) -> NSImage? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func clearDisk() {
        memory.removeAllObjects()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}

/// Poster with a shimmer placeholder and a soft fade-in.
struct PosterImage: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.inkRaised)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                ShimmerPlaceholder()
            }
        }
        .clipped()
        .task(id: url) {
            image = nil
            let loaded = await ImageLoader.shared.image(for: url)
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.fade) { image = loaded }
        }
        .accessibilityHidden(true)
    }
}

struct ShimmerPlaceholder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        LinearGradient(
            colors: [.white.opacity(0.0), .white.opacity(0.07), .white.opacity(0.0)],
            startPoint: UnitPoint(x: phase, y: 0.5),
            endPoint: UnitPoint(x: phase + 0.6, y: 0.5)
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1.4 }
        }
    }
}
