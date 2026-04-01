import Foundation

enum Paths {
    private static let fm = FileManager.default
    static let managedEpisodesMarkerFileName = ".recast-owned"

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

    static func episodesDir(in outputDir: URL) -> URL {
        let dir = outputDir.appendingPathComponent("episodes", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func managedEpisodesMarker(in outputDir: URL) -> URL {
        outputDir
            .appendingPathComponent("episodes", isDirectory: true)
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

    static func artworkURL(forEpisodeFileName fileName: String, in outputDir: URL) -> URL {
        episodesDir(in: outputDir).appendingPathComponent(Episode.artworkFileName(forEpisodeFileName: fileName))
    }

    static var ytDlpInBin: URL {
        binDir.appendingPathComponent("yt-dlp")
    }

    static var ffmpegInBin: URL {
        binDir.appendingPathComponent("ffmpeg")
    }
}
