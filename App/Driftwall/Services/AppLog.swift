import Foundation
import os

/// os.Logger for Console plus a small rolling text log the Settings screen can show.
nonisolated enum AppLog {
    private static let logger = Logger(subsystem: "app.driftwall", category: "app")
    private static let writer = LogFileWriter(url: AppPaths.live.logFile)

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        Task { await writer.append("INFO  \(message)") }
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        Task { await writer.append("ERROR \(message)") }
    }

    static func tail(lines: Int = 300) async -> String {
        await writer.tail(lines: lines)
    }
}

actor LogFileWriter {
    private static let maxBytes = 1_000_000
    private let url: URL
    private let stamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    init(url: URL) {
        self.url = url
    }

    func append(_ line: String) {
        let text = "\(stamp.string(from: Date())) \(line)\n"
        let manager = FileManager.default
        if let size = (try? manager.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.size] as? Int, size > Self.maxBytes {
            try? manager.removeItem(at: url)
        }
        if !manager.fileExists(atPath: url.path(percentEncoded: false)) {
            manager.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
    }

    func tail(lines: Int) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "No log entries yet." }
        return text.split(separator: "\n", omittingEmptySubsequences: true).suffix(lines).joined(separator: "\n")
    }
}
