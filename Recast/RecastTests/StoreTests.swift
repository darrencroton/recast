import XCTest
@testable import Recast

final class StoreTests: XCTestCase {

    private var store: AppStore!
    private var tempDir: URL!
    private var tempAppSupportDir: URL!
    private var tempStateFile: URL!
    private var defaultOutputDir: URL!

    // MARK: - Setup / teardown

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempAppSupportDir = tempDir.appendingPathComponent("app-support", isDirectory: true)
        try! FileManager.default.createDirectory(at: tempAppSupportDir, withIntermediateDirectories: true)
        tempStateFile = tempAppSupportDir.appendingPathComponent("state.json")
        defaultOutputDir = tempDir.appendingPathComponent("default-output", isDirectory: true)
        store = AppStore(
            stateFileURL: tempStateFile,
            appSupportURL: tempAppSupportDir,
            defaultOutputDirectory: defaultOutputDir,
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

    // MARK: - normalizeYouTubeURL: direct episode URLs canonicalised

    func test_normalize_shortURL_convertedToWatchURL() {
        let result = store.normalizeYouTubeURL("https://youtu.be/MBg7WxnLzfA")
        XCTAssertEqual(result, "https://www.youtube.com/watch?v=MBg7WxnLzfA")
    }

    func test_normalize_watchURL_stripsExtraParameters() {
        let result = store.normalizeYouTubeURL("https://www.youtube.com/watch?v=MBg7WxnLzfA&t=42s&feature=youtu.be")
        XCTAssertEqual(result, "https://www.youtube.com/watch?v=MBg7WxnLzfA")
    }

    func test_normalize_shortsURL_convertedToWatchURL() {
        let result = store.normalizeYouTubeURL("https://www.youtube.com/shorts/MBg7WxnLzfA?feature=share")
        XCTAssertEqual(result, "https://www.youtube.com/watch?v=MBg7WxnLzfA")
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

    func test_handleServerHostChange_regeneratesExistingFeedWithUpdatedHost() throws {
        let channel = makeChannel()
        let episode = makeEpisode(channelID: channel.id, videoID: "vid1", fileName: "vid1.mp3")
        store.channels = [channel]
        store.episodes = [episode]
        store.serverHost = "old.example.com"
        store.regenerateFeed()

        store.serverHost = "new.example.com"
        store.handleServerHostChange()

        let content = try String(contentsOf: tempDir.appendingPathComponent("feed.xml"), encoding: .utf8)
        XCTAssertTrue(content.contains("http://new.example.com:8888/feed.xml"))
        XCTAssertTrue(content.contains("http://new.example.com:8888/episodes/vid1.mp3"))
        XCTAssertFalse(content.contains("http://old.example.com:8888"))
    }

    func test_regenerateFeed_wrapsIPv6HostInURLs() throws {
        let channel = makeChannel()
        let episode = makeEpisode(channelID: channel.id, videoID: "vid1", fileName: "vid1.mp3")
        store.channels = [channel]
        store.episodes = [episode]
        store.serverHost = "fd7a:115c:a1e0::42"

        store.regenerateFeed()

        let content = try String(contentsOf: tempDir.appendingPathComponent("feed.xml"), encoding: .utf8)
        XCTAssertTrue(content.contains("http://[fd7a:115c:a1e0::42]:8888/feed.xml"))
        XCTAssertTrue(content.contains("http://[fd7a:115c:a1e0::42]:8888/episodes/vid1.mp3"))
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

    func test_filteredEpisodes_newFilterReturnsOnlyNewEpisodes() {
        let channel = makeChannel()
        var newEpisode = makeEpisode(channelID: channel.id, videoID: "new")
        newEpisode.isNew = true
        let oldEpisode = makeEpisode(channelID: channel.id, videoID: "old")
        store.channels = [channel]
        store.episodes = [newEpisode, oldEpisode]

        let result = store.filteredEpisodes(for: Set(), query: "", filter: .new)

        XCTAssertEqual(result.map(\.videoID), ["new"])
    }

    func test_episodeCount_usesSelectedFilter() {
        let channel = makeChannel()
        var downloaded = makeEpisode(channelID: channel.id, videoID: "downloaded", fileName: "downloaded.mp3")
        downloaded.isNew = true
        let pending = makeEpisode(channelID: channel.id, videoID: "pending")
        store.channels = [channel]
        store.episodes = [downloaded, pending]

        XCTAssertEqual(store.episodeCount(for: Set(), query: "", filter: .downloaded), 1)
        XCTAssertEqual(store.episodeCount(for: Set(), query: "", filter: .new), 1)
        XCTAssertEqual(store.episodeCount(for: Set(), query: "", filter: .all), 2)
    }

    func test_hasPendingDownloads_tracksQueuedStatuses() {
        store.activeDownloadStatus["queued"] = DownloadStatus(progress: 0, phase: .queued)

        XCTAssertTrue(store.hasPendingDownloads)
        XCTAssertFalse(store.hasActiveDownloads)
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

    func test_deleteEpisodes_removesArtworkSidecar() throws {
        let chID = UUID()
        let ep = makeEpisode(channelID: chID, videoID: "v1", fileName: "v1.mp3")
        store.episodes = [ep]
        let artworkPath = Paths.artworkURL(forEpisodeFileName: "v1.mp3", in: tempDir)
        try FileManager.default.createDirectory(at: artworkPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fake".utf8).write(to: artworkPath)

        store.deleteEpisodes([ep.id])

        XCTAssertFalse(FileManager.default.fileExists(atPath: artworkPath.path))
    }

    func test_deleteEpisodes_removesEmptySingleEpisodeSource() {
        let source = Channel(
            url: "https://www.youtube.com/watch?v=solo123",
            name: "Solo Creator",
            sourceKind: .singleEpisode,
            relatedCollectionURL: "https://www.youtube.com/@solo/videos"
        )
        let episode = makeEpisode(channelID: source.id, videoID: "solo123")
        store.channels = [source]
        store.episodes = [episode]

        store.deleteEpisodes([episode.id])

        XCTAssertTrue(store.channels.isEmpty)
        XCTAssertTrue(store.episodes.isEmpty)
    }

    func test_deleteEpisodes_removesNestedMP3File() throws {
        let channel = makeChannel(name: "Science Weekly")
        let relativePath = Paths.relativeEpisodePath(forFileName: "v1.mp3", in: channel)
        let ep = makeEpisode(channelID: channel.id, videoID: "v1", fileName: relativePath)
        store.channels = [channel]
        store.episodes = [ep]
        let mp3Path = Paths.episodeFileURL(forRelativePath: relativePath, in: tempDir)
        try FileManager.default.createDirectory(at: mp3Path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fake".utf8).write(to: mp3Path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mp3Path.path))

        store.deleteEpisodes([ep.id])

        XCTAssertFalse(FileManager.default.fileExists(atPath: mp3Path.path))
    }

    func test_deleteEpisodes_removesNestedArtworkSidecar() throws {
        let channel = makeChannel(name: "Science Weekly")
        let relativePath = Paths.relativeEpisodePath(forFileName: "v1.mp3", in: channel)
        let ep = makeEpisode(channelID: channel.id, videoID: "v1", fileName: relativePath)
        store.channels = [channel]
        store.episodes = [ep]
        let artworkPath = Paths.artworkURL(forEpisodeFileName: relativePath, in: tempDir)
        try FileManager.default.createDirectory(at: artworkPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fake".utf8).write(to: artworkPath)

        store.deleteEpisodes([ep.id])

        XCTAssertFalse(FileManager.default.fileExists(atPath: artworkPath.path))
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

    func test_channelArtworkURL_prefersNewestDownloadedEpisodeArtwork() throws {
        let channel = makeChannel()
        let older = makeEpisode(channelID: channel.id, videoID: "older", daysAgo: 5, fileName: "older.mp3")
        let newer = makeEpisode(channelID: channel.id, videoID: "newer", daysAgo: 1, fileName: "newer.mp3")
        store.channels = [channel]
        store.episodes = [older, newer]
        let olderArtwork = Paths.artworkURL(forEpisodeFileName: "older.mp3", in: tempDir)
        let newerArtwork = Paths.artworkURL(forEpisodeFileName: "newer.mp3", in: tempDir)
        try FileManager.default.createDirectory(at: olderArtwork.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: olderArtwork)
        try Data("new".utf8).write(to: newerArtwork)

        XCTAssertEqual(store.channelArtworkURL(for: channel.id)?.lastPathComponent, "newer.jpg")
    }

    // MARK: - feedURL

    func test_feedURL_containsPort() {
        store.serverPort = 9999
        XCTAssertTrue(store.feedURL.contains("9999"))
        XCTAssertTrue(store.feedURL.hasSuffix("/feed.xml"))
    }

    func test_feedURL_wrapsIPv6HostInBrackets() {
        store.serverHost = "fd7a:115c:a1e0::42"
        XCTAssertEqual(store.feedURL, "http://[fd7a:115c:a1e0::42]:8888/feed.xml")
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
            appSupportURL: tempAppSupportDir,
            defaultOutputDirectory: defaultOutputDir,
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
            appSupportURL: tempAppSupportDir,
            defaultOutputDirectory: defaultOutputDir,
            shouldLoadPersistentState: true,
            autoCheckDependencies: false
        )

        XCTAssertEqual(loadedStore.outputDirectory.standardizedFileURL, defaultOutputDir.standardizedFileURL)
    }

    func test_cleanupPartialArtifacts_removesOnlyMatchingFiles() async throws {
        let channel = makeChannel()
        let episode = makeEpisode(channelID: channel.id, videoID: "partial")
        store.channels = [channel]
        let episodesDir = Paths.episodesDir(in: tempDir)

        let matchingWebm = episodesDir.appendingPathComponent("\(String(episode.suggestedFileName.dropLast(4))).webm")
        let matchingMP3 = episodesDir.appendingPathComponent(episode.suggestedFileName)
        let otherFile = episodesDir.appendingPathComponent("keep-me.mp3")

        try Data("partial".utf8).write(to: matchingWebm)
        try Data("partial".utf8).write(to: matchingMP3)
        try Data("keep".utf8).write(to: otherFile)

        try await store.downloader.cleanupPartialArtifacts(for: episode, in: episodesDir, moveToTrash: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: matchingWebm.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: matchingMP3.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherFile.path))
    }

    func test_resetToDefaults_clearsStateAndManagedArtifacts() async throws {
        let customOutputDir = tempDir.appendingPathComponent("custom-output", isDirectory: true)
        try FileManager.default.createDirectory(at: customOutputDir, withIntermediateDirectories: true)

        let channel = makeChannel()
        let downloadedEpisode = makeEpisode(channelID: channel.id, videoID: "reset-me", fileName: "reset-me.mp3")
        store.channels = [channel]
        store.episodes = [downloadedEpisode]
        store.outputDirectory = customOutputDir
        store.serverPort = 9999
        store.autoFetchInterval = 24
        store.autoStartServer = true
        store.activeDownloadStatus = [
            "reset-me": DownloadStatus(progress: 0.5, phase: .convertingAudio)
        ]

        let episodesDir = Paths.ensureManagedEpisodesDirectory(in: customOutputDir)
        let audioFile = episodesDir.appendingPathComponent("reset-me.mp3")
        try Data("audio".utf8).write(to: audioFile)
        FeedGenerator.write(
            episodes: [downloadedEpisode],
            channels: [channel],
            baseURL: "http://localhost:9999",
            to: customOutputDir
        )

        let binDir = tempAppSupportDir.appendingPathComponent("bin", isDirectory: true)
        let logsDir = tempAppSupportDir.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        try Data("bin".utf8).write(to: binDir.appendingPathComponent("yt-dlp"))
        try Data("log".utf8).write(to: logsDir.appendingPathComponent("recast.log"))

        store.save()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempStateFile.path))

        await store.resetToDefaults()

        XCTAssertTrue(store.channels.isEmpty)
        XCTAssertTrue(store.episodes.isEmpty)
        XCTAssertEqual(store.outputDirectory.standardizedFileURL, defaultOutputDir.standardizedFileURL)
        XCTAssertEqual(store.serverPort, 8888)
        XCTAssertEqual(store.autoFetchInterval, 0)
        XCTAssertFalse(store.autoStartServer)
        XCTAssertFalse(store.isServerRunning)
        XCTAssertFalse(store.hasActiveDownloads)
        XCTAssertTrue(store.activeDownloadStatus.isEmpty)
        XCTAssertEqual(store.statusMessage, "Ready")

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: episodesDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: customOutputDir.appendingPathComponent("feed.xml").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: binDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logsDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logsDir.appendingPathComponent("recast.log").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempStateFile.path))

        let reloadedStore = AppStore(
            stateFileURL: tempStateFile,
            appSupportURL: tempAppSupportDir,
            defaultOutputDirectory: defaultOutputDir,
            shouldLoadPersistentState: true,
            autoCheckDependencies: false
        )

        XCTAssertTrue(reloadedStore.channels.isEmpty)
        XCTAssertTrue(reloadedStore.episodes.isEmpty)
        XCTAssertEqual(reloadedStore.outputDirectory.standardizedFileURL, defaultOutputDir.standardizedFileURL)
        XCTAssertEqual(reloadedStore.serverPort, 8888)
        XCTAssertEqual(reloadedStore.autoFetchInterval, 0)
        XCTAssertFalse(reloadedStore.autoStartServer)
    }

    func test_resetToDefaults_preservesUnownedOutputArtifacts() async throws {
        let customOutputDir = tempDir.appendingPathComponent("shared-output", isDirectory: true)
        try FileManager.default.createDirectory(at: customOutputDir, withIntermediateDirectories: true)

        let channel = makeChannel()
        let downloadedEpisode = makeEpisode(channelID: channel.id, videoID: "reset-me", fileName: "reset-me.mp3")
        let partialEpisode = makeEpisode(channelID: channel.id, videoID: "partial-me")
        store.channels = [channel]
        store.episodes = [downloadedEpisode, partialEpisode]
        store.outputDirectory = customOutputDir

        let episodesDir = Paths.ensureManagedEpisodesDirectory(in: customOutputDir)
        let managedAudioFile = episodesDir.appendingPathComponent("reset-me.mp3")
        let managedPartialFile = episodesDir.appendingPathComponent("\(String(partialEpisode.suggestedFileName.dropLast(4))).webm")
        let unrelatedAudioFile = episodesDir.appendingPathComponent("keep-me.mp3")
        let unrelatedFeedFile = customOutputDir.appendingPathComponent("feed.xml")

        try Data("audio".utf8).write(to: managedAudioFile)
        try Data("partial".utf8).write(to: managedPartialFile)
        try Data("keep".utf8).write(to: unrelatedAudioFile)
        try Data("user feed".utf8).write(to: unrelatedFeedFile)

        await store.resetToDefaults()

        XCTAssertFalse(FileManager.default.fileExists(atPath: managedAudioFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedPartialFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedAudioFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedFeedFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: episodesDir.path))
    }

    func test_resetToDefaults_removesNestedManagedArtifactsAndPrunesEmptyChannelFolder() async throws {
        let customOutputDir = tempDir.appendingPathComponent("nested-output", isDirectory: true)
        try FileManager.default.createDirectory(at: customOutputDir, withIntermediateDirectories: true)

        let channel = makeChannel(name: "Science Weekly")
        let relativePath = Paths.relativeEpisodePath(forFileName: "reset-me.mp3", in: channel)
        let downloadedEpisode = makeEpisode(channelID: channel.id, videoID: "reset-me", fileName: relativePath)
        store.channels = [channel]
        store.episodes = [downloadedEpisode]
        store.outputDirectory = customOutputDir

        let channelDir = Paths.ensureManagedChannelEpisodesDirectory(for: channel, in: customOutputDir)
        let audioFile = Paths.episodeFileURL(forRelativePath: relativePath, in: customOutputDir)
        let artworkFile = Paths.artworkURL(forEpisodeFileName: relativePath, in: customOutputDir)
        try Data("audio".utf8).write(to: audioFile)
        try Data("art".utf8).write(to: artworkFile)

        await store.resetToDefaults()

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artworkFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: channelDir.path))
    }
}
