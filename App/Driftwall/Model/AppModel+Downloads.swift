import DriftwallCore
import Foundation

/// Opt-in: offer videos that land in ~/Downloads as wallpapers. Imports stay on this Mac.
extension AppModel {
    func setWatchingDownloads(_ isOn: Bool) {
        guard isOn else {
            downloadsWatcher?.stop()
            downloadsWatcher = nil
            downloadOffer = nil
            return
        }
        let watcher = downloadsWatcher ?? DownloadsWatcher { [weak self] url in self?.downloadOffer = url }
        downloadsWatcher = watcher
        if !watcher.start() {
            show("Driftwall can't read your Downloads folder. Allow it in System Settings → Privacy & Security → Files and Folders.", isError: true)
        }
    }

    func useOfferedDownload() {
        guard let url = downloadOffer else { return }
        downloadOffer = nil
        importCustom(from: [url]) { [weak self] imported in
            if let wallpaper = imported.first { self?.apply(wallpaper) }
        }
    }

    func importOfferedDownload() {
        guard let url = downloadOffer else { return }
        downloadOffer = nil
        importCustom(from: [url])
    }

    func dismissDownloadOffer() {
        downloadOffer = nil
    }
}
