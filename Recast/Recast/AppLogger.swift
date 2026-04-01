import Foundation
import OSLog

enum AppLogger {
    private static let logger = Logger(subsystem: "com.recast.app", category: "app")
    private static let writeQueue = DispatchQueue(label: "com.recast.app.logger")

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static var logFileURL: URL {
        Paths.logFile
    }

    static func info(_ message: String, category: String = "app") {
        logger.info("\(message, privacy: .public)")
        append(level: "INFO", category: category, message: message)
    }

    static func warning(_ message: String, category: String = "app") {
        logger.warning("\(message, privacy: .public)")
        append(level: "WARN", category: category, message: message)
    }

    static func error(_ message: String, category: String = "app") {
        logger.error("\(message, privacy: .public)")
        append(level: "ERROR", category: category, message: message)
    }

    private static func append(level: String, category: String, message: String) {
        let line = "[\(timestampFormatter.string(from: Date()))] [\(level)] [\(category)] \(message)\n"
        writeQueue.async {
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: logFileURL.path),
               let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: logFileURL, options: .atomic)
            }
        }
    }
}
