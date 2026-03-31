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
    var activeDownloads: Set<String> = []  // videoIDs currently downloading

    // Dependencies
    var ytDlpReady = false
    var ffmpegReady = false
    var isInstallingDeps = false

    let downloader = Downloader()
    private var server: PodcastServer?

    // MARK: - Init

    init() {
        load()
        Task { await checkDependencies() }
    }

    // MARK: - Persistence

    private struct PersistentState: Codable {
        var channels: [Channel]
        var episodes: [Episode]
        var outputDirectory: String
        var serverPort: Int
    }

    func save() {
        let state = PersistentState(
            channels: channels,
            episodes: episodes,
            outputDirectory: outputDirectory.path,
            serverPort: serverPort
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: Paths.stateFile)
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: Paths.stateFile),
              let state = try? JSONDecoder().decode(PersistentState.self, from: data)
        else { return }
        channels = state.channels
        episodes = state.episodes
        outputDirectory = URL(fileURLWithPath: state.outputDirectory)
        serverPort = state.serverPort
    }

    // MARK: - Dependency management

    func checkDependencies() async {
        ytDlpReady = await downloader.hasYtDlp
        ffmpegReady = await downloader.hasFfmpeg
    }

    func installDependencies() async {
        isInstallingDeps = true
        statusMessage = "Installing yt-dlp…"
        do {
            if !ytDlpReady {
                try await downloader.installYtDlp()
                ytDlpReady = true
            }
            statusMessage = "Installing ffmpeg…"
            if !ffmpegReady {
                try await downloader.installFfmpeg()
                ffmpegReady = true
            }
            statusMessage = "Ready"
        } catch {
            statusMessage = "Setup failed: \(error.localizedDescription)"
        }
        isInstallingDeps = false
    }

    // MARK: - Channel management

    func addChannel(url: String) async throws {
        let cleaned = normalizeYouTubeURL(url)
        guard !channels.contains(where: { $0.url == cleaned }) else { return }
        statusMessage = "Resolving channel…"
        let name = try await downloader.resolveChannelName(url: cleaned)
        let channel = Channel(url: cleaned, name: name)
        channels.append(channel)
        save()
        statusMessage = "Added \(name)"
    }

    func removeChannels(_ ids: Set<UUID>) {
        episodes.removeAll { ids.contains($0.channelID) }
        channels.removeAll { ids.contains($0.id) }
        save()
        regenerateFeed()
    }

    // MARK: - Fetch & download

    func fetchNewEpisodes(for channelIDs: Set<UUID>) async {
        guard !isFetching else { return }
        isFetching = true
        let targets = channelIDs.isEmpty ? channels : channels.filter { channelIDs.contains($0.id) }

        let episodesDir = Paths.episodesDir(in: outputDirectory)
        var totalNew = 0

        for channel in targets {
            statusMessage = "Checking \(channel.name)…"
            do {
                let videos = try await downloader.listVideos(channelURL: channel.url)
                let knownIDs = Set(episodes.filter { $0.channelID == channel.id }.map(\.videoID))

                for video in videos where !knownIDs.contains(video.videoID) {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd"
                    let pubDate = df.date(from: video.uploadDate) ?? .now

                    var ep = Episode(
                        channelID: channel.id,
                        videoID: video.videoID,
                        title: video.title,
                        publishDate: pubDate,
                        durationSeconds: video.durationSeconds
                    )
                    episodes.append(ep)
                    save()

                    statusMessage = "Downloading: \(video.title.prefix(50))…"
                    activeDownloads.insert(video.videoID)
                    do {
                        let fileName = try await downloader.downloadAudio(
                            videoID: video.videoID, to: episodesDir
                        )
                        if let idx = episodes.firstIndex(where: { $0.videoID == video.videoID }) {
                            episodes[idx].fileName = fileName
                        }
                        totalNew += 1
                    } catch {
                        statusMessage = "Failed: \(video.title.prefix(40)) — \(error.localizedDescription)"
                    }
                    activeDownloads.remove(video.videoID)
                    save()
                }
            } catch {
                statusMessage = "Error on \(channel.name): \(error.localizedDescription)"
            }
        }

        regenerateFeed()
        statusMessage = totalNew > 0 ? "Fetched \(totalNew) new episode(s)" : "No new episodes"
        isFetching = false
    }

    // MARK: - Feed

    func regenerateFeed() {
        let baseURL = "http://localhost:\(serverPort)"
        let downloaded = episodes.filter(\.isDownloaded)
            .sorted { $0.publishDate > $1.publishDate }
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
        } catch {
            statusMessage = "Server failed: \(error.localizedDescription)"
        }
    }

    func stopServer() {
        server?.stop()
        server = nil
        isServerRunning = false
        statusMessage = "Server stopped"
    }

    // MARK: - Helpers

    func episodes(for channelID: UUID) -> [Episode] {
        episodes.filter { $0.channelID == channelID }
            .sorted { $0.publishDate > $1.publishDate }
    }

    func normalizeYouTubeURL(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        // Convert mobile URLs to desktop
        u = u.replacingOccurrences(of: "https://m.youtube.com", with: "https://www.youtube.com")
        // Ensure /videos suffix for channel pages
        if u.contains("/@") && !u.hasSuffix("/videos") && !u.contains("/playlist") {
            u = u.hasSuffix("/") ? u + "videos" : u + "/videos"
        }
        return u
    }
}
