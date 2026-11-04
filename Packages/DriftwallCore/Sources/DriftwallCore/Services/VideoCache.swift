import Foundation
import os

public protocol VideoDownloading: Sendable {
    /// Download to a temporary file the caller then owns.
    func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
}

public enum VideoCacheError: Error, Equatable, Sendable {
    case invalidIdentifier(String)
    case insecureURL
}

/// On-disk cache of full-resolution wallpapers with in-flight de-duplication and LRU eviction.
public actor VideoCache {
    private static let logger = Logger(subsystem: "app.driftwall", category: "cache")
    private static let maxIdentifierLength = 128
    private static let fileExtension = "mp4"

    private let directory: URL
    private let downloader: any VideoDownloading
    private var limitBytes: Int64
    private var inFlight: [String: Task<URL, any Error>] = [:]
    private var protectedIDs: Set<String> = []

    public init(directory: URL, limitBytes: Int64, downloader: any VideoDownloading) {
        self.directory = directory
        self.limitBytes = limitBytes
        self.downloader = downloader
    }

    /// Only `[A-Za-z0-9_-]` survives, so an id can never escape the cache directory.
    public static func fileName(for id: String) throws(VideoCacheError) -> String {
        let allowed = id.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45 || byte == 95
        }
        guard !id.isEmpty, id.count <= maxIdentifierLength, allowed else { throw .invalidIdentifier(id) }
        return "\(id).\(fileExtension)"
    }

    private func fileURL(for id: String) throws(VideoCacheError) -> URL {
        directory.appending(path: try Self.fileName(for: id), directoryHint: .notDirectory)
    }

    public func setLimit(bytes: Int64) {
        limitBytes = bytes
        evictIfNeeded()
    }

    /// Ids that must survive eviction and clearing (wallpapers currently on screen or scheduled).
    public func protect(_ ids: Set<String>) {
        protectedIDs = ids
    }

    public func localURL(for id: String) -> URL? {
        guard let url = try? fileURL(for: id), FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        touch(url)
        return url
    }

    public func download(_ wallpaper: Wallpaper, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let destination = try fileURL(for: wallpaper.id)
        guard wallpaper.videoURL.scheme?.lowercased() == "https" else { throw VideoCacheError.insecureURL }
        if let existing = localURL(for: wallpaper.id) {
            progress(1)
            return existing
        }
        if let pending = inFlight[wallpaper.id] {
            return try await pending.value
        }

        let downloader = downloader
        let source = wallpaper.videoURL
        let task = Task<URL, any Error> {
            let temporary = try await downloader.download(from: source, progress: progress)
            return try Self.moveIntoPlace(temporary, destination: destination)
        }
        inFlight[wallpaper.id] = task
        defer { inFlight[wallpaper.id] = nil }

        let url = try await task.value
        Self.logger.info("Cached \(wallpaper.id, privacy: .public)")
        evictIfNeeded(alsoProtecting: wallpaper.id)
        return url
    }

    private static func moveIntoPlace(_ temporary: URL, destination: URL) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try manager.removeItem(at: destination)
        }
        try manager.moveItem(at: temporary, to: destination)
        try manager.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path(percentEncoded: false))
        return destination
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path(percentEncoded: false))
    }

    private struct Entry {
        let id: String
        let url: URL
        let size: Int64
        let lastUsed: Date
    }

    private func entries() -> [Entry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return files.compactMap { url in
            guard url.pathExtension == Self.fileExtension, let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return Entry(
                id: url.deletingPathExtension().lastPathComponent,
                url: url,
                size: Int64(values.fileSize ?? 0),
                lastUsed: values.contentModificationDate ?? .distantPast
            )
        }
    }

    public func cachedIDs() -> [String] {
        entries().map(\.id).sorted()
    }

    public func totalBytes() -> Int64 {
        entries().reduce(0) { $0 + $1.size }
    }

    private func evictIfNeeded(alsoProtecting extra: String? = nil) {
        let keep = protectedIDs.union([extra].compactMap { $0 })
        var all = entries()
        var total = all.reduce(0) { $0 + $1.size }
        all.sort { $0.lastUsed < $1.lastUsed }
        for entry in all where total > limitBytes && !keep.contains(entry.id) {
            do {
                try FileManager.default.removeItem(at: entry.url)
                total -= entry.size
                Self.logger.info("Evicted \(entry.id, privacy: .public)")
            } catch {
                Self.logger.error("Evict failed \(entry.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func remove(id: String) {
        guard let url = try? fileURL(for: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Remove everything except protected wallpapers.
    public func clear() {
        for entry in entries() where !protectedIDs.contains(entry.id) {
            try? FileManager.default.removeItem(at: entry.url)
        }
    }
}
