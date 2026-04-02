import SwiftUI

@Observable
final class AppStore {
    private static let defaultServerPort = 8888
    private static let defaultServerHost = ""
    private static let defaultAutoFetchInterval = 0
    private static let defaultAutoStartServer = false
    private let openURLInDefaultApp: (URL) -> Bool
    private let revealURLsInFinder: ([URL]) -> Void

    private enum ResolvedYouTubeInput {
        case collection(url: String)
        case singleVideo(url: String, videoID: String)
    }

    private enum AddSourceError: LocalizedError {
        case invalidYouTubeURL

        var errorDescription: String? {
            switch self {
            case .invalidYouTubeURL:
                return "Please enter a valid YouTube channel, playlist, or episode URL."
            }
        }
    }

    // MARK: - State

    var channels: [Channel] = []
    var episodes: [Episode] = []
    var outputDirectory: URL
    var serverPort: Int = 8888
    var serverHost: String = ""   // empty = auto-detect from network interfaces
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
        autoCheckDependencies: Bool = true,
        openURLInDefaultApp: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        revealURLsInFinder: @escaping ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }
    ) {
        self.outputDirectory = defaultOutputDirectory
        self.appSupportURL = appSupportURL
        self.defaultOutputDirectory = defaultOutputDirectory
        self.stateFileURL = stateFileURL
        self.openURLInDefaultApp = openURLInDefaultApp
        self.revealURLsInFinder = revealURLsInFinder
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
        var serverHost: String?
        var autoFetchInterval: Int?
        var autoStartServer: Bool?
    }

    func save() {
        let state = PersistentState(
            channels: channels,
            episodes: episodes,
            outputDirectory: outputDirectory.path,
            serverPort: serverPort,
            serverHost: serverHost.isEmpty ? nil : serverHost,
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
        serverPort = sanitizedServerPort(state.serverPort)
        serverHost = sanitizedServerHost(state.serverHost ?? Self.defaultServerHost)
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
        try await addSource(url: url)
    }

    @MainActor
    func addSource(url: String) async throws {
        let operationToken = operationGeneration
        let cleaned = normalizeYouTubeURL(url)
        guard let input = resolvedYouTubeInput(for: cleaned) else {
            throw AddSourceError.invalidYouTubeURL
        }

        switch input {
        case .collection(let collectionURL):
            guard !channels.contains(where: { $0.url == collectionURL }) else {
                statusMessage = "Source already added"
                return
            }

            statusMessage = "Resolving source…"
            AppLogger.info("Adding collection source from \(collectionURL)", category: "channels")
            let name = try await downloader.resolveChannelName(url: collectionURL)
            guard isCurrentOperation(operationToken) else { return }

            let channel = Channel(url: collectionURL, name: name)
            channels.append(channel)
            save()
            statusMessage = "Added \(name)"
            AppLogger.info("Added collection source \(name) with id \(channel.id)", category: "channels")

        case .singleVideo(let videoURL, _):
            statusMessage = "Resolving episode…"
            AppLogger.info("Adding single-episode source from \(videoURL)", category: "channels")
            let resolvedVideo = try await downloader.resolveVideoSource(url: videoURL)
            guard isCurrentOperation(operationToken) else { return }
            let normalizedCollectionURL = resolvedVideo.collectionURL.map(normalizeYouTubeURL)

            if episodes.contains(where: { $0.videoID == resolvedVideo.video.videoID }) {
                statusMessage = "Episode already added"
                AppLogger.info("Skipped single-episode source for \(resolvedVideo.video.videoID); episode already exists", category: "channels")
                return
            }

            if let collectionURL = normalizedCollectionURL,
               let existingCollection = channels.first(where: {
                   $0.sourceKind == .collection && $0.url == collectionURL
               }) {
                appendEpisodeIfNeeded(resolvedVideo.video, to: existingCollection.id, markAsNew: false)
                save()
                statusMessage = "Added episode to \(existingCollection.name)"
                AppLogger.info(
                    "Added episode \(resolvedVideo.video.videoID) to existing source \(existingCollection.name)",
                    category: "channels"
                )
                return
            }

            guard !channels.contains(where: { $0.url == videoURL }) else {
                statusMessage = "Source already added"
                return
            }

            let sourceName = resolvedVideo.channelName.isEmpty ? resolvedVideo.video.title : resolvedVideo.channelName
            let channel = Channel(
                url: videoURL,
                name: sourceName,
                sourceKind: .singleEpisode,
                relatedCollectionURL: normalizedCollectionURL
            )
            channels.append(channel)
            appendEpisodeIfNeeded(resolvedVideo.video, to: channel.id, markAsNew: false)
            save()
            statusMessage = "Added episode from \(sourceName)"
            AppLogger.info(
                "Added single-episode source \(sourceName) with video \(resolvedVideo.video.videoID)",
                category: "channels"
            )
        }
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
        AppLogger.info("Starting fetch for \(targets.count) source(s)", category: "fetch")

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
                let videos = try await videosForFetch(for: channel)
                guard isCurrentOperation(operationToken) else { return false }
                AppLogger.info(
                    "Fetched \(videos.count) candidate video(s) for \(channel.name)",
                    category: "fetch"
                )

                for video in videos {
                    if handleFetchedVideo(video, for: channel) {
                        totalNew += 1
                    }
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

        pruneEmptySingleEpisodeSources()
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
                    : "Fetch failed for \(fetchErrors.count) sources"
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
        guard let channel = channels.first(where: { $0.id == episode.channelID }) else {
            statusMessage = "Failed: \(episode.title.prefix(40)) — Missing channel"
            AppLogger.error("Download failed for \(episode.videoID): missing channel \(episode.channelID)", category: "download")
            return
        }
        let episodesDir = Paths.ensureManagedChannelEpisodesDirectory(for: channel, in: outputDirectory)
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
            let relativePath = Paths.relativeEpisodePath(forFileName: fileName, in: channel)
            if let idx = episodes.firstIndex(where: { $0.videoID == videoID }) {
                episodes[idx].fileName = relativePath
            }
            statusMessage = "Downloaded: \(episode.title.prefix(50))"
            AppLogger.info("Downloaded episode \(episode.videoID) to \(relativePath)", category: "download")
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
        let targetEpisodes = episodes.filter { ids.contains($0.id) }
        let episodesDir = Paths.episodesDirectoryURL(in: outputDirectory)
        removeManagedEpisodeArtifacts(for: targetEpisodes, channels: channels, in: outputDirectory)
        removeManagedEpisodesDirectoryIfEmptyAndOwned(at: episodesDir)
        episodes.removeAll { ids.contains($0.id) }
        pruneEmptySingleEpisodeSources()
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

    func downloadedEpisodeFileURL(for episode: Episode) -> URL? {
        guard let fileName = episode.fileName else { return nil }
        let fileURL = Paths.episodeFileURL(forRelativePath: fileName, in: outputDirectory)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    func openEpisode(_ episode: Episode) {
        guard let fileURL = downloadedEpisodeFileURL(for: episode) else {
            statusMessage = "Episode file unavailable"
            AppLogger.warning("Tried to open unavailable episode file for \(episode.videoID)", category: "episodes")
            return
        }

        guard openURLInDefaultApp(fileURL) else {
            statusMessage = "Couldn't open episode"
            AppLogger.warning("Failed to open episode \(episode.videoID) at \(fileURL.path)", category: "episodes")
            return
        }

        AppLogger.info("Opened episode \(episode.videoID) at \(fileURL.path)", category: "episodes")
    }

    func revealInFinder(_ episode: Episode) {
        guard let fileURL = downloadedEpisodeFileURL(for: episode) else { return }
        revealURLsInFinder([fileURL])
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
        let baseURL = serverBaseURL
        let downloaded = sortEpisodesNewestFirst(validEpisodes.filter(\.isDownloaded))
        ShowArtwork.ensureExists(in: outputDirectory)
        AppLogger.info("Regenerating feed with \(downloaded.count) downloaded episode(s) at \(baseURL)", category: "feed")
        FeedGenerator.write(
            episodes: downloaded,
            channels: channels,
            baseURL: baseURL,
            to: outputDirectory
        )
    }

    // MARK: - Server

    var defaultServerPort: Int {
        Self.defaultServerPort
    }

    func handleServerHostChange() {
        save()
        regenerateFeed()
    }

    func handleServerPortChange() {
        save()
        guard isServerRunning else {
            regenerateFeed()
            return
        }

        stopServer()
        startServer()
    }

    func commitServerHost(_ input: String) {
        let sanitizedHost = sanitizedServerHost(input)
        guard sanitizedHost != serverHost else { return }
        serverHost = sanitizedHost
        handleServerHostChange()
    }

    func commitServerPort(_ input: String) {
        let sanitizedPort = sanitizedServerPort(input)
        guard sanitizedPort != serverPort else { return }
        serverPort = sanitizedPort
        handleServerPortChange()
    }

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

    var resolvedHost: String {
        serverHost.isEmpty ? (localIPAddress ?? "localhost") : serverHost
    }

    var serverBaseURL: String {
        var components = URLComponents()
        components.scheme = "http"
        components.host = normalizedURLHost(resolvedHost)
        components.port = serverPort

        if let url = components.string {
            return url
        }

        return "http://\(urlDisplayHost(resolvedHost)):\(serverPort)"
    }

    var feedURL: String {
        "\(serverBaseURL)/feed.xml"
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
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), let host = components.host?.lowercased() else {
            return trimmed
        }

        if host == "youtu.be" {
            let videoID = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !videoID.isEmpty {
                return "https://www.youtube.com/watch?v=\(videoID)"
            }
            return trimmed
        }

        let normalizedHost = host == "m.youtube.com" ? "www.youtube.com" : host
        components.scheme = "https"
        components.host = normalizedHost

        if let videoID = Self.extractDirectVideoID(from: components) {
            return "https://www.youtube.com/watch?v=\(videoID)"
        }

        var normalizedURL = components.string ?? trimmed
        if normalizedURL.contains("/@") && !normalizedURL.hasSuffix("/videos") && !normalizedURL.contains("/playlist") {
            normalizedURL = normalizedURL.hasSuffix("/") ? normalizedURL + "videos" : normalizedURL + "/videos"
        }
        return normalizedURL
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
        serverHost = Self.defaultServerHost
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

    private func sanitizedServerHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizedServerPort(_ port: String) -> Int {
        guard let parsedPort = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return Self.defaultServerPort
        }
        return sanitizedServerPort(parsedPort)
    }

    private func sanitizedServerPort(_ port: Int) -> Int {
        guard (1...65_535).contains(port) else {
            return Self.defaultServerPort
        }
        return port
    }

    private func normalizedURLHost(_ host: String) -> String {
        guard host.hasPrefix("["), host.hasSuffix("]"), host.count > 2 else {
            return host
        }
        return String(host.dropFirst().dropLast())
    }

    private func urlDisplayHost(_ host: String) -> String {
        let normalizedHost = normalizedURLHost(host)
        guard normalizedHost.contains(":") else {
            return normalizedHost
        }
        return "[\(normalizedHost)]"
    }

    private func videosForFetch(for channel: Channel) async throws -> [Downloader.VideoInfo] {
        switch channel.sourceKind {
        case .collection:
            return try await downloader.listVideos(channelURL: channel.url)
        case .singleEpisode:
            return [try await downloader.resolveVideoSource(url: channel.url).video]
        }
    }

    private func handleFetchedVideo(_ video: Downloader.VideoInfo, for channel: Channel) -> Bool {
        if let existingIndex = episodes.firstIndex(where: { $0.videoID == video.videoID }) {
            if episodes[existingIndex].channelID == channel.id {
                return false
            }

            if canMergeSingleEpisodeSource(at: existingIndex, into: channel) {
                episodes[existingIndex].channelID = channel.id
                pruneEmptySingleEpisodeSources()
            }
            return false
        }

        appendEpisodeIfNeeded(video, to: channel.id, markAsNew: true)
        return true
    }

    private func appendEpisodeIfNeeded(_ video: Downloader.VideoInfo, to channelID: UUID, markAsNew: Bool) {
        guard !episodes.contains(where: { $0.videoID == video.videoID }) else { return }
        var episode = Episode(
            channelID: channelID,
            videoID: video.videoID,
            title: video.title,
            publishDate: video.publishDate,
            durationSeconds: video.durationSeconds
        )
        episode.isNew = markAsNew
        episodes.append(episode)
    }

    private func canMergeSingleEpisodeSource(at episodeIndex: Int, into channel: Channel) -> Bool {
        guard channel.sourceKind == .collection else { return false }
        guard let sourceChannel = channels.first(where: { $0.id == episodes[episodeIndex].channelID }) else { return false }
        guard sourceChannel.sourceKind == .singleEpisode else { return false }
        return sourceChannel.relatedCollectionURL == channel.url
    }

    private func pruneEmptySingleEpisodeSources() {
        let channelIDsWithEpisodes = Set(episodes.map(\.channelID))
        channels.removeAll { channel in
            channel.isSingleEpisodeSource && !channelIDsWithEpisodes.contains(channel.id)
        }
    }

    private func resolvedYouTubeInput(for normalizedURL: String) -> ResolvedYouTubeInput? {
        if let components = URLComponents(string: normalizedURL),
           let videoID = Self.extractDirectVideoID(from: components) {
            return .singleVideo(url: normalizedURL, videoID: videoID)
        }

        guard let components = URLComponents(string: normalizedURL),
              let host = components.host?.lowercased(),
              host.contains("youtube.com"),
              !components.path.isEmpty else {
            return nil
        }

        return .collection(url: normalizedURL)
    }

    private static func extractDirectVideoID(from components: URLComponents) -> String? {
        let path = components.path

        if path == "/watch" {
            return components.queryItems?.first(where: { $0.name == "v" })?.value
        }

        for prefix in ["/shorts/", "/live/", "/embed/"] where path.hasPrefix(prefix) {
            let suffix = path.dropFirst(prefix.count)
            let videoID = suffix.split(separator: "/").first.map(String.init)
            if let videoID, !videoID.isEmpty {
                return videoID
            }
        }

        return nil
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
        let episodesDir = Paths.episodesDirectoryURL(in: outputDirectory)
        let feedFile = outputDirectory.appendingPathComponent("feed.xml")

        if isManagedFeed(at: feedFile) {
            try? fileManager.removeItem(at: feedFile)
        }

        removeManagedEpisodeArtifacts(for: episodes, channels: channels, in: outputDirectory)
        removeManagedEpisodesDirectoryIfEmptyAndOwned(at: episodesDir)
    }

    private func removeManagedEpisodeArtifacts(for episodes: [Episode], channels: [Channel], in outputDirectory: URL) {
        let fileManager = FileManager.default
        let episodesDir = Paths.episodesDirectoryURL(in: outputDirectory)
        guard fileManager.fileExists(atPath: episodesDir.path) else { return }

        let downloadedFileURLs = Set(
            episodes.compactMap { episode in
                episode.fileName.map { Paths.episodeFileURL(forRelativePath: $0, in: outputDirectory) }
            }
        )
        for fileURL in downloadedFileURLs {
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        let downloadedArtworkURLs = Set(
            episodes.compactMap { episode in
                episode.fileName.map { Paths.artworkURL(forEpisodeFileName: $0, in: outputDirectory) }
            }
        )
        for artworkURL in downloadedArtworkURLs {
            if fileManager.fileExists(atPath: artworkURL.path) {
                try? fileManager.removeItem(at: artworkURL)
            }
        }

        let channelsByID = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) })
        var managedPrefixesByDirectory: [URL: Set<String>] = [episodesDir: []]
        for episode in episodes {
            let prefix = String(episode.suggestedFileName.dropLast(4))
            managedPrefixesByDirectory[episodesDir, default: []].insert(prefix)
            if let channel = channelsByID[episode.channelID] {
                let channelDir = Paths.channelEpisodesDir(for: channel, in: outputDirectory)
                managedPrefixesByDirectory[channelDir, default: []].insert(prefix)
            }
        }

        for (directory, managedPrefixes) in managedPrefixesByDirectory {
            guard fileManager.fileExists(atPath: directory.path) else { continue }
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            ) else {
                continue
            }

            for url in contents where managedPrefixes.contains(where: { url.lastPathComponent.hasPrefix($0) }) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func removeManagedEpisodesDirectoryIfEmptyAndOwned(at episodesDir: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: episodesDir.path) else { return }
        removeEmptyManagedEpisodeSubdirectories(in: episodesDir)

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

    private func removeEmptyManagedEpisodeSubdirectories(in episodesDir: URL) {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: episodesDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in contents {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let childContents = (try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            guard childContents.isEmpty else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func isManagedFeed(at feedFile: URL) -> Bool {
        guard let content = try? String(contentsOf: feedFile, encoding: .utf8) else { return false }

        if content.contains(FeedGenerator.managedFeedMarker) {
            return true
        }

        return content.contains("<title>Recast</title>")
            && content.contains("<itunes:author>Recast</itunes:author>")
            && content.contains("<language>en</language>")
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
