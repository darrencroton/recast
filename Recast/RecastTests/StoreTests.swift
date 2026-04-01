import XCTest
@testable import Recast

final class StoreTests: XCTestCase {

    private var store: AppStore!
    private var tempDir: URL!
    private var tempStateFile: URL!

    // MARK: - Setup / teardown

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempStateFile = tempDir.appendingPathComponent("state.json")
        store = AppStore(
            stateFileURL: tempStateFile,
            shouldLoadPersistentState: false,
            autoCheckDependencies: false
        )
        store.outputDirectory = tempDir
        store.channels = []
        store.episodes = []
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeChannel(name: String = "Test", urlHandle: String = "test") -> Channel {
        Channel(url: "https://www.youtube.com/@\(urlHandle)/videos", name: name)
    }

    private func makeEpisode(channelID: UUID, videoID: String, daysAgo: Int = 0, fileName: String? = nil) -> Episode {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        var ep = Episode(
            channelID: channelID,
            videoID: videoID,
            title: videoID,
            publishDate: date,
            durationSeconds: 120
        )
        ep.fileName = fileName
        return ep
    }

    // MARK: - normalizeYouTubeURL: mobile → desktop

    func test_normalize_mobileScheme_convertedToDesktop() {
        let result = store.normalizeYouTubeURL("https://m.youtube.com/@channel/videos")
        XCTAssertEqual(result, "https://www.youtube.com/@channel/videos")
    }

    func test_normalize_mobileHandle_convertedAndSuffixed() {
        let result = store.normalizeYouTubeURL("https://m.youtube.com/@science")
        XCTAssertEqual(result, "https://www.youtube.com/@science/videos")
    }

    // MARK: - normalizeYouTubeURL: /videos suffix

    func test_normalize_handleWithoutSuffix_suffixAppended() {
        let result = store.normalizeYouTubeURL("https://www.youtube.com/@science")
        XCTAssertEqual(result, "https://www.youtube.com/@science/videos")
    }

    func test_normalize_handleWithTrailingSlash_suffixAppended() {
        let result = store.normalizeYouTubeURL("https://www.youtube.com/@science/")
        XCTAssertEqual(result, "https://www.youtube.com/@science/videos")
    }

    func test_normalize_handleAlreadyHasSuffix_unchanged() {
        let result = store.normalizeYouTubeURL("https://www.youtube.com/@science/videos")
        XCTAssertEqual(result, "https://www.youtube.com/@science/videos")
    }

    // MARK: - normalizeYouTubeURL: playlist URLs unchanged

    func test_normalize_playlistURL_noSuffixAdded() {
        let url = "https://www.youtube.com/playlist?list=PLabc123"
        XCTAssertFalse(store.normalizeYouTubeURL(url).contains("/videos"), "Playlist URLs must not receive a /videos suffix")
    }

    func test_normalize_playlistURL_valuePreserved() {
        let url = "https://www.youtube.com/playlist?list=PLabc123"
        XCTAssertEqual(store.normalizeYouTubeURL(url), url)
    }

    // MARK: - normalizeYouTubeURL: whitespace

    func test_normalize_leadingAndTrailingWhitespaceStripped() {
        let result = store.normalizeYouTubeURL("  https://www.youtube.com/@channel/videos  ")
        XCTAssertEqual(result, "https://www.youtube.com/@channel/videos")
    }

    func test_normalize_newlineStripped() {
        let result = store.normalizeYouTubeURL("https://www.youtube.com/@channel/videos\n")
        XCTAssertEqual(result, "https://www.youtube.com/@channel/videos")
    }

    // MARK: - episodes(for:)

    func test_episodesForChannel_returnsOnlyMatchingChannel() {
        let channelA = makeChannel(name: "A", urlHandle: "a")
        let channelB = makeChannel(name: "B", urlHandle: "b")
        store.channels = [channelA, channelB]
        store.episodes = [
            makeEpisode(channelID: channelA.id, videoID: "a1"),
            makeEpisode(channelID: channelA.id, videoID: "a2"),
            makeEpisode(channelID: channelB.id, videoID: "b1"),
        ]
        let results = store.episodes(for: channelA.id)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.channelID == channelA.id })
    }

    func test_episodesForChannel_sortedNewestFirst() {
        let channel = makeChannel()
        store.channels = [channel]
        store.episodes = [
            makeEpisode(channelID: channel.id, videoID: "old", daysAgo: 10),
            makeEpisode(channelID: channel.id, videoID: "new", daysAgo: 1),
        ]
        let results = store.episodes(for: channel.id)
        XCTAssertEqual(results.first?.videoID, "new")
        XCTAssertEqual(results.last?.videoID, "old")
    }

    func test_episodesForChannel_emptyWhenChannelHasNoEpisodes() {
        let channel = makeChannel()
        store.channels = [channel]
        store.episodes = []
        XCTAssertTrue(store.episodes(for: channel.id).isEmpty)
    }

    func test_episodesForChannel_emptyForUnknownChannelID() {
        store.channels = []
        store.episodes = []
        XCTAssertTrue(store.episodes(for: UUID()).isEmpty)
    }

    func test_episodesForChannel_doesNotReturnOtherChannelsEpisodes() {
        let channelA = makeChannel(name: "A", urlHandle: "a")
        let channelB = makeChannel(name: "B", urlHandle: "b")
        store.channels = [channelA, channelB]
        store.episodes = [makeEpisode(channelID: channelB.id, videoID: "b1")]
        XCTAssertTrue(store.episodes(for: channelA.id).isEmpty)
    }

    // MARK: - regenerateFeed

    func test_regenerateFeed_createsFeedXMLInOutputDirectory() {
        let channel = makeChannel()
        let ep = makeEpisode(channelID: channel.id, videoID: "vid1", fileName: "vid1.mp3")
        store.channels = [channel]
        store.episodes = [ep]
        store.regenerateFeed()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("feed.xml").path))
    }

    func test_regenerateFeed_onlyDownloadedEpisodesInFeed() throws {
        let channel = makeChannel()
        let downloaded = makeEpisode(channelID: channel.id, videoID: "dl1", fileName: "dl1.mp3")
        let pending = makeEpisode(channelID: channel.id, videoID: "pend1", fileName: nil)
        store.channels = [channel]
        store.episodes = [downloaded, pending]
        store.regenerateFeed()
        let content = try String(contentsOf: tempDir.appendingPathComponent("feed.xml"), encoding: .utf8)
        XCTAssertTrue(content.contains("dl1"))
        XCTAssertFalse(content.contains("pend1"))
    }

    func test_regenerateFeed_episodesOrderedNewestFirst() throws {
        let channel = makeChannel()
        let older = makeEpisode(channelID: channel.id, videoID: "older", daysAgo: 10, fileName: "older.mp3")
        let newer = makeEpisode(channelID: channel.id, videoID: "newer", daysAgo: 1, fileName: "newer.mp3")
        store.channels = [channel]
        store.episodes = [older, newer]   // pass in old-first; feed should still sort newest-first
        store.regenerateFeed()
        let content = try String(contentsOf: tempDir.appendingPathComponent("feed.xml"), encoding: .utf8)
        let newerRange = content.range(of: "newer")!
        let olderRange = content.range(of: "older")!
        XCTAssertTrue(newerRange.lowerBound < olderRange.lowerBound, "regenerateFeed should emit the newest episode first")
    }

    func test_regenerateFeed_usesConfiguredServerPort() throws {
        store.serverPort = 9999
        store.channels = [makeChannel()]
        store.episodes = []
        store.regenerateFeed()
        let content = try String(contentsOf: tempDir.appendingPathComponent("feed.xml"), encoding: .utf8)
        XCTAssertTrue(content.contains("9999"))
    }

    // MARK: - filteredEpisodes

    func test_filteredEpisodes_allChannels() {
        let channel = makeChannel()
        store.channels = [channel]
        store.episodes = (0..<5).map { i in
            makeEpisode(channelID: channel.id, videoID: "vid\(i)", daysAgo: i)
        }
        let result = store.filteredEpisodes(for: Set(), query: "")
        XCTAssertEqual(result.count, 5)
        XCTAssertTrue(result.first!.publishDate >= result.last!.publishDate)
    }

    func test_filteredEpisodes_singleChannel() {
        let channelA = makeChannel(name: "A", urlHandle: "a")
        let channelB = makeChannel(name: "B", urlHandle: "b")
        store.channels = [channelA, channelB]
        store.episodes = [
            makeEpisode(channelID: channelA.id, videoID: "a1"),
            makeEpisode(channelID: channelB.id, videoID: "b1"),
        ]
        let result = store.filteredEpisodes(for: [channelA.id], query: "")
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.allSatisfy { $0.channelID == channelA.id })
    }

    func test_filteredEpisodes_searchQuery() {
        let channel = makeChannel()
        store.channels = [channel]
        store.episodes = [
            makeEpisode(channelID: channel.id, videoID: "match"),
            makeEpisode(channelID: channel.id, videoID: "other"),
        ]
        let result = store.filteredEpisodes(for: Set(), query: "match")
        XCTAssertEqual(result.count, 1)
    }

    func test_filteredEpisodes_caseInsensitiveSearch() {
        let channel = makeChannel()
        store.channels = [channel]
        store.episodes = [makeEpisode(channelID: channel.id, videoID: "MyVideo")]
        let result = store.filteredEpisodes(for: Set(), query: "myvideo")
        XCTAssertEqual(result.count, 1)
    }

    func test_filteredEpisodes_noMatch() {
        let channel = makeChannel()
        store.channels = [channel]
        store.episodes = [makeEpisode(channelID: channel.id, videoID: "something")]
        let result = store.filteredEpisodes(for: Set(), query: "nonexistent")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - togglePlayed

    func test_togglePlayed() {
        let chID = UUID()
        let ep = makeEpisode(channelID: chID, videoID: "v1", fileName: "v1.mp3")
        store.episodes = [ep]
        XCTAssertFalse(store.episodes[0].isPlayed)

        store.togglePlayed(ep.id)
        XCTAssertTrue(store.episodes[0].isPlayed)

        store.togglePlayed(ep.id)
        XCTAssertFalse(store.episodes[0].isPlayed)
    }

    // MARK: - deleteEpisodes

    func test_deleteEpisodes_removesFromList() {
        let chID = UUID()
        let ep1 = makeEpisode(channelID: chID, videoID: "v1")
        let ep2 = makeEpisode(channelID: chID, videoID: "v2")
        store.episodes = [ep1, ep2]
        store.deleteEpisodes([ep1.id])
        XCTAssertEqual(store.episodes.count, 1)
        XCTAssertEqual(store.episodes[0].videoID, "v2")
    }

    func test_deleteEpisodes_removesMP3File() throws {
        let chID = UUID()
        let ep = makeEpisode(channelID: chID, videoID: "v1", fileName: "v1.mp3")
        store.episodes = [ep]
        let episodesDir = Paths.episodesDir(in: tempDir)
        let mp3Path = episodesDir.appendingPathComponent("v1.mp3")
        try Data("fake".utf8).write(to: mp3Path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mp3Path.path))

        store.deleteEpisodes([ep.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: mp3Path.path))
    }

    // MARK: - removeChannels

    func test_removeChannels_removesEpisodes() {
        let ch = makeChannel()
        store.channels = [ch]
        store.episodes = [makeEpisode(channelID: ch.id, videoID: "v1")]
        store.removeChannels([ch.id])
        XCTAssertTrue(store.channels.isEmpty)
        XCTAssertTrue(store.episodes.isEmpty)
    }

    // MARK: - feedURL

    func test_feedURL_containsPort() {
        store.serverPort = 9999
        XCTAssertTrue(store.feedURL.contains("9999"))
        XCTAssertTrue(store.feedURL.hasSuffix("/feed.xml"))
    }

    // MARK: - Settings defaults

    func test_autoFetchIntervalDefaults() {
        XCTAssertEqual(store.autoFetchInterval, 0)
        XCTAssertFalse(store.autoStartServer)
    }

    // MARK: - persistence hygiene

    func test_load_prunesEpisodesWithoutMatchingChannels() throws {
        let validChannel = makeChannel(name: "Valid", urlHandle: "valid")
        let validEpisode = makeEpisode(channelID: validChannel.id, videoID: "keep")
        let orphanEpisode = makeEpisode(channelID: UUID(), videoID: "orphan")

        let payload: [String: Any] = [
            "channels": [[
                "id": validChannel.id.uuidString,
                "url": validChannel.url,
                "name": validChannel.name,
                "dateAdded": validChannel.dateAdded.timeIntervalSince1970,
            ]],
            "episodes": [
                [
                    "id": validEpisode.id.uuidString,
                    "channelID": validEpisode.channelID.uuidString,
                    "videoID": validEpisode.videoID,
                    "title": validEpisode.title,
                    "publishDate": validEpisode.publishDate.timeIntervalSince1970,
                    "durationSeconds": validEpisode.durationSeconds,
                    "isPlayed": validEpisode.isPlayed,
                ],
                [
                    "id": orphanEpisode.id.uuidString,
                    "channelID": orphanEpisode.channelID.uuidString,
                    "videoID": orphanEpisode.videoID,
                    "title": orphanEpisode.title,
                    "publishDate": orphanEpisode.publishDate.timeIntervalSince1970,
                    "durationSeconds": orphanEpisode.durationSeconds,
                    "isPlayed": orphanEpisode.isPlayed,
                ],
            ],
            "outputDirectory": tempDir.path,
            "serverPort": 8888,
            "autoFetchInterval": 0,
            "autoStartServer": false,
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: tempStateFile)

        let loadedStore = AppStore(
            stateFileURL: tempStateFile,
            shouldLoadPersistentState: true,
            autoCheckDependencies: false
        )

        XCTAssertEqual(loadedStore.allEpisodesCount, 1)
        XCTAssertEqual(loadedStore.episodes.count, 1)
        XCTAssertEqual(loadedStore.episodes.first?.videoID, "keep")
    }

    func test_load_resetsMissingTemporaryOutputDirectoryToDefault() throws {
        let missingTempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let payload: [String: Any] = [
            "channels": [],
            "episodes": [],
            "outputDirectory": missingTempDirectory.path,
            "serverPort": 8888,
            "autoFetchInterval": 0,
            "autoStartServer": false,
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: tempStateFile)

        let loadedStore = AppStore(
            stateFileURL: tempStateFile,
            shouldLoadPersistentState: true,
            autoCheckDependencies: false
        )

        XCTAssertEqual(loadedStore.outputDirectory.standardizedFileURL, Paths.defaultOutputDir.standardizedFileURL)
    }
}
