import Foundation

enum Paths {
    private static let fm = FileManager.default

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

    static var ytDlpInBin: URL {
        binDir.appendingPathComponent("yt-dlp")
    }

    static var ffmpegInBin: URL {
        binDir.appendingPathComponent("ffmpeg")
    }
}
