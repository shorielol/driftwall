import Foundation
import os

public enum CatalogFetchResult: Sendable, Equatable {
    case fetched(Data, etag: String?)
    case notModified
}

public protocol CatalogFetching: Sendable {
    func fetch(_ url: URL, etag: String?) async throws -> CatalogFetchResult
}

public enum CatalogRefreshOutcome: Sendable, Equatable {
    case updated(Catalog)
    case notModified
    case failed(String)
}

/// Keeps the newest valid catalog on disk. A bad download never replaces the last good one.
public actor CatalogService {
    private static let logger = Logger(subsystem: "app.driftwall", category: "catalog")

    private let remoteURL: URL
    private let cacheFile: URL
    private let etagFile: URL
    private let bundledSeedURL: URL?
    private let fetcher: any CatalogFetching

    public init(remoteURL: URL, cacheDirectory: URL, bundledSeedURL: URL?, fetcher: any CatalogFetching) {
        self.remoteURL = remoteURL
        self.cacheFile = cacheDirectory.appending(path: "catalog.json")
        self.etagFile = cacheDirectory.appending(path: "catalog.etag")
        self.bundledSeedURL = bundledSeedURL
        self.fetcher = fetcher
    }

    private static func decode(at url: URL?) -> Catalog? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try Catalog.decodeValidated(from: data)
        } catch {
            logger.error("Ignoring invalid catalog at \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Newest of (cached download, bundled seed), or an empty catalog.
    public func loadCachedOrSeed() -> Catalog {
        let candidates = [Self.decode(at: cacheFile), Self.decode(at: bundledSeedURL)].compactMap { $0 }
        return candidates.max { $0.generatedAt < $1.generatedAt } ?? .empty
    }

    public func refresh() async -> CatalogRefreshOutcome {
        let hasCache = FileManager.default.fileExists(atPath: cacheFile.path(percentEncoded: false))
        let etag = hasCache ? (try? String(contentsOf: etagFile, encoding: .utf8)) : nil

        let result: CatalogFetchResult
        do {
            result = try await fetcher.fetch(remoteURL, etag: etag)
        } catch {
            Self.logger.notice("Catalog refresh failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }

        switch result {
        case .notModified:
            return .notModified
        case .fetched(let data, let newETag):
            return store(data, etag: newETag)
        }
    }

    private func store(_ data: Data, etag: String?) -> CatalogRefreshOutcome {
        let catalog: Catalog
        do {
            catalog = try Catalog.decodeValidated(from: data)
        } catch {
            Self.logger.error("Rejected remote catalog: \(String(describing: error), privacy: .public)")
            return .failed("The wallpaper catalog could not be read.")
        }
        do {
            try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cacheFile, options: .atomic)
            if let etag {
                try Data(etag.utf8).write(to: etagFile, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: etagFile)
            }
        } catch {
            Self.logger.error("Could not cache catalog: \(error.localizedDescription, privacy: .public)")
        }
        Self.logger.info("Catalog updated to drop \(catalog.dropId, privacy: .public) with \(catalog.wallpapers.count) wallpapers")
        return .updated(catalog)
    }
}
