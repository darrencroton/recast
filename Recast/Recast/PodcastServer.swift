import Foundation
import Network

final class PodcastServer {
    private var listener: NWListener?
    private let port: UInt16
    private let rootDir: URL
    private let queue = DispatchQueue(label: "recast.server", qos: .userInitiated)

    init(port: UInt16, rootDir: URL) {
        self.port = port
        self.rootDir = rootDir
    }

    func start() throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ServerError.invalidPort
        }
        let params = NWParameters.tcp
        listener = try NWListener(using: params, on: nwPort)
        listener?.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener?.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                AppLogger.error("Server listener error: \(err)", category: "server")
            }
        }
        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, let data, error == nil,
                  let request = String(data: data, encoding: .utf8) else {
                conn.cancel()
                return
            }
            self.handleRequest(request, on: conn)
        }
    }

    private func handleRequest(_ request: String, on conn: NWConnection) {
        // Parse method and path from "GET /path HTTP/1.1"
        let lines = request.components(separatedBy: "\r\n")
        guard let first = lines.first else { conn.cancel(); return }
        let tokens = first.split(separator: " ")
        guard tokens.count >= 2, tokens[0] == "GET" else {
            sendResponse(conn, status: "405 Method Not Allowed", body: Data())
            return
        }

        var path = String(tokens[1])
        if path == "/" { path = "/feed.xml" }

        // Security: prevent directory traversal
        let resolved = rootDir.appendingPathComponent(path).standardized
        guard resolved.path.hasPrefix(rootDir.standardized.path) else {
            sendResponse(conn, status: "403 Forbidden", body: Data())
            return
        }

        guard FileManager.default.fileExists(atPath: resolved.path),
              let handle = try? FileHandle(forReadingFrom: resolved) else {
            sendResponse(conn, status: "404 Not Found", body: Data())
            return
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: resolved.path)[.size] as? Int) ?? 0
        let contentType = mimeType(for: resolved.pathExtension)

        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(fileSize)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        let headerData = header.data(using: .utf8)!

        conn.send(content: headerData, completion: .contentProcessed { [weak self] _ in
            self?.sendFileChunks(handle: handle, on: conn)
        })
    }

    private func sendFileChunks(handle: FileHandle, on conn: NWConnection, chunkSize: Int = 65536) {
        let chunk = handle.readData(ofLength: chunkSize)
        if chunk.isEmpty {
            try? handle.close()
            conn.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                conn.cancel()
            })
            return
        }
        conn.send(content: chunk, completion: .contentProcessed { [weak self] _ in
            self?.sendFileChunks(handle: handle, on: conn)
        })
    }

    private func sendResponse(_ conn: NWConnection, status: String, body: Data) {
        let header = "HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var data = header.data(using: .utf8)!
        data.append(body)
        conn.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "xml": return "application/rss+xml; charset=utf-8"
        case "mp3": return "audio/mpeg"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }

    enum ServerError: LocalizedError {
        case invalidPort
        var errorDescription: String? { "Invalid server port." }
    }
}
