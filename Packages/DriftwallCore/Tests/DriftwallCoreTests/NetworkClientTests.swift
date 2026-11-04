import Foundation
import Testing
@testable import DriftwallCore

/// Serves canned responses keyed by URL path; records request headers.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    nonisolated(unsafe) static var stubs: [String: Stub] = [:]
    nonisolated(unsafe) static var lastIfNoneMatch: [String: String] = [:]
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path() ?? ""
        let stub = Self.lock.withLock {
            Self.lastIfNoneMatch[path] = request.value(forHTTPHeaderField: "If-None-Match")
            return Self.stubs[path]
        }
        guard let stub, let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session(_ stubs: [String: Stub]) -> URLSession {
        lock.withLock { self.stubs.merge(stubs) { _, new in new } }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

@Suite("URLSession clients", .serialized)
struct NetworkClientTests {
    @Test func `catalog fetcher returns body and etag on 200`() async throws {
        let session = StubURLProtocol.session(["/ok.json": .init(status: 200, headers: ["ETag": "\"abc\""], body: Data("{}".utf8))])
        let result = try await URLSessionCatalogFetcher(session: session).fetch(URL(string: "https://x.example/ok.json")!, etag: nil)
        #expect(result == .fetched(Data("{}".utf8), etag: "\"abc\""))
    }

    @Test func `catalog fetcher sends if none match and maps 304`() async throws {
        let session = StubURLProtocol.session(["/same.json": .init(status: 304, headers: [:], body: Data())])
        let result = try await URLSessionCatalogFetcher(session: session).fetch(URL(string: "https://x.example/same.json")!, etag: "\"v1\"")
        #expect(result == .notModified)
        #expect(StubURLProtocol.lock.withLock { StubURLProtocol.lastIfNoneMatch["/same.json"] } == "\"v1\"")
    }

    @Test func `catalog fetcher throws on server error`() async throws {
        let session = StubURLProtocol.session(["/err.json": .init(status: 500, headers: [:], body: Data())])
        await #expect(throws: NetworkError.badStatus(500)) {
            _ = try await URLSessionCatalogFetcher(session: session).fetch(URL(string: "https://x.example/err.json")!, etag: nil)
        }
    }

    @Test func `video downloader writes file and reports completion`() async throws {
        let body = Data(repeating: 1, count: 4_096)
        let session = StubURLProtocol.session(["/v.mp4": .init(status: 200, headers: ["Content-Length": "4096"], body: body)])
        let finished = ProgressRecorder()
        let url = try await URLSessionVideoDownloader(session: session).download(from: URL(string: "https://x.example/v.mp4")!) {
            finished.record($0)
        }
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Data(contentsOf: url) == body)
        #expect(finished.last == 1)
    }

    @Test func `video downloader rejects 404`() async throws {
        let session = StubURLProtocol.session(["/missing.mp4": .init(status: 404, headers: [:], body: Data())])
        await #expect(throws: NetworkError.badStatus(404)) {
            _ = try await URLSessionVideoDownloader(session: session).download(from: URL(string: "https://x.example/missing.mp4")!) { _ in }
        }
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []

    func record(_ value: Double) { lock.withLock { values.append(value) } }
    var last: Double? { lock.withLock { values.last } }
}

@Suite("Download limits", .serialized)
struct DownloadLimitTests {
    @Test func `catalog larger than the cap is refused`() async throws {
        let body = Data(repeating: 32, count: 2_048)
        let session = StubURLProtocol.session(["/big.json": .init(status: 200, headers: [:], body: body)])
        await #expect(throws: NetworkError.tooLarge) {
            _ = try await URLSessionCatalogFetcher(session: session, maxBytes: 1_024).fetch(URL(string: "https://x.example/big.json")!, etag: nil)
        }
    }

    @Test func `video larger than the cap is refused`() async throws {
        let body = Data(repeating: 1, count: 8_192)
        let session = StubURLProtocol.session(["/huge.mp4": .init(status: 200, headers: ["Content-Length": "8192"], body: body)])
        await #expect(throws: NetworkError.tooLarge) {
            _ = try await URLSessionVideoDownloader(session: session, maxBytes: 1_000).download(from: URL(string: "https://x.example/huge.mp4")!) { _ in }
        }
    }
}
