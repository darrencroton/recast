import XCTest
@testable import Recast

final class PathsTests: XCTestCase {

    func testAppSupportExists() {
        let dir = Paths.appSupport
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func testBinDirInsideAppSupport() {
        let bin = Paths.binDir
        XCTAssertTrue(bin.path.contains("Recast"))
        XCTAssertTrue(bin.path.hasSuffix("bin"))
    }

    func testStateFileInsideAppSupport() {
        let state = Paths.stateFile
        XCTAssertTrue(state.path.contains("Recast"))
        XCTAssertTrue(state.lastPathComponent == "state.json")
    }

    func testDefaultOutputDir() {
        let dir = Paths.defaultOutputDir
        XCTAssertTrue(dir.path.contains("Recast"))
    }

    func testEpisodesDirCreated() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecastPathsTest-\(UUID().uuidString)")
        let episodes = Paths.episodesDir(in: tmpDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: episodes.path))
        XCTAssertTrue(episodes.lastPathComponent == "episodes")
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testYtDlpInBin() {
        XCTAssertTrue(Paths.ytDlpInBin.lastPathComponent == "yt-dlp")
        XCTAssertTrue(Paths.ytDlpInBin.path.contains("bin"))
    }

    func testFfmpegInBin() {
        XCTAssertTrue(Paths.ffmpegInBin.lastPathComponent == "ffmpeg")
        XCTAssertTrue(Paths.ffmpegInBin.path.contains("bin"))
    }
}
