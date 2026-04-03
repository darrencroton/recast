import Foundation

enum Paths {
    private static let fm = FileManager.default
    static let managedEpisodesMarkerFileName = ".recast-owned"
    static let showArtworkFileName = "show-cover.jpg"
    static let feedAssetsDirectoryName = "feed-assets"

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

    static var defaultOutputDir: URL {
        let music = fm.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Music")
        return music.appendingPathComponent("Recast", isDirectory: true)
    }

    static func episodesDirectoryURL(in outputDir: URL) -> URL {
        outputDir.appendingPathComponent("episodes", isDirectory: true)
    }

    static func episodesDir(in outputDir: URL) -> URL {
        let dir = episodesDirectoryURL(in: outputDir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func managedEpisodesMarker(in outputDir: URL) -> URL {
        episodesDirectoryURL(in: outputDir)
            .appendingPathComponent(managedEpisodesMarkerFileName)
    }

    static func ensureManagedEpisodesDirectory(in outputDir: URL) -> URL {
        let dir = episodesDir(in: outputDir)
        let marker = managedEpisodesMarker(in: outputDir)
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

    static func channelEpisodesDir(for channel: Channel, in outputDir: URL) -> URL {
        episodesDirectoryURL(in: outputDir)
            .appendingPathComponent(channelDirectoryName(for: channel), isDirectory: true)
    }

    static func ensureManagedChannelEpisodesDirectory(for channel: Channel, in outputDir: URL) -> URL {
        _ = ensureManagedEpisodesDirectory(in: outputDir)
        let dir = channelEpisodesDir(for: channel, in: outputDir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func relativeEpisodePath(forFileName fileName: String, in channel: Channel) -> String {
        let channelDir = channelDirectoryName(for: channel)
        return URL(fileURLWithPath: channelDir, isDirectory: true)
            .appendingPathComponent(fileName)
            .path
    }

    static func episodeFileURL(forRelativePath relativePath: String, in outputDir: URL) -> URL {
        episodesDirectoryURL(in: outputDir).appendingPathComponent(relativePath)
    }

    static func legacyArtworkURL(forEpisodeFileName fileName: String, in outputDir: URL) -> URL {
        episodeFileURL(
            forRelativePath: Episode.artworkFileName(forEpisodeFileName: fileName),
            in: outputDir
        )
    }

    static func showArtworkURL(in outputDir: URL) -> URL {
        outputDir.appendingPathComponent(showArtworkFileName)
    }

    static func feedAssetsDirectoryURL(in outputDir: URL) -> URL {
        outputDir.appendingPathComponent(feedAssetsDirectoryName, isDirectory: true)
    }

    static func ensureFeedAssetsDirectory(in outputDir: URL) -> URL {
        let dir = feedAssetsDirectoryURL(in: outputDir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func feedAudioFileName(forVideoID videoID: String) -> String {
        "\(videoID).mp3"
    }

    static func feedArtworkFileName(forVideoID videoID: String) -> String {
        "\(videoID).jpg"
    }

    static func feedAudioURL(forVideoID videoID: String, in outputDir: URL) -> URL {
        feedAssetsDirectoryURL(in: outputDir).appendingPathComponent(feedAudioFileName(forVideoID: videoID))
    }

    static func feedArtworkURL(forVideoID videoID: String, in outputDir: URL) -> URL {
        feedAssetsDirectoryURL(in: outputDir).appendingPathComponent(feedArtworkFileName(forVideoID: videoID))
    }

    static var ytDlpInBin: URL {
        binDir.appendingPathComponent("yt-dlp")
    }

    static var ffmpegInBin: URL {
        binDir.appendingPathComponent("ffmpeg")
    }
}
