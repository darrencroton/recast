import XCTest
@testable import Recast

final class FeedGeneratorTests: XCTestCase {

    private var outputDir: URL!

    override func setUpWithError() throws {
        outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecastTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        // Create episodes dir and a dummy MP3
        let episodesDir = outputDir.appendingPathComponent("episodes")
        try FileManager.default.createDirectory(at: episodesDir, withIntermediateDirectories: true)
        try Data("fake mp3 data".utf8).write(to: episodesDir.appendingPathComponent("vid1.mp3"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: outputDir)
    }

    private func makeChannel() -> Channel {
        Channel(url: "https://www.youtube.com/@test/videos", name: "Test Channel")
    }

    private func makeEpisode(channelID: UUID) -> Episode {
        var ep = Episode(
            channelID: channelID,
            videoID: "vid1",
            title: "Test Episode & <Special>",
            publishDate: Date(timeIntervalSince1970: 1700000000),
            durationSeconds: 3661
        )
        ep.fileName = "vid1.mp3"
        return ep
    }

    func testWritesFeedFile() {
        let ch = makeChannel()
        let ep = makeEpisode(channelID: ch.id)
        FeedGenerator.write(episodes: [ep], channels: [ch], baseURL: "http://localhost:8888", to: outputDir)

        let feedPath = outputDir.appendingPathComponent("feed.xml")
        XCTAssertTrue(FileManager.default.fileExists(atPath: feedPath.path))
    }

    func testFeedContainsRSSElements() throws {
        let ch = makeChannel()
        let ep = makeEpisode(channelID: ch.id)
        FeedGenerator.write(episodes: [ep], channels: [ch], baseURL: "http://localhost:8888", to: outputDir)

        let feedPath = outputDir.appendingPathComponent("feed.xml")
        let content = try String(contentsOf: feedPath, encoding: .utf8)

        XCTAssertTrue(content.contains("<rss"))
        XCTAssertTrue(content.contains("xmlns:itunes"))
        XCTAssertTrue(content.contains("<title>Recast</title>"))
        XCTAssertTrue(content.contains("<item>"))
        XCTAssertTrue(content.contains("<enclosure"))
        XCTAssertTrue(content.contains("audio/mpeg"))
        XCTAssertTrue(content.contains("<guid"))
        XCTAssertTrue(content.contains("vid1"))
    }

    func testFeedXMLEscaping() throws {
        let ch = makeChannel()
        let ep = makeEpisode(channelID: ch.id) // title has & and < >
        FeedGenerator.write(episodes: [ep], channels: [ch], baseURL: "http://localhost:8888", to: outputDir)

        let feedPath = outputDir.appendingPathComponent("feed.xml")
        let content = try String(contentsOf: feedPath, encoding: .utf8)

        XCTAssertTrue(content.contains("&amp;"))
        XCTAssertTrue(content.contains("&lt;Special&gt;"))
        XCTAssertFalse(content.contains("& <Special>"))
    }

    func testFeedDuration() throws {
        let ch = makeChannel()
        let ep = makeEpisode(channelID: ch.id) // 3661 seconds = 01:01:01
        FeedGenerator.write(episodes: [ep], channels: [ch], baseURL: "http://localhost:8888", to: outputDir)

        let feedPath = outputDir.appendingPathComponent("feed.xml")
        let content = try String(contentsOf: feedPath, encoding: .utf8)

        XCTAssertTrue(content.contains("<itunes:duration>01:01:01</itunes:duration>"))
    }

    func testFeedBaseURL() throws {
        let ch = makeChannel()
        let ep = makeEpisode(channelID: ch.id)
        FeedGenerator.write(episodes: [ep], channels: [ch], baseURL: "http://192.168.1.5:9090", to: outputDir)

        let feedPath = outputDir.appendingPathComponent("feed.xml")
        let content = try String(contentsOf: feedPath, encoding: .utf8)

        XCTAssertTrue(content.contains("http://192.168.1.5:9090/episodes/vid1.mp3"))
    }

    func testFeedExcludesUndownloaded() {
        let ch = makeChannel()
        let downloaded = makeEpisode(channelID: ch.id)
        let undownloaded = Episode(
            channelID: ch.id, videoID: "vid2", title: "Not Downloaded",
            publishDate: .now, durationSeconds: 60
        )
        FeedGenerator.write(episodes: [downloaded, undownloaded], channels: [ch],
                            baseURL: "http://localhost:8888", to: outputDir)

        let feedPath = outputDir.appendingPathComponent("feed.xml")
        let content = (try? String(contentsOf: feedPath, encoding: .utf8)) ?? ""

        // Only the downloaded episode should appear (FeedGenerator only receives downloaded eps,
        // but even if passed undownloaded, items with nil fileName are skipped)
        XCTAssertTrue(content.contains("vid1"))
        XCTAssertFalse(content.contains("vid2"))
    }

    func testEmptyFeed() {
        let ch = makeChannel()
        FeedGenerator.write(episodes: [], channels: [ch], baseURL: "http://localhost:8888", to: outputDir)

        let feedPath = outputDir.appendingPathComponent("feed.xml")
        let content = (try? String(contentsOf: feedPath, encoding: .utf8)) ?? ""

        XCTAssertTrue(content.contains("<rss"))
        XCTAssertFalse(content.contains("<item>"))
    }
}
