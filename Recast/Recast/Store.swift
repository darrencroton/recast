import SwiftUI

@Observable
final class AppStore {

    // MARK: - State

    var channels: [Channel] = []
    var episodes: [Episode] = []
    var outputDirectory: URL = Paths.defaultOutputDir
    var serverPort: Int = 8888
    var isServerRunning = false
    var isFetching = false
    var statusMessage = "Ready"
    var activeDownloads: Set<String> = []       // videoIDs currently downloading
    var downloadProgress: [String: Double] = [:]  // videoID → 0.0…1.0

    // Settings
    var autoFetchInterval: Int = 0   // hours; 0 = disabled
    var autoStartServer: Bool = false

    // Dependencies
    var ytDlpReady = false
    var ffmpegReady = false
    var isInstallingDeps = false

    let downloader = Downloader()
    private var server: PodcastServer?
    private var autoFetchTimer: Timer?
    private let stateFileURL: URL

    // MARK: - Init

    init(
        stateFileURL: URL = Paths.stateFile,
        shouldLoadPersistentState: Bool = true,
        autoCheckDependencies: Bool = true
    ) {
        self.stateFileURL = stateFileURL
        AppLogger.info("Initialising store with state file \(stateFileURL.path)", category: "store")
        if shouldLoadPersistentState {
            load()
        }
        if autoCheckDependencies {
            Task { await checkDependencies() }
        }
    }

    // MARK: - Persistence

    private struct PersistentState: Codable {
        var channels: [Channel]
        var episodes: [Episode]
        var outputDirectory: String
        var serverPort: Int
        var autoFetchInterval: Int?
        var autoStartServer: Bool?
    }

    func save() {
        let state = PersistentState(
            channels: channels,
            episodes: episodes,
            outputDirectory: outputDirectory.path,
            serverPort: serverPort,
            autoFetchInterval: autoFetchInterval,
            autoStartServer: autoStartServer
        )
        if let data = try? JSONEncoder().encode(state) {
            do {
                try data.write(to: stateFileURL)
                AppLogger.info(
                    "Saved state with \(channels.count) channel(s), \(episodes.count) episode(s), output dir \(outputDirectory.path)",
                    category: "store"
                )
            } catch {
                AppLogger.error("Failed to save state to \(stateFileURL.path): \(error.localizedDescription)", category: "store")
            }
        } else {
            AppLogger.error("Failed to encode state for \(stateFileURL.path)", category: "store")
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: stateFileURL),
              let state = try? JSONDecoder().decode(PersistentState.self, from: data)
        else {
            AppLogger.info("No readable persisted state at \(stateFileURL.path); starting fresh", category: "store")
            return
        }
        channels = state.channels
        episodes = state.episodes
        outputDirectory = sanitizedOutputDirectory(URL(fileURLWithPath: state.outputDirectory))
        serverPort = state.serverPort
        autoFetchInterval = state.autoFetchInterval ?? 0
        autoStartServer = state.autoStartServer ?? false

        let didPruneEpisodes = pruneEpisodesWithoutChannels()
        let loadedOutputDirectory = URL(fileURLWithPath: state.outputDirectory)
        let didResetOutputDirectory = outputDirectory.standardizedFileURL != loadedOutputDirectory.standardizedFileURL

        AppLogger.info(
            "Loaded state with \(channels.count) channel(s), \(episodes.count) valid episode(s), output dir \(outputDirectory.path)",
            category: "store"
        )

        if didPruneEpisodes || didResetOutputDirectory {
            if didPruneEpisodes {
                AppLogger.warning("Pruned orphaned episodes that no longer matched any saved channel", category: "store")
            }
            if didResetOutputDirectory {
                AppLogger.warning(
                    "Reset missing temporary output directory \(loadedOutputDirectory.path) to \(outputDirectory.path)",
                    category: "store"
                )
            }
            save()
        }
    }

    // MARK: - Lifecycle (called from RecastApp.onAppear)

    func onLaunch() {
        if autoStartServer { startServer() }
        restartAutoFetchTimer()
    }

    // MARK: - Dependency management

    func checkDependencies() async {
        ytDlpReady = await downloader.hasYtDlp
        ffmpegReady = await downloader.hasFfmpeg
        AppLogger.info("Dependency check: yt-dlp ready=\(ytDlpReady), ffmpeg ready=\(ffmpegReady)", category: "setup")
    }

    func installDependencies() async {
        isInstallingDeps = true
        statusMessage = "Installing yt-dlp…"
        AppLogger.info("Installing external dependencies", category: "setup")
        do {
            if !ytDlpReady {
                try await downloader.installYtDlp()
                ytDlpReady = true
                AppLogger.info("Installed yt-dlp to \(Paths.ytDlpInBin.path)", category: "setup")
            }
            statusMessage = "Installing ffmpeg…"
            if !ffmpegReady {
                try await downloader.installFfmpeg()
                ffmpegReady = true
                AppLogger.info("Installed ffmpeg to \(Paths.ffmpegInBin.path)", category: "setup")
            }
            statusMessage = "Ready"
            AppLogger.info("Dependency installation completed", category: "setup")
        } catch {
            statusMessage = "Setup failed: \(error.localizedDescription)"
            AppLogger.error("Dependency installation failed: \(error.localizedDescription)", category: "setup")
        }
        isInstallingDeps = false
    }

    // MARK: - Channel management

    func addChannel(url: String) async throws {
        let cleaned = normalizeYouTubeURL(url)
        guard !channels.contains(where: { $0.url == cleaned }) else { return }
        statusMessage = "Resolving channel…"
        AppLogger.info("Adding channel from \(cleaned)", category: "channels")
        let name = try await downloader.resolveChannelName(url: cleaned)
        let channel = Channel(url: cleaned, name: name)
        channels.append(channel)
        save()
        statusMessage = "Added \(name)"
        AppLogger.info("Added channel \(name) with id \(channel.id)", category: "channels")
    }

    func removeChannels(_ ids: Set<UUID>) {
        AppLogger.info("Removing \(ids.count) channel(s)", category: "channels")
        episodes.removeAll { ids.contains($0.channelID) }
        channels.removeAll { ids.contains($0.id) }
        save()
        regenerateFeed()
    }

    // MARK: - Fetch (discover only — no downloads)

    func fetchNewEpisodes(for channelIDs: Set<UUID>) async {
        guard !isFetching else { return }
        isFetching = true
        let targets = channelIDs.isEmpty ? channels : channels.filter { channelIDs.contains($0.id) }

        var totalNew = 0
        var fetchErrors: [String] = []
        AppLogger.info("Starting fetch for \(targets.count) channel(s)", category: "fetch")

        for channel in targets {
            statusMessage = "Checking \(channel.name)…"
            do {
                let videos = try await downloader.listVideos(channelURL: channel.url)
                let knownIDs = Set(episodes.filter { $0.channelID == channel.id }.map(\.videoID))
                AppLogger.info(
                    "Fetched \(videos.count) candidate video(s) for \(channel.name); \(knownIDs.count) already known",
                    category: "fetch"
                )

                for video in videos where !knownIDs.contains(video.videoID) {
                    let ep = Episode(
                        channelID: channel.id,
                        videoID: video.videoID,
                        title: video.title,
                        publishDate: video.publishDate,
                        durationSeconds: video.durationSeconds
                    )
                    episodes.append(ep)
                    totalNew += 1
                }
            } catch {
                let message = "\(channel.name): \(error.localizedDescription)"
                fetchErrors.append(message)
                AppLogger.error("Fetch failed for \(message)", category: "fetch")
            }
        }

        save()
        if !fetchErrors.isEmpty {
            if totalNew > 0 {
                statusMessage = "Found \(totalNew) new episode(s); \(fetchErrors.count) channel fetch failed"
            } else {
                statusMessage = fetchErrors.count == 1
                    ? "Fetch failed for \(fetchErrors[0])"
                    : "Fetch failed for \(fetchErrors.count) channels"
            }
        } else {
            statusMessage = totalNew > 0 ? "Found \(totalNew) new episode(s)" : "No new episodes"
        }
        AppLogger.info(statusMessage, category: "fetch")
        isFetching = false
    }

    // MARK: - Download

    func downloadEpisode(_ episode: Episode) async {
        guard !activeDownloads.contains(episode.videoID), !episode.isDownloaded else { return }
        let episodesDir = Paths.episodesDir(in: outputDirectory)
        let videoID = episode.videoID

        activeDownloads.insert(videoID)
        downloadProgress[videoID] = 0
        statusMessage = "Downloading: \(episode.title.prefix(50))…"
        AppLogger.info("Downloading episode \(episode.videoID) as \(episode.suggestedFileName)", category: "download")

        do {
            let fileName = try await downloader.downloadAudio(
                episode: episode,
                to: episodesDir
            ) { [weak self] pct in
                Task { @MainActor [weak self, videoID] in
                    self?.downloadProgress[videoID] = pct
                }
            }
            if let idx = episodes.firstIndex(where: { $0.videoID == videoID }) {
                episodes[idx].fileName = fileName
            }
            statusMessage = "Downloaded: \(episode.title.prefix(50))"
            AppLogger.info("Downloaded episode \(episode.videoID) to \(fileName)", category: "download")
        } catch {
            statusMessage = "Failed: \(episode.title.prefix(40)) — \(error.localizedDescription)"
            AppLogger.error("Download failed for \(episode.videoID): \(error.localizedDescription)", category: "download")
        }

        activeDownloads.remove(videoID)
        downloadProgress.removeValue(forKey: videoID)
        save()
        regenerateFeed()
    }

    func downloadAllNew(for channelIDs: Set<UUID>) async {
        let targets = sortEpisodesNewestFirst(validEpisodes.filter { ep in
            !ep.isDownloaded &&
            !activeDownloads.contains(ep.videoID) &&
            (channelIDs.isEmpty || channelIDs.contains(ep.channelID))
        })

        for episode in targets {
            await downloadEpisode(episode)
        }
    }

    func downloadEpisodes(_ ids: Set<UUID>) async {
        let targets = sortEpisodesNewestFirst(
            validEpisodes.filter {
                ids.contains($0.id) &&
                !$0.isDownloaded &&
                !activeDownloads.contains($0.videoID)
            }
        )

        for episode in targets {
            await downloadEpisode(episode)
        }
    }

    /// Auto-fetch: discover AND download (background behaviour)
    func autoFetch() async {
        await fetchNewEpisodes(for: Set())
        await downloadAllNew(for: Set())
    }

    // MARK: - Episode management

    func deleteEpisodes(_ ids: Set<UUID>) {
        AppLogger.info("Deleting \(ids.count) episode(s)", category: "episodes")
        let fm = FileManager.default
        let episodesDir = Paths.episodesDir(in: outputDirectory)
        for ep in episodes where ids.contains(ep.id) {
            if let fileName = ep.fileName {
                let file = episodesDir.appendingPathComponent(fileName)
                try? fm.removeItem(at: file)
            }
        }
        episodes.removeAll { ids.contains($0.id) }
        save()
        regenerateFeed()
    }

    func togglePlayed(_ episodeID: UUID) {
        if let idx = episodes.firstIndex(where: { $0.id == episodeID }) {
            episodes[idx].isPlayed.toggle()
            AppLogger.info(
                "Marked episode \(episodes[idx].videoID) as \(episodes[idx].isPlayed ? "played" : "unplayed")",
                category: "episodes"
            )
            save()
        }
    }

    func revealInFinder(_ episode: Episode) {
        guard let fileName = episode.fileName else { return }
        let path = Paths.episodesDir(in: outputDirectory).appendingPathComponent(fileName)
        NSWorkspace.shared.activateFileViewerSelecting([path])
    }

    // MARK: - Filtered episodes (search + channel filter)

    func filteredEpisodes(for channelIDs: Set<UUID>, query: String) -> [Episode] {
        var result = validEpisodes

        if !channelIDs.isEmpty {
            result = result.filter { channelIDs.contains($0.channelID) }
        }

        if !query.isEmpty {
            let q = query.lowercased()
            result = result.filter { $0.title.lowercased().contains(q) }
        }

        return sortEpisodesNewestFirst(result)
    }

    // MARK: - Feed

    func regenerateFeed() {
        let host = localIPAddress ?? "localhost"
        let baseURL = "http://\(host):\(serverPort)"
        let downloaded = sortEpisodesNewestFirst(validEpisodes.filter(\.isDownloaded))
        AppLogger.info("Regenerating feed with \(downloaded.count) downloaded episode(s) at \(baseURL)", category: "feed")
        FeedGenerator.write(
            episodes: downloaded,
            channels: channels,
            baseURL: baseURL,
            to: outputDirectory
        )
    }

    // MARK: - Server

    func startServer() {
        guard !isServerRunning else { return }
        regenerateFeed()
        server = PodcastServer(port: UInt16(serverPort), rootDir: outputDirectory)
        do {
            try server?.start()
            isServerRunning = true
            statusMessage = "Server running on port \(serverPort)"
            AppLogger.info("Started server on port \(serverPort) serving \(outputDirectory.path)", category: "server")
        } catch {
            statusMessage = "Server failed: \(error.localizedDescription)"
            AppLogger.error("Failed to start server on port \(serverPort): \(error.localizedDescription)", category: "server")
        }
    }

    func stopServer() {
        server?.stop()
        server = nil
        isServerRunning = false
        statusMessage = "Server stopped"
        AppLogger.info("Stopped server", category: "server")
    }

    // MARK: - Auto-fetch timer

    func restartAutoFetchTimer() {
        autoFetchTimer?.invalidate()
        autoFetchTimer = nil
        guard autoFetchInterval > 0 else { return }
        let interval = TimeInterval(autoFetchInterval * 3600)
        autoFetchTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.autoFetch() }
        }
    }

    // MARK: - Network helpers

    var localIPAddress: String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(first) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = ptr {
            defer { ptr = ifa.pointee.ifa_next }
            guard let ifaAddr = ifa.pointee.ifa_addr else { continue }
            let sa = ifaAddr.pointee
            guard sa.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            // Skip loopback; accept any non-loopback IPv4 interface
            guard name != "lo0" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(ifaAddr, socklen_t(sa.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            address = String(cString: hostname)
            break
        }
        return address
    }

    var feedURL: String {
        let host = localIPAddress ?? "localhost"
        return "http://\(host):\(serverPort)/feed.xml"
    }

    // MARK: - Helpers

    var allEpisodesCount: Int {
        validEpisodes.count
    }

    func episodes(for channelID: UUID) -> [Episode] {
        sortEpisodesNewestFirst(validEpisodes.filter { $0.channelID == channelID })
    }

    func normalizeYouTubeURL(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        u = u.replacingOccurrences(of: "https://m.youtube.com", with: "https://www.youtube.com")
        if u.contains("/@") && !u.hasSuffix("/videos") && !u.contains("/playlist") {
            u = u.hasSuffix("/") ? u + "videos" : u + "/videos"
        }
        return u
    }

    private func sortEpisodesNewestFirst(_ episodes: [Episode]) -> [Episode] {
        episodes.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.publishDate != rhs.element.publishDate {
                    return lhs.element.publishDate > rhs.element.publishDate
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private var validEpisodes: [Episode] {
        let knownChannelIDs = Set(channels.map(\.id))
        guard !knownChannelIDs.isEmpty else { return episodes }
        return episodes.filter { knownChannelIDs.contains($0.channelID) }
    }

    private func pruneEpisodesWithoutChannels() -> Bool {
        let pruned = validEpisodes
        guard pruned.count != episodes.count else { return false }
        episodes = pruned
        return true
    }

    private func sanitizedOutputDirectory(_ loadedDirectory: URL) -> URL {
        let standardized = loadedDirectory.standardizedFileURL
        let temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let isTemporary = standardized.path.hasPrefix(temporaryRoot)
        if isTemporary {
            return Paths.defaultOutputDir
        }
        return loadedDirectory
    }
}
