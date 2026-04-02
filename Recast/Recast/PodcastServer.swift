import Foundation
import Network

final class PodcastServer {
    private struct ByteRange {
        let start: UInt64
        let end: UInt64

        var length: UInt64 {
            end - start + 1
        }
    }

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
        guard tokens.count >= 2 else {
            sendResponse(conn, status: "405 Method Not Allowed", body: Data())
            return
        }

        let method = String(tokens[0]).uppercased()
        guard method == "GET" || method == "HEAD" else {
            sendResponse(conn, status: "405 Method Not Allowed", body: Data())
            return
        }

        var path = String(tokens[1].split(separator: "?", maxSplits: 1).first ?? "")
        if path == "/" { path = "/feed.xml" }
        let decodedPath = path.removingPercentEncoding ?? path

        var requestHeaders: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            requestHeaders[name] = value
        }

        // Security: prevent directory traversal
        let resolved = rootDir.appendingPathComponent(decodedPath).standardized
        guard resolved.path.hasPrefix(rootDir.standardized.path) else {
            sendResponse(conn, status: "403 Forbidden", body: Data())
            return
        }

        guard FileManager.default.fileExists(atPath: resolved.path),
              let handle = try? FileHandle(forReadingFrom: resolved) else {
            sendResponse(conn, status: "404 Not Found", body: Data())
            return
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        let lastModified = attributes?[.modificationDate] as? Date
        let contentType = mimeType(for: resolved.pathExtension)
        let range = parseRangeHeader(requestHeaders["range"], fileSize: fileSize)

        if requestHeaders["range"] != nil && range == nil {
            sendResponse(
                conn,
                status: "416 Range Not Satisfiable",
                headers: ["Content-Range": "bytes */\(fileSize)", "Accept-Ranges": "bytes"],
                body: Data()
            )
            try? handle.close()
            return
        }

        let responseRange = range ?? ByteRange(start: 0, end: fileSize == 0 ? 0 : fileSize - 1)
        let responseLength = range?.length ?? fileSize
        let status = range == nil ? "200 OK" : "206 Partial Content"
        let responseHeaders = responseHeaders(
            contentType: contentType,
            fileSize: fileSize,
            range: responseRange,
            contentLength: responseLength,
            status: status,
            lastModified: lastModified
        )

        if responseRange.start > 0 {
            try? handle.seek(toOffset: responseRange.start)
        }

        guard let headerData = responseHeaderData(status: status, headers: responseHeaders) else {
            sendResponse(conn, status: "500 Internal Server Error", body: Data())
            try? handle.close()
            return
        }

        conn.send(content: headerData, completion: .contentProcessed { [weak self] _ in
            guard method == "GET" else {
                try? handle.close()
                conn.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                    conn.cancel()
                })
                return
            }
            self?.sendFileChunks(handle: handle, on: conn, remainingBytes: responseLength)
        })
    }

    private func sendFileChunks(handle: FileHandle, on conn: NWConnection, remainingBytes: UInt64, chunkSize: Int = 65536) {
        guard remainingBytes > 0 else {
            try? handle.close()
            conn.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                conn.cancel()
            })
            return
        }

        let readSize = Int(min(remainingBytes, UInt64(chunkSize)))
        let chunk = handle.readData(ofLength: readSize)
        if chunk.isEmpty {
            try? handle.close()
            conn.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                conn.cancel()
            })
            return
        }
        conn.send(content: chunk, completion: .contentProcessed { [weak self] _ in
            self?.sendFileChunks(
                handle: handle,
                on: conn,
                remainingBytes: remainingBytes - UInt64(chunk.count),
                chunkSize: chunkSize
            )
        })
    }

    private func sendResponse(_ conn: NWConnection, status: String, headers: [String: String] = [:], body: Data) {
        var responseHeaders = headers
        responseHeaders["Content-Length"] = String(body.count)
        guard var data = responseHeaderData(status: status, headers: responseHeaders) else {
            conn.cancel()
            return
        }
        data.append(body)
        conn.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private func responseHeaders(
        contentType: String,
        fileSize: UInt64,
        range: ByteRange,
        contentLength: UInt64,
        status: String,
        lastModified: Date?
    ) -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": contentType,
            "Content-Length": String(contentLength),
            "Access-Control-Allow-Origin": "*",
            "Accept-Ranges": "bytes"
        ]
        if let lastModified {
            headers["Last-Modified"] = Self.httpDate(lastModified)
        }
        if status == "206 Partial Content" {
            headers["Content-Range"] = "bytes \(range.start)-\(range.end)/\(fileSize)"
        }
        return headers
    }

    private func responseHeaderData(status: String, headers: [String: String]) -> Data? {
        var header = "HTTP/1.1 \(status)\r\n"
        for key in headers.keys.sorted() {
            guard let value = headers[key] else { continue }
            header += "\(key): \(value)\r\n"
        }
        header += "Connection: close\r\n\r\n"
        return header.data(using: .utf8)
    }

    private func parseRangeHeader(_ value: String?, fileSize: UInt64) -> ByteRange? {
        guard let value, fileSize > 0 else { return nil }
        guard value.lowercased().hasPrefix("bytes=") else { return nil }

        let spec = value.dropFirst("bytes=".count)
        guard !spec.contains(",") else { return nil }

        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let lower = String(parts[0])
        let upper = String(parts[1])

        if lower.isEmpty {
            guard let suffixLength = UInt64(upper), suffixLength > 0 else { return nil }
            let length = min(suffixLength, fileSize)
            return ByteRange(start: fileSize - length, end: fileSize - 1)
        }

        guard let start = UInt64(lower), start < fileSize else { return nil }

        if upper.isEmpty {
            return ByteRange(start: start, end: fileSize - 1)
        }

        guard let end = UInt64(upper), end >= start else { return nil }
        return ByteRange(start: start, end: min(end, fileSize - 1))
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

    private static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    enum ServerError: LocalizedError {
        case invalidPort
        var errorDescription: String? { "Invalid server port." }
    }
}
