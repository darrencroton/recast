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
        XCTAssertFalse(ep.isNew)
        XCTAssertFalse(ep.isPendingAutoDownload)
        XCTAssertNil(ep.lastAutoDownloadAttemptAt)
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
            "isNew": false,
            "fileName": "testVid.mp3"
        }
        """
        let data = json.data(using: .utf8)!
        let ep = try JSONDecoder().decode(Episode.self, from: data)
        XCTAssertTrue(ep.isPlayed)
        XCTAssertFalse(ep.isNew)
        XCTAssertTrue(ep.isDownloaded)
        XCTAssertEqual(ep.fileName, "testVid.mp3")
    }

    func testEpisodeDecodesWithIsNew() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "channelID": "22222222-2222-2222-2222-222222222222",
            "videoID": "freshVid",
            "title": "Fresh Episode",
            "publishDate": 0,
            "durationSeconds": 300,
            "isPlayed": false,
            "isNew": true
        }
        """
        let data = json.data(using: .utf8)!
        let ep = try JSONDecoder().decode(Episode.self, from: data)
        XCTAssertTrue(ep.isNew)
    }

    func testEpisodeDecodesWithoutPendingAutoDownload_defaultsToFalse() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "channelID": "22222222-2222-2222-2222-222222222222",
            "videoID": "legacyVid",
            "title": "Legacy Episode",
            "publishDate": 0,
            "durationSeconds": 300,
            "isPlayed": false,
            "isNew": true
        }
        """
        let data = json.data(using: .utf8)!
        let ep = try JSONDecoder().decode(Episode.self, from: data)
        XCTAssertFalse(ep.isPendingAutoDownload)
        XCTAssertNil(ep.lastAutoDownloadAttemptAt)
    }

    func testEpisodeDecodesWithPendingAutoDownload() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "channelID": "22222222-2222-2222-2222-222222222222",
            "videoID": "retryVid",
            "title": "Retry Episode",
            "publishDate": 0,
            "durationSeconds": 300,
            "isPlayed": false,
            "isNew": false,
            "isPendingAutoDownload": true
        }
        """
        let data = json.data(using: .utf8)!
        let ep = try JSONDecoder().decode(Episode.self, from: data)
        XCTAssertTrue(ep.isPendingAutoDownload)
    }

    func testEpisodeDecodesWithoutLastAutoDownloadAttempt_defaultsToNil() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "channelID": "22222222-2222-2222-2222-222222222222",
            "videoID": "pendingVid",
            "title": "Pending Episode",
            "publishDate": 0,
            "durationSeconds": 300,
            "isPendingAutoDownload": true
        }
        """

        let ep = try JSONDecoder().decode(Episode.self, from: Data(json.utf8))

        XCTAssertNil(ep.lastAutoDownloadAttemptAt)
    }

    func testEpisodeRoundTrip() throws {
        var ep = Episode(
            channelID: UUID(), videoID: "rt1", title: "Round Trip",
            publishDate: Date(timeIntervalSince1970: 1000), durationSeconds: 600
        )
        ep.isPlayed = true
        ep.fileName = "rt1.mp3"
        ep.isNew = true
        ep.isPendingAutoDownload = true
        ep.lastAutoDownloadAttemptAt = Date(timeIntervalSince1970: 2000)

        let data = try JSONEncoder().encode(ep)
        let decoded = try JSONDecoder().decode(Episode.self, from: data)
        XCTAssertEqual(decoded.videoID, ep.videoID)
        XCTAssertEqual(decoded.title, ep.title)
        XCTAssertEqual(decoded.isPlayed, true)
        XCTAssertEqual(decoded.isNew, true)
        XCTAssertEqual(decoded.isPendingAutoDownload, true)
        XCTAssertEqual(decoded.fileName, "rt1.mp3")
        XCTAssertEqual(decoded.lastAutoDownloadAttemptAt, ep.lastAutoDownloadAttemptAt)
    }

    // MARK: - Channel

    func testChannelInit() {
        let ch = Channel(url: "https://www.youtube.com/@test/videos", name: "Test")
        XCTAssertEqual(ch.name, "Test")
        XCTAssertEqual(ch.url, "https://www.youtube.com/@test/videos")
        XCTAssertNotNil(ch.id)
        XCTAssertFalse(ch.hasCompletedInitialImport)
    }

    func testChannelCodableRoundTrip() throws {
        let ch = Channel(url: "https://www.youtube.com/@ch/videos", name: "My Channel")
        let data = try JSONEncoder().encode(ch)
        let decoded = try JSONDecoder().decode(Channel.self, from: data)
        XCTAssertEqual(decoded.id, ch.id)
        XCTAssertEqual(decoded.url, ch.url)
        XCTAssertEqual(decoded.name, ch.name)
        XCTAssertEqual(decoded.sourceKind, .collection)
        XCTAssertFalse(decoded.hasCompletedInitialImport)
    }

    func testChannelCodableRoundTrip_preservesSingleEpisodeMetadata() throws {
        let channel = Channel(
            url: "https://www.youtube.com/watch?v=abc123",
            name: "Example Creator",
            sourceKind: .singleEpisode,
            relatedCollectionURL: "https://www.youtube.com/@creator/videos"
        )

        let data = try JSONEncoder().encode(channel)
        let decoded = try JSONDecoder().decode(Channel.self, from: data)

        XCTAssertEqual(decoded.sourceKind, .singleEpisode)
        XCTAssertEqual(decoded.relatedCollectionURL, "https://www.youtube.com/@creator/videos")
        XCTAssertTrue(decoded.hasCompletedInitialImport)
    }

    func testCollectionChannelDecodesWithoutInitialImportFlag_defaultsToFalse() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "url": "https://www.youtube.com/@test/videos",
            "name": "Test",
            "dateAdded": 0,
            "sourceKind": "collection"
        }
        """

        let decoded = try JSONDecoder().decode(Channel.self, from: Data(json.utf8))

        XCTAssertFalse(decoded.hasCompletedInitialImport)
    }

    func testSingleEpisodeChannelDecodesWithoutInitialImportFlag_defaultsToTrue() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "url": "https://www.youtube.com/watch?v=abc123",
            "name": "Test",
            "dateAdded": 0,
            "sourceKind": "singleEpisode"
        }
        """

        let decoded = try JSONDecoder().decode(Channel.self, from: Data(json.utf8))

        XCTAssertTrue(decoded.hasCompletedInitialImport)
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

    func testParseVideoListOutput_parsesCompleteRows() {
        let output = """
        abc123\tEpisode One\t20260329\t1743206400\t\t300
        def456\tEpisode Two\t\t1743120000\t\t125
        """

        let videos = Downloader.parseVideoListOutput(output)

        XCTAssertEqual(videos.count, 2)
        XCTAssertEqual(videos[0].videoID, "abc123")
        XCTAssertEqual(videos[0].title, "Episode One")
        XCTAssertEqual(Episode.fileDatePrefix(for: videos[0].publishDate), "2026-03-29")
        XCTAssertEqual(videos[1].videoID, "def456")
        XCTAssertEqual(videos[1].durationSeconds, 125)
    }

    func testParseVideoListOutput_parsesDecimalDurationsFromFlatPlaylist() {
        let output = """
        abc123\tEpisode One\t20260329\t1743206400\t\t300.0
        """

        let videos = Downloader.parseVideoListOutput(output)

        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(videos[0].durationSeconds, 300)
    }

    func testParseVideoListOutput_skipsMalformedRows() {
        let output = """
        abc123\tEpisode One\t20260329\t1743206400\t\t300
        malformed row
        """

        let videos = Downloader.parseVideoListOutput(output)

        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(videos[0].videoID, "abc123")
    }

    func testParseDownloadProgress_readsPercentFromYtDlpLine() {
        let progress = Downloader.parseDownloadProgress(from: "[download]  42.3% of  100.00MiB at 10.00MiB/s ETA 00:06")
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress!, 0.423, accuracy: 0.0001)
    }

    func testParseConversionProgress_readsFfmpegTimeAgainstDuration() {
        let progress = Downloader.parseConversionProgress(
            from: "size=    512kB time=00:01:30.00 bitrate=  46.6kbits/s speed=1.5x",
            durationSeconds: 180
        )
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress!, 0.5, accuracy: 0.0001)
    }

    func testMapPhaseProgress_scalesIntoSuppliedRange() {
        let progress = Downloader.mapPhaseProgress(0.5, into: 0.18 ... 0.58)
        XCTAssertEqual(progress, 0.38, accuracy: 0.0001)
    }

    func testEstimatedConversionFraction_growsOverTimeAndStaysBounded() {
        let progress = Downloader.estimatedConversionFraction(elapsed: 12, durationSeconds: 600)
        XCTAssertGreaterThan(progress, 0.0)
        XCTAssertLessThan(progress, 0.95)
    }

    func testDownloadPhaseLabel_convertingAudio() {
        XCTAssertEqual(DownloadPhase.convertingAudio.label, "Converting to MP3")
    }

    func testDownloadPhaseLabel_queued() {
        XCTAssertEqual(DownloadPhase.queued.label, "Queued for download")
    }
}
