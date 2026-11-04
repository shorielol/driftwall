import Foundation
import os

/// Small Codable persistence: atomic writes, corrupt files read as nil (and are logged).
public struct JSONFileStore<Value: Codable & Sendable>: Sendable {
    public let url: URL
    private static var logger: Logger { Logger(subsystem: "app.driftwall", category: "store") }

    public init(url: URL) {
        self.url = url
    }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            Self.logger.error("Could not decode \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: [.atomic])
    }
}
