import Foundation

enum Paths {
    private static let fm = FileManager.default
    static let managedEpisodesMarkerFileName = ".recast-owned"
    static let showArtworkFileName = "show-cover.jpg"
    static let feedAssetsDirectoryName = "feed-assets"
    static let serverDirectoryName = "server"

    static var appSupport: URL {
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Recast", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var binDir: URL {
        let dir = appSupport.appendingPathComponent("bin", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var stateFile: URL {
        appSupport.appendingPathComponent("state.json")
    }

    static var logsDir: URL {
        let dir = appSupport.appendingPathComponent("logs", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var logFile: URL {
        logsDir.appendingPathComponent("recast.log")
    }

    static var defaultEpisodesDir: URL {
        let music = fm.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Music")
        return music.appendingPathComponent("Recast", isDirectory: true)
    }

    static func serverDirectory(in appSupportDir: URL) -> URL {
        let dir = appSupportDir.appendingPathComponent(serverDirectoryName, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func episodesDirectoryURL(in episodesDir: URL) -> URL {
        episodesDir
    }

    static func episodesDir(in episodesDir: URL) -> URL {
        let dir = episodesDirectoryURL(in: episodesDir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func managedEpisodesMarker(in episodesDir: URL) -> URL {
        episodesDirectoryURL(in: episodesDir)
            .appendingPathComponent(managedEpisodesMarkerFileName)
    }

    static func ensureManagedEpisodesDirectory(in episodesDir: URL) -> URL {
        let dir = self.episodesDir(in: episodesDir)
        let marker = managedEpisodesMarker(in: episodesDir)
        if !fm.fileExists(atPath: marker.path) {
            fm.createFile(atPath: marker.path, contents: Data())
        }
        return dir
    }

    static func channelDirectoryName(for channel: Channel) -> String {
        let readableName = Episode.sanitizedFileComponent(from: channel.name, fallback: "Channel")
        let idSuffix = String(channel.id.uuidString.lowercased().prefix(8))
        return "\(readableName) [\(idSuffix)]"
    }

    static func channelEpisodesDir(for channel: Channel, in episodesDir: URL) -> URL {
        episodesDirectoryURL(in: episodesDir)
            .appendingPathComponent(channelDirectoryName(for: channel), isDirectory: true)
    }

    static func ensureManagedChannelEpisodesDirectory(for channel: Channel, in episodesDir: URL) -> URL {
        _ = ensureManagedEpisodesDirectory(in: episodesDir)
        let dir = channelEpisodesDir(for: channel, in: episodesDir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func relativeEpisodePath(forFileName fileName: String, in channel: Channel) -> String {
        let channelDir = channelDirectoryName(for: channel)
        return URL(fileURLWithPath: channelDir, isDirectory: true)
            .appendingPathComponent(fileName)
            .path
    }

    static func episodeFileURL(forRelativePath relativePath: String, in episodesDir: URL) -> URL {
        episodesDirectoryURL(in: episodesDir).appendingPathComponent(relativePath)
    }

    static func legacyArtworkURL(forEpisodeFileName fileName: String, in episodesDir: URL) -> URL {
        episodeFileURL(
            forRelativePath: Episode.artworkFileName(forEpisodeFileName: fileName),
            in: episodesDir
        )
    }

    static func feedFileURL(in feedDir: URL) -> URL {
        feedDir.appendingPathComponent("feed.xml")
    }

    static func showArtworkURL(in feedDir: URL) -> URL {
        feedDir.appendingPathComponent(showArtworkFileName)
    }

    static func feedAssetsDirectoryURL(in feedDir: URL) -> URL {
        feedDir.appendingPathComponent(feedAssetsDirectoryName, isDirectory: true)
    }

    static func ensureFeedAssetsDirectory(in feedDir: URL) -> URL {
        let dir = feedAssetsDirectoryURL(in: feedDir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func feedAudioFileName(forVideoID videoID: String) -> String {
        "\(videoID).mp3"
    }

    static func feedArtworkFileName(forVideoID videoID: String) -> String {
        "\(videoID).jpg"
    }

    static func feedAudioURL(forVideoID videoID: String, in feedDir: URL) -> URL {
        feedAssetsDirectoryURL(in: feedDir).appendingPathComponent(feedAudioFileName(forVideoID: videoID))
    }

    static func feedArtworkURL(forVideoID videoID: String, in feedDir: URL) -> URL {
        feedAssetsDirectoryURL(in: feedDir).appendingPathComponent(feedArtworkFileName(forVideoID: videoID))
    }

    static var ytDlpInBin: URL {
        binDir.appendingPathComponent("yt-dlp")
    }

    static var ffmpegInBin: URL {
        binDir.appendingPathComponent("ffmpeg")
    }
}
