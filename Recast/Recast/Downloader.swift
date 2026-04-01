import Foundation

enum DownloaderError: LocalizedError {
    case dependencyMissing(String)
    case processError(String)
    case parseError
    case cancelled

    var errorDescription: String? {
        switch self {
        case .dependencyMissing(let name): return "\(name) is not available."
        case .processError(let msg): return msg
        case .parseError: return "Failed to parse yt-dlp output."
        case .cancelled: return "Download cancelled."
        }
    }
}

actor Downloader {
    static let downloadPhaseWeight = 0.15

    struct ProcessOutput {
        let stdout: String
        let stderr: String
        let terminationStatus: Int32
    }

    private struct ProgressParser {
        let durationSeconds: Int
        private let progressPattern = try? NSRegularExpression(pattern: #"(\d+\.?\d*)%"#)
        private let conversionPattern = try? NSRegularExpression(pattern: #"time=(\d+):(\d+):(\d+(?:\.\d+)?)"#)
        private var bufferedLine = ""
        private var latestDownloadProgress = 0.0
        private var latestConversionProgress = 0.0
        private var hasSeenConversionProgress = false

        init(durationSeconds: Int) {
            self.durationSeconds = durationSeconds
        }

        mutating func ingest(_ text: String) -> [Double] {
            bufferedLine += text
            let lines = bufferedLine.components(separatedBy: .newlines)
            bufferedLine = lines.last ?? ""

            return lines.dropLast().compactMap { line in
                combinedProgress(for: line)
            }
        }

        mutating func finish() -> [Double] {
            defer { bufferedLine = "" }
            guard !bufferedLine.isEmpty else { return [] }
            return combinedProgress(for: bufferedLine).map { [$0] } ?? []
        }

        private mutating func combinedProgress(for line: String) -> Double? {
            if let conversionProgress = conversionProgress(for: line) {
                hasSeenConversionProgress = true
                latestConversionProgress = max(latestConversionProgress, conversionProgress)
                return Downloader.displayProgress(
                    downloadProgress: latestDownloadProgress,
                    conversionProgress: latestConversionProgress
                )
            }

            guard let downloadProgress = downloadProgress(for: line) else { return nil }
            latestDownloadProgress = max(latestDownloadProgress, downloadProgress)
            guard !hasSeenConversionProgress else { return nil }
            return Downloader.displayProgress(
                downloadProgress: latestDownloadProgress,
                conversionProgress: nil
            )
        }

        private func downloadProgress(for line: String) -> Double? {
            Downloader.parseDownloadProgress(from: line, with: progressPattern)
        }

        private func conversionProgress(for line: String) -> Double? {
            Downloader.parseConversionProgress(
                from: line,
                durationSeconds: durationSeconds,
                with: conversionPattern
            )
        }
    }

    private var runningDownloadProcesses: [String: Process] = [:]
    private var cancelledDownloadIDs: Set<String> = []

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
        let processOutput = try await runProcessCapturingOutput(
            ytdlp,
            arguments: [
                "--ignore-errors",
                "--no-warnings",
                "--print", "%(id)s\t%(title)s\t%(upload_date)s\t%(timestamp)s\t%(release_timestamp)s\t%(duration)s",
                "--playlist-end", String(max),
                channelURL,
            ]
        )

        let results = Self.parseVideoListOutput(processOutput.stdout)

        if processOutput.terminationStatus != 0 {
            let trimmedError = processOutput.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if results.isEmpty {
                let message = trimmedError.isEmpty ? "yt-dlp failed without output." : trimmedError
                throw DownloaderError.processError(message)
            }

            if !trimmedError.isEmpty {
                AppLogger.warning(
                    "yt-dlp returned \(processOutput.terminationStatus) for \(channelURL) after listing \(results.count) valid video(s): \(trimmedError)",
                    category: "fetch"
                )
            }
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
            do {
                try await runProcessWithProgress(
                    ytdlp,
                    arguments: args,
                    downloadID: episode.videoID,
                    durationSeconds: episode.durationSeconds,
                    onProgress: progress
                )
            } catch {
                let shouldTrash = if let downloaderError = error as? DownloaderError, case .cancelled = downloaderError {
                    true
                } else {
                    false
                }
                try? cleanupPartialArtifacts(for: episode, in: episodesDir, moveToTrash: shouldTrash)
                throw error
            }
        } else {
            do {
                _ = try await runProcess(ytdlp, arguments: args)
            } catch {
                try? cleanupPartialArtifacts(for: episode, in: episodesDir, moveToTrash: false)
                throw error
            }
        }

        guard FileManager.default.fileExists(atPath: dest.path) else {
            throw DownloaderError.processError("MP3 file was not created for \(episode.videoID).")
        }
        return fileName
    }

    func cleanupPartialArtifacts(for episode: Episode, in episodesDir: URL, moveToTrash: Bool) throws {
        let fileManager = FileManager.default
        let prefix = String(episode.suggestedFileName.dropLast(4))

        guard let contents = try? fileManager.contentsOfDirectory(
            at: episodesDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in contents where url.lastPathComponent.hasPrefix(prefix) {
            if moveToTrash {
                if (try? fileManager.trashItem(at: url, resultingItemURL: nil)) == nil {
                    try? fileManager.removeItem(at: url)
                }
            } else {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    static func displayProgress(downloadProgress: Double, conversionProgress: Double?) -> Double {
        if let conversionProgress {
            return downloadPhaseWeight + (min(max(conversionProgress, 0), 1) * (1 - downloadPhaseWeight))
        }
        return min(max(downloadProgress, 0), 1) * downloadPhaseWeight
    }

    static func parseDownloadProgress(from line: String) -> Double? {
        parseDownloadProgress(from: line, with: try? NSRegularExpression(pattern: #"(\d+\.?\d*)%"#))
    }

    static func parseConversionProgress(from line: String, durationSeconds: Int) -> Double? {
        parseConversionProgress(
            from: line,
            durationSeconds: durationSeconds,
            with: try? NSRegularExpression(pattern: #"time=(\d+):(\d+):(\d+(?:\.\d+)?)"#)
        )
    }

    private static func parseDownloadProgress(from line: String, with pattern: NSRegularExpression?) -> Double? {
        guard let pattern else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = pattern.firstMatch(in: line, range: range),
              let numberRange = Range(match.range(at: 1), in: line),
              let percent = Double(line[numberRange])
        else {
            return nil
        }

        return min(percent / 100.0, 1.0)
    }

    private static func parseConversionProgress(
        from line: String,
        durationSeconds: Int,
        with pattern: NSRegularExpression?
    ) -> Double? {
        guard durationSeconds > 0, let pattern else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = pattern.firstMatch(in: line, range: range),
              let hoursRange = Range(match.range(at: 1), in: line),
              let minutesRange = Range(match.range(at: 2), in: line),
              let secondsRange = Range(match.range(at: 3), in: line),
              let hours = Double(line[hoursRange]),
              let minutes = Double(line[minutesRange]),
              let seconds = Double(line[secondsRange])
        else {
            return nil
        }

        let convertedSeconds = (hours * 3600) + (minutes * 60) + seconds
        return min(convertedSeconds / Double(durationSeconds), 1.0)
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

    static func parseVideoListOutput(_ output: String) -> [VideoInfo] {
        var results: [VideoInfo] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(
                separator: "\t",
                maxSplits: 5,
                omittingEmptySubsequences: false
            ).map(String.init)
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

    // MARK: - Process execution

    private func runProcess(_ path: String, arguments: [String]) async throws -> String {
        let output = try await runProcessCapturingOutput(path, arguments: arguments)
        if output.terminationStatus == 0 {
            return output.stdout
        }

        let message = output.stderr.isEmpty ? "Unknown error" : output.stderr
        throw DownloaderError.processError(message)
    }

    private func runProcessCapturingOutput(_ path: String, arguments: [String]) async throws -> ProcessOutput {
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
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outData, encoding: .utf8) ?? ""
                    let errorOutput = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(returning: ProcessOutput(
                        stdout: output,
                        stderr: errorOutput,
                        terminationStatus: process.terminationStatus
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runProcessWithProgress(
        _ path: String,
        arguments: [String],
        downloadID: String,
        durationSeconds: Int,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        runningDownloadProcesses[downloadID] = process
        cancelledDownloadIDs.remove(downloadID)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let outputQueue = DispatchQueue(label: "recast.downloader.progress")
                var stderrText = ""
                var stdoutText = ""
                var stdoutParser = ProgressParser(durationSeconds: durationSeconds)
                var stderrParser = ProgressParser(durationSeconds: durationSeconds)

                let handleOutput: (FileHandle, Bool) -> Void = { handle, isStandardError in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

                    outputQueue.sync {
                        if isStandardError {
                            stderrText += text
                            for value in stderrParser.ingest(text) {
                                onProgress(value)
                            }
                        } else {
                            stdoutText += text
                            for value in stdoutParser.ingest(text) {
                                onProgress(value)
                            }
                        }
                    }
                }

                stdout.fileHandleForReading.readabilityHandler = { handle in
                    handleOutput(handle, false)
                }

                stderr.fileHandleForReading.readabilityHandler = { handle in
                    handleOutput(handle, true)
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil

                    let finalOutput = outputQueue.sync { () -> (String, String) in
                        for value in stdoutParser.finish() + stderrParser.finish() {
                            onProgress(value)
                        }
                        return (stdoutText, stderrText)
                    }

                    Task {
                        let wasCancelled = await self.completeDownload(downloadID: downloadID)
                        if process.terminationStatus == 0 {
                            onProgress(1.0)
                            continuation.resume(returning: ())
                        } else if wasCancelled {
                            continuation.resume(throwing: DownloaderError.cancelled)
                        } else {
                            let message = [finalOutput.1, finalOutput.0]
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .first { !$0.isEmpty } ?? "Unknown error"
                            continuation.resume(throwing: DownloaderError.processError(message))
                        }
                    }
                } catch {
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    Task {
                        _ = await self.completeDownload(downloadID: downloadID)
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    func cancelDownload(videoID: String) {
        cancelledDownloadIDs.insert(videoID)
        runningDownloadProcesses[videoID]?.terminate()
    }

    func cancelAllDownloads() {
        for videoID in runningDownloadProcesses.keys {
            cancelledDownloadIDs.insert(videoID)
            runningDownloadProcesses[videoID]?.terminate()
        }
    }

    private func completeDownload(downloadID: String) -> Bool {
        runningDownloadProcesses.removeValue(forKey: downloadID)
        return cancelledDownloadIDs.remove(downloadID) != nil
    }
}
