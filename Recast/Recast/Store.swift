import SwiftUI

@Observable
final class AppStore {
    private static let defaultServerPort = 8888
    private static let defaultAutoFetchInterval = 0
    private static let defaultAutoStartServer = false

    // MARK: - State

    var channels: [Channel] = []
    var episodes: [Episode] = []
    var outputDirectory: URL
    var serverPort: Int = 8888
    var isServerRunning = false
    var isFetching = false
    var isStoppingFetch = false
    var activeRefreshChannelIDs: Set<UUID> = []
    var currentRefreshChannelID: UUID?
    var statusMessage = "Ready"
    var activeDownloads: Set<String> = []       // videoIDs currently downloading
    var activeDownloadStatus: [String: DownloadStatus] = [:]
    var isStoppingDownloads = false

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
    private let appSupportURL: URL
    private let defaultOutputDirectory: URL
    private let stateFileURL: URL
    private var cancelAllDownloadsRequested = false
    private var operationGeneration: UInt64 = 0

    // MARK: - Init

    init(
        stateFileURL: URL = Paths.stateFile,
        appSupportURL: URL = Paths.appSupport,
        defaultOutputDirectory: URL = Paths.defaultOutputDir,
        shouldLoadPersistentState: Bool = true,
        autoCheckDependencies: Bool = true
    ) {
        self.outputDirectory = defaultOutputDirectory
        self.appSupportURL = appSupportURL
        self.defaultOutputDirectory = defaultOutputDirectory
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
                try FileManager.default.createDirectory(
                    at: stateFileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil
                )
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

    @MainActor
    func checkDependencies() async {
        ytDlpReady = await downloader.hasYtDlp
        ffmpegReady = await downloader.hasFfmpeg
        AppLogger.info("Dependency check: yt-dlp ready=\(ytDlpReady), ffmpeg ready=\(ffmpegReady)", category: "setup")
    }

    @MainActor
    func installDependencies() async {
        let operationToken = operationGeneration
        isInstallingDeps = true
        statusMessage = "Installing yt-dlp…"
        AppLogger.info("Installing external dependencies", category: "setup")
        do {
            if !ytDlpReady {
                try await downloader.installYtDlp()
                guard isCurrentOperation(operationToken) else {
                    removeManagedAppSupportArtifacts(removeStateFile: false)
                    statusMessage = "Ready"
                    isInstallingDeps = false
                    await checkDependencies()
                    return
                }
                ytDlpReady = true
                AppLogger.info("Installed yt-dlp to \(Paths.ytDlpInBin.path)", category: "setup")
            }
            statusMessage = "Installing ffmpeg…"
            if !ffmpegReady {
                try await downloader.installFfmpeg()
                guard isCurrentOperation(operationToken) else {
                    removeManagedAppSupportArtifacts(removeStateFile: false)
                    statusMessage = "Ready"
                    isInstallingDeps = false
                    await checkDependencies()
                    return
                }
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

    @MainActor
    func addChannel(url: String) async throws {
        let operationToken = operationGeneration
        let cleaned = normalizeYouTubeURL(url)
        guard !channels.contains(where: { $0.url == cleaned }) else { return }
        statusMessage = "Resolving channel…"
        AppLogger.info("Adding channel from \(cleaned)", category: "channels")
        let name = try await downloader.resolveChannelName(url: cleaned)
        guard isCurrentOperation(operationToken) else { return }
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

    @MainActor
    @discardableResult
    func fetchNewEpisodes(for channelIDs: Set<UUID>) async -> Bool {
        guard !isFetching else { return false }
        let operationToken = operationGeneration
        isFetching = true
        isStoppingFetch = false
        currentRefreshChannelID = nil
        defer {
            isFetching = false
            isStoppingFetch = false
            activeRefreshChannelIDs.removeAll()
            currentRefreshChannelID = nil
        }

        let targets = channelIDs.isEmpty ? channels : channels.filter { channelIDs.contains($0.id) }
        let targetChannelIDs = Set(targets.map(\.id))
        activeRefreshChannelIDs = targetChannelIDs

        var totalNew = 0
        var fetchErrors: [String] = []
        var wasCancelled = false
        AppLogger.info("Starting fetch for \(targets.count) channel(s)", category: "fetch")

        clearNewFlags(for: targetChannelIDs)

        for channel in targets {
            if isStoppingFetch {
                wasCancelled = true
                break
            }
            guard isCurrentOperation(operationToken) else { return false }
            currentRefreshChannelID = channel.id
            statusMessage = "Checking \(channel.name)…"
            do {
                let videos = try await downloader.listVideos(channelURL: channel.url)
                guard isCurrentOperation(operationToken) else { return false }
                let knownIDs = Set(episodes.filter { $0.channelID == channel.id }.map(\.videoID))
                AppLogger.info(
                    "Fetched \(videos.count) candidate video(s) for \(channel.name); \(knownIDs.count) already known",
                    category: "fetch"
                )

                for video in videos where !knownIDs.contains(video.videoID) {
                    var ep = Episode(
                        channelID: channel.id,
                        videoID: video.videoID,
                        title: video.title,
                        publishDate: video.publishDate,
                        durationSeconds: video.durationSeconds
                    )
                    ep.isNew = true
                    episodes.append(ep)
                    totalNew += 1
                }
            } catch DownloaderError.cancelled {
                guard isCurrentOperation(operationToken) else { return false }
                wasCancelled = true
                AppLogger.info("Stopped fetch while checking \(channel.name)", category: "fetch")
                break
            } catch {
                guard isCurrentOperation(operationToken) else { return false }
                let message = "\(channel.name): \(error.localizedDescription)"
                fetchErrors.append(message)
                AppLogger.error("Fetch failed for \(message)", category: "fetch")
            }
        }

        guard isCurrentOperation(operationToken) else { return false }
        save()
        if wasCancelled {
            statusMessage = totalNew > 0
                ? "Stopped refresh after finding \(totalNew) new episode(s)"
                : "Refresh stopped"
        } else if !fetchErrors.isEmpty {
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
        return !wasCancelled
    }

    // MARK: - Download

    @MainActor
    func downloadEpisode(_ episode: Episode, operationToken: UInt64? = nil) async {
        let operationToken = operationToken ?? operationGeneration
        let existingStatus = activeDownloadStatus[episode.videoID]
        guard isCurrentOperation(operationToken) else { return }
        guard !activeDownloads.contains(episode.videoID), !episode.isDownloaded else { return }
        guard existingStatus == nil || existingStatus?.phase == .queued else { return }
        let episodesDir = Paths.ensureManagedEpisodesDirectory(in: outputDirectory)
        let videoID = episode.videoID

        activeDownloads.insert(videoID)
        activeDownloadStatus[videoID] = DownloadStatus(progress: 0, phase: .preparing)
        isStoppingDownloads = false
        statusMessage = "Downloading: \(episode.title.prefix(50))…"
        AppLogger.info("Downloading episode \(episode.videoID) as \(episode.suggestedFileName)", category: "download")

        do {
            let fileName = try await downloader.downloadAudio(
                episode: episode,
                to: episodesDir
            ) { [weak self] update in
                Task { @MainActor [weak self, videoID, operationToken] in
                    guard let self, self.isCurrentOperation(operationToken) else { return }
                    self.activeDownloadStatus[videoID] = DownloadStatus(
                        progress: update.progress,
                        phase: update.phase
                    )
                }
            }
            guard isCurrentOperation(operationToken) else { return }
            if let idx = episodes.firstIndex(where: { $0.videoID == videoID }) {
                episodes[idx].fileName = fileName
            }
            statusMessage = "Downloaded: \(episode.title.prefix(50))"
            AppLogger.info("Downloaded episode \(episode.videoID) to \(fileName)", category: "download")
        } catch DownloaderError.cancelled {
            guard isCurrentOperation(operationToken) else { return }
            statusMessage = "Stopped: \(episode.title.prefix(50))"
            AppLogger.info("Stopped download for \(episode.videoID)", category: "download")
        } catch {
            guard isCurrentOperation(operationToken) else { return }
            statusMessage = "Failed: \(episode.title.prefix(40)) — \(error.localizedDescription)"
            AppLogger.error("Download failed for \(episode.videoID): \(error.localizedDescription)", category: "download")
        }

        guard isCurrentOperation(operationToken) else { return }
        activeDownloads.remove(videoID)
        activeDownloadStatus.removeValue(forKey: videoID)
        if activeDownloads.isEmpty {
            isStoppingDownloads = false
        }
        save()
        regenerateFeed()
    }

    @MainActor
    func downloadAllNew(for channelIDs: Set<UUID>, operationToken: UInt64? = nil) async {
        let operationToken = operationToken ?? operationGeneration
        guard isCurrentOperation(operationToken) else { return }
        cancelAllDownloadsRequested = false
        let targets = sortEpisodesNewestFirst(validEpisodes.filter { ep in
            !ep.isDownloaded &&
            activeDownloadStatus[ep.videoID] == nil &&
            (channelIDs.isEmpty || channelIDs.contains(ep.channelID))
        })
        queueDownloads(targets)

        for episode in targets {
            guard isCurrentOperation(operationToken), !cancelAllDownloadsRequested else { break }
            await downloadEpisode(episode, operationToken: operationToken)
        }

        clearQueuedDownloads(targets)
    }

    @MainActor
    func downloadEpisodes(_ ids: Set<UUID>, operationToken: UInt64? = nil) async {
        let operationToken = operationToken ?? operationGeneration
        guard isCurrentOperation(operationToken) else { return }
        cancelAllDownloadsRequested = false
        let targets = sortEpisodesNewestFirst(
            validEpisodes.filter {
                ids.contains($0.id) &&
                !$0.isDownloaded &&
                activeDownloadStatus[$0.videoID] == nil
            }
        )
        queueDownloads(targets)

        for episode in targets {
            guard isCurrentOperation(operationToken), !cancelAllDownloadsRequested else { break }
            await downloadEpisode(episode, operationToken: operationToken)
        }

        clearQueuedDownloads(targets)
    }

    /// Auto-fetch: discover AND download (background behaviour)
    @MainActor
    func autoFetch() async {
        let operationToken = operationGeneration
        let didCompleteFetch = await fetchNewEpisodes(for: Set())
        guard didCompleteFetch, isCurrentOperation(operationToken) else { return }
        await downloadAllNew(for: Set(), operationToken: operationToken)
    }

    // MARK: - Episode management

    func deleteEpisodes(_ ids: Set<UUID>) {
        AppLogger.info("Deleting \(ids.count) episode(s)", category: "episodes")
        let episodesDir = Paths.episodesDir(in: outputDirectory)
        let targetEpisodes = episodes.filter { ids.contains($0.id) }
        removeManagedEpisodeArtifacts(for: targetEpisodes, in: episodesDir)
        removeManagedEpisodesDirectoryIfEmptyAndOwned(at: episodesDir)
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

    func filteredEpisodes(for channelIDs: Set<UUID>, query: String, filter: EpisodeFilter) -> [Episode] {
        let result = filteredEpisodes(for: channelIDs, query: query)
        switch filter {
        case .all:
            return result
        case .downloaded:
            return result.filter(\.isDownloaded)
        case .new:
            return result.filter(\.isNew)
        case .unplayed:
            return result.filter { !$0.isPlayed && $0.isDownloaded }
        }
    }

    func episodeCount(for channelIDs: Set<UUID>, query: String, filter: EpisodeFilter) -> Int {
        filteredEpisodes(for: channelIDs, query: query, filter: filter).count
    }

    func artworkURL(for episode: Episode) -> URL? {
        guard let fileName = episode.fileName else { return nil }
        let artworkURL = Paths.artworkURL(forEpisodeFileName: fileName, in: outputDirectory)
        guard FileManager.default.fileExists(atPath: artworkURL.path) else { return nil }
        return artworkURL
    }

    func downloadStatus(for episode: Episode) -> DownloadStatus? {
        activeDownloadStatus[episode.videoID]
    }

    func channelArtworkURL(for channelID: UUID) -> URL? {
        for episode in episodes(for: channelID) {
            if let artworkURL = artworkURL(for: episode) {
                return artworkURL
            }
        }
        return nil
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

    var hasActiveDownloads: Bool {
        !activeDownloads.isEmpty
    }

    var hasPendingDownloads: Bool {
        !activeDownloadStatus.isEmpty
    }

    var activeDownloadEpisodes: [Episode] {
        sortEpisodesNewestFirst(validEpisodes.filter { activeDownloadStatus[$0.videoID] != nil })
    }

    var currentRefreshChannelName: String? {
        guard let currentRefreshChannelID else { return nil }
        return channels.first(where: { $0.id == currentRefreshChannelID })?.name
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

    private func clearNewFlags(for channelIDs: Set<UUID>) {
        guard !channelIDs.isEmpty else { return }
        for index in episodes.indices where channelIDs.contains(episodes[index].channelID) {
            episodes[index].isNew = false
        }
    }

    private func queueDownloads(_ episodes: [Episode]) {
        for episode in episodes where activeDownloadStatus[episode.videoID] == nil {
            activeDownloadStatus[episode.videoID] = DownloadStatus(progress: 0, phase: .queued)
        }
    }

    private func clearQueuedDownloads(_ episodes: [Episode]) {
        for episode in episodes where activeDownloadStatus[episode.videoID]?.phase == .queued {
            activeDownloadStatus.removeValue(forKey: episode.videoID)
        }
        if activeDownloadStatus.isEmpty {
            isStoppingDownloads = false
        }
    }

    func stopDownload(videoID: String) {
        guard activeDownloads.contains(videoID) else { return }
        statusMessage = "Stopping download…"
        isStoppingDownloads = true
        AppLogger.info("Requesting stop for \(videoID)", category: "download")
        Task {
            await downloader.cancelDownload(videoID: videoID)
        }
    }

    func stopAllDownloads() {
        guard hasPendingDownloads else { return }
        cancelAllDownloadsRequested = true
        isStoppingDownloads = true
        statusMessage = "Stopping downloads…"
        AppLogger.info("Requesting stop for all downloads", category: "download")
        Task {
            await downloader.cancelAllDownloads()
        }
    }

    func stopFetch() {
        guard isFetching, !isStoppingFetch else { return }
        statusMessage = "Stopping refresh…"
        isStoppingFetch = true
        AppLogger.info("Requesting stop for current fetch", category: "fetch")
        Task {
            await downloader.cancelFetch()
        }
    }

    @MainActor
    func resetToDefaults() async {
        AppLogger.warning("Resetting app to default state", category: "store")
        operationGeneration &+= 1

        statusMessage = "Resetting app…"
        cancelAllDownloadsRequested = true
        if isFetching {
            await downloader.cancelFetch()
        }
        isFetching = false
        isStoppingFetch = false
        activeRefreshChannelIDs.removeAll()
        currentRefreshChannelID = nil
        isInstallingDeps = false

        autoFetchTimer?.invalidate()
        autoFetchTimer = nil

        if hasPendingDownloads {
            isStoppingDownloads = true
            await downloader.cancelAllDownloadsAndWait()
        }

        server?.stop()
        server = nil
        isServerRunning = false

        let previousOutputDirectory = outputDirectory
        let previousEpisodes = episodes
        removeManagedOutputArtifacts(at: previousOutputDirectory, episodes: previousEpisodes)
        removeManagedAppSupportArtifacts(removeStateFile: true)

        channels.removeAll()
        episodes.removeAll()
        outputDirectory = defaultOutputDirectory
        serverPort = Self.defaultServerPort
        autoFetchInterval = Self.defaultAutoFetchInterval
        autoStartServer = Self.defaultAutoStartServer
        activeDownloads.removeAll()
        activeDownloadStatus.removeAll()
        cancelAllDownloadsRequested = false
        isStoppingDownloads = false
        statusMessage = "Ready"

        save()
        await checkDependencies()
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
            return defaultOutputDirectory
        }
        return loadedDirectory
    }

    private func isCurrentOperation(_ token: UInt64) -> Bool {
        token == operationGeneration
    }

    private func removeManagedOutputArtifacts(at outputDirectory: URL, episodes: [Episode]) {
        let fileManager = FileManager.default
        let episodesDir = outputDirectory.appendingPathComponent("episodes", isDirectory: true)
        let feedFile = outputDirectory.appendingPathComponent("feed.xml")

        if isManagedFeed(at: feedFile) {
            try? fileManager.removeItem(at: feedFile)
        }

        removeManagedEpisodeArtifacts(for: episodes, in: episodesDir)
        removeManagedEpisodesDirectoryIfEmptyAndOwned(at: episodesDir)
    }

    private func removeManagedEpisodeArtifacts(for episodes: [Episode], in episodesDir: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: episodesDir.path) else { return }

        let downloadedFileNames = Set(episodes.compactMap(\.fileName))
        for fileName in downloadedFileNames {
            let fileURL = episodesDir.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        let downloadedArtworkFileNames = Set(episodes.compactMap(\.artworkFileName))
        for artworkFileName in downloadedArtworkFileNames {
            let artworkURL = episodesDir.appendingPathComponent(artworkFileName)
            if fileManager.fileExists(atPath: artworkURL.path) {
                try? fileManager.removeItem(at: artworkURL)
            }
        }

        let managedPrefixes = Set(episodes.map { String($0.suggestedFileName.dropLast(4)) })
        guard let contents = try? fileManager.contentsOfDirectory(
            at: episodesDir,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            return
        }

        for url in contents where managedPrefixes.contains(where: { url.lastPathComponent.hasPrefix($0) }) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func removeManagedEpisodesDirectoryIfEmptyAndOwned(at episodesDir: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: episodesDir.path) else { return }

        let markerFile = episodesDir.appendingPathComponent(Paths.managedEpisodesMarkerFileName)
        guard fileManager.fileExists(atPath: markerFile.path) else { return }

        let contents = (try? fileManager.contentsOfDirectory(
            at: episodesDir,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []

        let nonMarkerContents = contents.filter { $0.lastPathComponent != Paths.managedEpisodesMarkerFileName }
        guard nonMarkerContents.isEmpty else { return }

        try? fileManager.removeItem(at: episodesDir)
    }

    private func isManagedFeed(at feedFile: URL) -> Bool {
        guard let content = try? String(contentsOf: feedFile, encoding: .utf8) else { return false }

        if content.contains(FeedGenerator.managedFeedMarker) {
            return true
        }

        return content.contains("<title>Recast</title>")
            && content.contains("<itunes:author>Recast</itunes:author>")
            && content.contains("<link>https://github.com</link>")
    }

    private func removeManagedAppSupportArtifacts(removeStateFile: Bool) {
        let fileManager = FileManager.default
        let binDir = appSupportURL.appendingPathComponent("bin", isDirectory: true)

        if removeStateFile, fileManager.fileExists(atPath: stateFileURL.path) {
            try? fileManager.removeItem(at: stateFileURL)
        }
        if fileManager.fileExists(atPath: binDir.path) {
            try? fileManager.removeItem(at: binDir)
        }
    }
}
