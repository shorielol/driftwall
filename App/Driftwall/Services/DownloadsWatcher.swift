import DriftwallCore
import Foundation

/// Watches ~/Downloads and reports videos that finish downloading after watching starts.
///
/// Files already there when watching starts are ignored, so turning the feature on never floods
/// the user with offers. A file counts as finished once its size holds still between two looks.
final class DownloadsWatcher {
    private static let settleDelay: Duration = .seconds(2)

    private let folder: URL
    private let onNewVideo: (URL) -> Void
    private var source: (any DispatchSourceFileSystemObject)?
    private var known: Set<String> = []
    private var pending: Task<Void, Never>?

    init(folder: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads"),
         onNewVideo: @escaping (URL) -> Void) {
        self.folder = folder
        self.onNewVideo = onNewVideo
    }

    /// Returns false when the folder can't be opened (for example, access was denied).
    @discardableResult
    func start() -> Bool {
        guard source == nil else { return true }
        let descriptor = open(folder.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else {
            AppLog.error("Can't watch \(folder.path(percentEncoded: false)) (errno \(errno))")
            return false
        }
        known = Set(listing().map(\.lastPathComponent))
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.folderChanged() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        return true
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
    }

    private func listing() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        )) ?? []
    }

    private func folderChanged() {
        // Browsers touch the folder many times per download; look once things settle.
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            await self?.reportFinishedVideos()
        }
    }

    private func reportFinishedVideos() async {
        let fresh = DownloadFilter.newVideos(in: listing(), known: known)
        guard !fresh.isEmpty else { return }
        let before = fresh.map(Self.size)
        try? await Task.sleep(for: Self.settleDelay)
        guard !Task.isCancelled else { return }
        for (url, size) in zip(fresh, before) where size > 0 && Self.size(url) == size {
            known.insert(url.lastPathComponent)
            onNewVideo(url)
        }
    }

    private static func size(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
