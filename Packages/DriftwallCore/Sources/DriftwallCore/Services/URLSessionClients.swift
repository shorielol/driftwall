import Foundation
import Synchronization

public enum NetworkError: Error, Equatable, Sendable {
    case badStatus(Int)
    case tooLarge
}

/// Conditional GET for the catalog (ETag / If-None-Match), streamed with a hard size cap.
public struct URLSessionCatalogFetcher: CatalogFetching {
    public static let defaultMaxBytes = 20_000_000
    private let session: URLSession
    private let maxBytes: Int

    public init(session: URLSession = .shared, maxBytes: Int = Self.defaultMaxBytes) {
        self.session = session
        self.maxBytes = maxBytes
    }

    public func fetch(_ url: URL, etag: String?) async throws -> CatalogFetchResult {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (bytes, response) = try await session.bytes(for: request)
        let http = response as? HTTPURLResponse
        switch http?.statusCode ?? 0 {
        case 304:
            return .notModified
        case 200:
            if response.expectedContentLength > Int64(maxBytes) { throw NetworkError.tooLarge }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes { throw NetworkError.tooLarge }
            }
            return .fetched(data, etag: http?.value(forHTTPHeaderField: "ETag"))
        case let status:
            throw NetworkError.badStatus(status)
        }
    }
}

/// Full-resolution video download with progress and a hard size cap.
public struct URLSessionVideoDownloader: VideoDownloading {
    public static let defaultMaxBytes: Int64 = 1_500_000_000
    private let session: URLSession
    private let maxBytes: Int64

    public init(session: URLSession = .shared, maxBytes: Int64 = Self.defaultMaxBytes) {
        self.session = session
        self.maxBytes = maxBytes
    }

    public func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = DownloadProgressDelegate(maxBytes: maxBytes, onProgress: progress)
        let temporary: URL
        let response: URLResponse
        do {
            (temporary, response) = try await session.download(from: url, delegate: delegate)
        } catch {
            if delegate.exceededLimit { throw NetworkError.tooLarge }
            throw error
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let size = (try? FileManager.default.attributesOfItem(atPath: temporary.path(percentEncoded: false))[.size] as? Int64) ?? 0
        guard (200..<300).contains(status), size <= maxBytes else {
            try? FileManager.default.removeItem(at: temporary)
            throw size > maxBytes ? NetworkError.tooLarge : NetworkError.badStatus(status)
        }
        // The system may reclaim its temp file; move to our own temp name immediately.
        let owned = FileManager.default.temporaryDirectory.appending(path: "driftwall-\(UUID().uuidString).mp4")
        try FileManager.default.moveItem(at: temporary, to: owned)
        progress(1)
        return owned
    }
}

final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    private let maxBytes: Int64
    private let onProgress: @Sendable (Double) -> Void
    private let exceeded = Mutex(false)

    init(maxBytes: Int64, onProgress: @escaping @Sendable (Double) -> Void) {
        self.maxBytes = maxBytes
        self.onProgress = onProgress
    }

    var exceededLimit: Bool { exceeded.withLock { $0 } }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesWritten > maxBytes || totalBytesExpectedToWrite > maxBytes {
            exceeded.withLock { $0 = true }
            downloadTask.cancel()
            return
        }
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Required by the protocol; the async API hands the file back to the caller.
    }
}
