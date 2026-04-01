import XCTest
@testable import Recast

final class ModelTests: XCTestCase {

    // MARK: - Episode

    func testEpisodeInit() {
        let ep = Episode(
            channelID: UUID(),
            videoID: "abc123",
            title: "Test Video",
            publishDate: Date(timeIntervalSince1970: 0),
            durationSeconds: 3661
        )
        XCTAssertEqual(ep.videoID, "abc123")
        XCTAssertEqual(ep.title, "Test Video")
        XCTAssertNil(ep.fileName)
        XCTAssertFalse(ep.isDownloaded)
        XCTAssertFalse(ep.isPlayed)
    }

    func testEpisodeIsDownloaded() {
        var ep = Episode(
            channelID: UUID(), videoID: "v1", title: "T",
            publishDate: .now, durationSeconds: 60
        )
        XCTAssertFalse(ep.isDownloaded)
        ep.fileName = "v1.mp3"
        XCTAssertTrue(ep.isDownloaded)
    }

    func testFormattedDurationShort() {
        let ep = Episode(
            channelID: UUID(), videoID: "v", title: "T",
            publishDate: .now, durationSeconds: 125 // 2:05
        )
        XCTAssertEqual(ep.formattedDuration, "2:05")
    }

    func testFormattedDurationLong() {
        let ep = Episode(
            channelID: UUID(), videoID: "v", title: "T",
            publishDate: .now, durationSeconds: 3661 // 1:01:01
        )
        XCTAssertEqual(ep.formattedDuration, "1:01:01")
    }

    func testFormattedDurationZero() {
        let ep = Episode(
            channelID: UUID(), videoID: "v", title: "T",
            publishDate: .now, durationSeconds: 0
        )
        XCTAssertEqual(ep.formattedDuration, "0:00")
    }

    func testSuggestedFileName_includesDateTitleAndVideoID() {
        let episode = Episode(
            channelID: UUID(),
            videoID: "abc123",
            title: "Meaningful Episode Title",
            publishDate: Date(timeIntervalSince1970: 0),
            durationSeconds: 60
        )
        XCTAssertEqual(episode.suggestedFileName, "1970-01-01 - Meaningful Episode Title [abc123].mp3")
    }

    func testSuggestedFileName_sanitizesFilesystemUnsafeCharacters() {
        let episode = Episode(
            channelID: UUID(),
            videoID: "safe42",
            title: #"A/B:C*D?"#,
            publishDate: Date(timeIntervalSince1970: 0),
            durationSeconds: 60
        )
        XCTAssertEqual(episode.suggestedFileName, "1970-01-01 - A B C D [safe42].mp3")
    }

    // MARK: - Episode Codable (backwards compatibility)

    func testEpisodeDecodesWithoutIsPlayed() throws {
        // Simulates old state.json without isPlayed field
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "channelID": "22222222-2222-2222-2222-222222222222",
            "videoID": "testVid",
            "title": "Old Episode",
            "publishDate": 0,
            "durationSeconds": 300
        }
        """
        let data = json.data(using: .utf8)!
        let ep = try JSONDecoder().decode(Episode.self, from: data)
        XCTAssertEqual(ep.videoID, "testVid")
        XCTAssertFalse(ep.isPlayed) // defaults to false
        XCTAssertNil(ep.fileName)
    }

    func testEpisodeDecodesWithIsPlayed() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "channelID": "22222222-2222-2222-2222-222222222222",
            "videoID": "testVid",
            "title": "Played Episode",
            "publishDate": 0,
            "durationSeconds": 300,
            "isPlayed": true,
            "fileName": "testVid.mp3"
        }
        """
        let data = json.data(using: .utf8)!
        let ep = try JSONDecoder().decode(Episode.self, from: data)
        XCTAssertTrue(ep.isPlayed)
        XCTAssertTrue(ep.isDownloaded)
        XCTAssertEqual(ep.fileName, "testVid.mp3")
    }

    func testEpisodeRoundTrip() throws {
        var ep = Episode(
            channelID: UUID(), videoID: "rt1", title: "Round Trip",
            publishDate: Date(timeIntervalSince1970: 1000), durationSeconds: 600
        )
        ep.isPlayed = true
        ep.fileName = "rt1.mp3"

        let data = try JSONEncoder().encode(ep)
        let decoded = try JSONDecoder().decode(Episode.self, from: data)
        XCTAssertEqual(decoded.videoID, ep.videoID)
        XCTAssertEqual(decoded.title, ep.title)
        XCTAssertEqual(decoded.isPlayed, true)
        XCTAssertEqual(decoded.fileName, "rt1.mp3")
    }

    // MARK: - Channel

    func testChannelInit() {
        let ch = Channel(url: "https://www.youtube.com/@test/videos", name: "Test")
        XCTAssertEqual(ch.name, "Test")
        XCTAssertEqual(ch.url, "https://www.youtube.com/@test/videos")
        XCTAssertNotNil(ch.id)
    }

    func testChannelCodableRoundTrip() throws {
        let ch = Channel(url: "https://www.youtube.com/@ch/videos", name: "My Channel")
        let data = try JSONEncoder().encode(ch)
        let decoded = try JSONDecoder().decode(Channel.self, from: data)
        XCTAssertEqual(decoded.id, ch.id)
        XCTAssertEqual(decoded.url, ch.url)
        XCTAssertEqual(decoded.name, ch.name)
    }

    func testPublishedDate_prefersUploadDate() {
        let date = Downloader.publishedDate(
            uploadDate: "20260329",
            timestamp: "1743206400",
            releaseTimestamp: ""
        )
        XCTAssertEqual(Episode.fileDatePrefix(for: date), "2026-03-29")
    }

    func testPublishedDate_fallsBackToTimestamp() {
        let date = Downloader.publishedDate(
            uploadDate: "",
            timestamp: "1743206400",
            releaseTimestamp: ""
        )
        XCTAssertEqual(Episode.fileDatePrefix(for: date), "2025-03-29")
    }
}
