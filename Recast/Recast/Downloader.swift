import Foundation

enum DownloaderError: LocalizedError {
    case dependencyMissing(String)
    case processError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .dependencyMissing(let name): return "\(name) is not available."
        case .processError(let msg): return msg
        case .parseError: return "Failed to parse yt-dlp output."
        }
    }
}

actor Downloader {
    // MARK: - Dependency resolution

    func ytDlpPath() -> String? {
        let bundled = Paths.ytDlpInBin
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }
        return whichPath("yt-dlp")
    }

    func ffmpegPath() -> String? {
        let bundled = Paths.ffmpegInBin
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }
        return whichPath("ffmpeg")
    }

    var hasYtDlp: Bool { ytDlpPath() != nil }
    var hasFfmpeg: Bool { ffmpegPath() != nil }

    private func whichPath(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (out?.isEmpty == false) ? out : nil
    }

    // MARK: - Install dependencies

    func installYtDlp() async throws {
        let url = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
        let dest = Paths.ytDlpInBin
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: tempURL, to: dest)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
    }

    func installFfmpeg() async throws {
        let url = URL(string: "https://evermeet.cx/ffmpeg/get/zip")!
        let (zipURL, _) = try await URLSession.shared.download(from: url)
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        // Unzip
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", zipURL.path, "-d", tmpDir.path]
        unzip.standardOutput = FileHandle.nullDevice
        unzip.standardError = FileHandle.nullDevice
        try unzip.run()
        unzip.waitUntilExit()
        let extracted = tmpDir.appendingPathComponent("ffmpeg")
        guard FileManager.default.fileExists(atPath: extracted.path) else {
            throw DownloaderError.processError("ffmpeg binary not found in downloaded archive.")
        }
        let dest = Paths.ffmpegInBin
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: extracted, to: dest)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        try? fm.removeItem(at: tmpDir)
    }

    // MARK: - Channel operations

    func resolveChannelName(url: String) async throws -> String {
        guard let ytdlp = ytDlpPath() else { throw DownloaderError.dependencyMissing("yt-dlp") }
        let output = try await runProcess(
            ytdlp,
            arguments: ["--flat-playlist", "--playlist-end", "1",
                        "--print", "%(channel)s", "--no-warnings", url]
        )
        let name = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "NA" {
            // Fallback: try playlist title
            let output2 = try await runProcess(
                ytdlp,
                arguments: ["--flat-playlist", "--playlist-end", "1",
                            "--print", "%(playlist_title)s", "--no-warnings", url]
            )
            let fallback = output2.trimmingCharacters(in: .whitespacesAndNewlines)
            return (fallback.isEmpty || fallback == "NA") ? "Unknown Channel" : fallback
        }
        return name
    }

    struct VideoInfo {
        let videoID: String
        let title: String
        let publishDate: Date
        let durationSeconds: Int
    }

    func listVideos(channelURL: String, max: Int = 50) async throws -> [VideoInfo] {
        guard let ytdlp = ytDlpPath() else { throw DownloaderError.dependencyMissing("yt-dlp") }
        let output = try await runProcess(
            ytdlp,
            arguments: [
                "--no-warnings",
                "--print", "%(id)s\t%(title)s\t%(upload_date)s\t%(timestamp)s\t%(release_timestamp)s\t%(duration)s",
                "--playlist-end", String(max),
                channelURL,
            ]
        )
        var results: [VideoInfo] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 5).map(String.init)
            guard parts.count >= 6 else { continue }
            results.append(VideoInfo(
                videoID: parts[0],
                title: parts[1],
                publishDate: Self.publishedDate(
                    uploadDate: parts[2],
                    timestamp: parts[3],
                    releaseTimestamp: parts[4]
                ),
                durationSeconds: Int(parts[5]) ?? 0
            ))
        }
        return results
    }

    func downloadAudio(
        episode: Episode,
        to episodesDir: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        guard let ytdlp = ytDlpPath() else { throw DownloaderError.dependencyMissing("yt-dlp") }

        let fileName = episode.suggestedFileName
        let dest = episodesDir.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: dest.path) { return fileName }

        let fileStem = String(fileName.dropLast(4))
        let templateName = "\(fileStem).%(ext)s"
        var args = [
            "--extract-audio",
            "--audio-format", "mp3",
            "--audio-quality", "3",
            "--embed-metadata",
            "--output", episodesDir.appendingPathComponent(templateName).path,
            "--no-playlist", "--no-warnings", "--newline",
        ]
        if let ffmpeg = ffmpegPath() {
            args += ["--ffmpeg-location", ffmpeg]
        }
        args.append("https://www.youtube.com/watch?v=\(episode.videoID)")

        if let progress {
            try await runProcessWithProgress(ytdlp, arguments: args, onProgress: progress)
        } else {
            _ = try await runProcess(ytdlp, arguments: args)
        }

        guard FileManager.default.fileExists(atPath: dest.path) else {
            throw DownloaderError.processError("MP3 file was not created for \(episode.videoID).")
        }
        return fileName
    }

    static func publishedDate(uploadDate: String, timestamp: String, releaseTimestamp: String) -> Date {
        if let uploadDate = parseUploadDate(uploadDate) {
            return uploadDate
        }
        if let timestampDate = parseUnixTimestamp(timestamp) {
            return timestampDate
        }
        if let releaseDate = parseUnixTimestamp(releaseTimestamp) {
            return releaseDate
        }
        return .now
    }

    private static func parseUploadDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "NA" else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in ["yyyyMMdd", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    private static func parseUnixTimestamp(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = TimeInterval(trimmed), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    // MARK: - Process execution

    private func runProcess(_ path: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    process.waitUntilExit()
                    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outData, encoding: .utf8) ?? ""
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                        let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: DownloaderError.processError(errMsg))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runProcessWithProgress(
        _ path: String,
        arguments: [String],
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                var stderrText = ""
                let progressPattern = try? NSRegularExpression(pattern: #"(\d+\.?\d*)%"#)

                stderr.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    stderrText += text
                    // Parse download progress percentages from yt-dlp output
                    if let progressPattern {
                        for line in text.components(separatedBy: .newlines) {
                            let range = NSRange(line.startIndex..., in: line)
                            if let match = progressPattern.firstMatch(in: line, range: range),
                               let numRange = Range(match.range(at: 1), in: line) {
                                if let pct = Double(line[numRange]) {
                                    onProgress(min(pct / 100.0, 1.0))
                                }
                            }
                        }
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    stderr.fileHandleForReading.readabilityHandler = nil

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: ())
                    } else {
                        let msg = stderrText.isEmpty ? "Unknown error" : stderrText
                        continuation.resume(throwing: DownloaderError.processError(msg))
                    }
                } catch {
                    stderr.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
