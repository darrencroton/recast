import Darwin
import Foundation
import XCTest
@testable import Recast

final class PodcastServerTests: XCTestCase {

    private var tempDir: URL!
    private var server: PodcastServer?
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        server?.stop()
        session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_getServesURLDecodedEpisodePath() async throws {
        let relativePath = "Science Weekly [abc12345]/2024-01-01 - Talk [vid123].mp3"
        let fileURL = tempDir
            .appendingPathComponent("episodes", isDirectory: true)
            .appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let expectedBody = Data("decoded path".utf8)
        try expectedBody.write(to: fileURL)

        let port = try startServer()
        let encodedPath = fileURL.path.replacingOccurrences(of: tempDir.path, with: "")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let url = URL(string: "http://127.0.0.1:\(port)\(encodedPath)")!

        let (data, response) = try await session.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(data, expectedBody)
    }

    func test_headReturnsHeadersWithoutBody() async throws {
        let fileURL = tempDir
            .appendingPathComponent("episodes", isDirectory: true)
            .appendingPathComponent("sample.mp3")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let body = Data("head body".utf8)
        try body.write(to: fileURL)

        let port = try startServer()
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/episodes/sample.mp3")!)
        request.httpMethod = "HEAD"

        let (data, response) = try await session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(data.count, 0)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Length"), String(body.count))
        XCTAssertEqual(http.value(forHTTPHeaderField: "Accept-Ranges"), "bytes")
        XCTAssertNotNil(http.value(forHTTPHeaderField: "Last-Modified"))
    }

    func test_getSupportsByteRangeResponses() async throws {
        let fileURL = tempDir
            .appendingPathComponent("episodes", isDirectory: true)
            .appendingPathComponent("range.mp3")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let body = Data("range-test-body".utf8)
        try body.write(to: fileURL)

        let port = try startServer()
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/episodes/range.mp3")!)
        request.setValue("bytes=0-4", forHTTPHeaderField: "Range")

        let (data, response) = try await session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(data, body.prefix(5))
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Range"), "bytes 0-4/\(body.count)")
        XCTAssertEqual(http.value(forHTTPHeaderField: "Accept-Ranges"), "bytes")
    }

    private func startServer() throws -> UInt16 {
        let port = try availablePort()
        let server = PodcastServer(port: port, rootDir: tempDir)
        try server.start()
        self.server = server
        Thread.sleep(forTimeInterval: 0.1)
        return port
    }

    private func availablePort() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw POSIXError(.EADDRINUSE)
        }

        var boundAddress = address
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard nameResult == 0 else {
            throw POSIXError(.EINVAL)
        }

        return UInt16(bigEndian: boundAddress.sin_port)
    }
}
