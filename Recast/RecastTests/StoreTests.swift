import AppKit
import XCTest
@testable import Recast

final class StoreTests: XCTestCase {

    private var store: AppStore!
    private var tempDir: URL!
    private var tempAppSupportDir: URL!
    private var tempStateFile: URL!
    private var defaultEpisodesDir: URL!

    private var feedDir: URL {
        Paths.serverDirectory(in: tempAppSupportDir)
    }

    // MARK: - Setup / teardown

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempAppSupportDir = tempDir.appendingPathComponent("app-support", isDirectory: true)
        try! FileManager.default.createDirectory(at: tempAppSupportDir, withIntermediateDirectories: true)
        tempStateFile = tempAppSupportDir.appendingPathComponent("state.json")
        defaultEpisodesDir = tempDir.appendingPathComponent("default-episodes", isDirectory: true)
        store = AppStore(
            stateFileURL: tempStateFile,
            appSupportURL: tempAppSupportDir,
            defaultEpisodesDirectory: defaultEpisodesDir,
            shouldLoadPersistentState: false,
            autoCheckDependencies: false
        )
        store.episodesDirectory = tempDir
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

    private func makeVideoInfo(videoID: String, daysAgo: Int = 0) -> Downloader.VideoInfo {
        let publishDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return Downloader.VideoInfo(
            videoID: videoID,
            title: videoID,
            publishDate: publishDate,
            durationSeconds: 120
        )
    }

    private func createDownloadedEpisodeFile(named relativePath: String) throws -> URL {
        let fileURL = Paths.episodeFileURL(forRelativePath: relativePath, in: store.episodesDirectory)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("audio".utf8).write(to: fileURL)
        return fileURL
    }

    private func createSharedArtworkFile(videoID: String, width: Int, height: Int) throws -> URL {
        let artworkURL = Paths.sharedArtworkURL(forVideoID: videoID, in: store.episodesDirectory)
        try FileManager.default.createDirectory(
            at: artworkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemTeal.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2)).fill()
        NSGraphicsContext.restoreGraphicsState()

        let data = try XCTUnwrap(bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]))
        try data.write(to: artworkURL)
        return artworkURL
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

    // MARK: - downloaded episode files

    func test_downloadedEpisodeFileURL_returnsExistingLocalFileURL() throws {
        let channel = makeChannel()
        let relativePath = "Channel Folder [abc12345]/test-episode.mp3"
        let expectedURL = try createDownloadedEpisodeFile(named: relativePath)
        let episode = makeEpisode(channelID: channel.id, videoID: "vid1", fileName: relativePath)

        XCTAssertEqual(store.downloadedEpisodeFileURL(for: episode), expectedURL)
    }

    func test_downloadedEpisodeFileURL_returnsNilWhenFileIsMissing() {
        let channel = makeChannel()
        let episode = makeEpisode(channelID: channel.id, videoID: "vid1", fileName: "missing.mp3")

        XCTAssertNil(store.downloadedEpisodeFileURL(for: episode))
    }

    func test_openEpisode_opensExistingDownloadedFileInDefaultApp() throws {
        var openedURL: URL?
        store = AppStore(
            stateFileURL: tempStateFile,
            appSupportURL: tempAppSupportDir,
            defaultEpisodesDirectory: defaultEpisodesDir,
            shouldLoadPersistentState: false,
            autoCheckDependencies: false,
            openURLInDefaultApp: {
                openedURL = $0
                return true
            }
        )
        store.episodesDirectory = tempDir

        let channel = makeChannel()
        let relativePath = "Channel Folder [abc12345]/test-episode.mp3"
        let expectedURL = try createDownloadedEpisodeFile(named: relativePath)
        let episode = makeEpisode(channelID: channel.id, videoID: "vid1", fileName: relativePath)

        store.openEpisode(episode)

        XCTAssertEqual(openedURL, expectedURL)
    }

    // MARK: - regenerateFeed

    func test_regenerateFeed_createsFeedXMLInAppSupportServerDirectory() {
        let channel = makeChannel()
        let ep = makeEpisode(channelID: channel.id, videoID: "vid1", fileName: "vid1.mp3")
        store.channels = [channel]
        store.episodes = [ep]
        store.regenerateFeed()
        XCTAssertTrue(FileManager.default.fileExists(atPath: Paths.feedFileURL(in: feedDir).path))
    }

    func test_regenerateFeed_copiesBundledShowArtworkToAppSupportServerDirectory() {
        store.channels = [makeChannel()]
        store.episodes = []

        store.regenerateFeed()

        XCTAssertTrue(FileManager.default.fileExists(atPath: Paths.showArtworkURL(in: feedDir).path))
    }

    func test_regenerateFeed_normalizesEpisodeArtworkToSquarePodcastDimensions() throws {
        let channel = makeChannel(name: "Science Weekly")
        let relativePath = Paths.relativeEpisodePath(forFileName: "episode.mp3", in: channel)
        _ = try createDownloadedEpisodeFile(named: relativePath)
        let artworkURL = try createSharedArtworkFile(videoID: "episode", width: 1280, height: 720)
        let episode = makeEpisode(channelID: channel.id, videoID: "episode", fileName: relativePath)
        store.channels = [channel]
        store.episodes = [episode]

        store.regenerateFeed()

        let artworkData = try Data(contentsOf: artworkURL)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: artworkData))
        XCTAssertEqual(representation.pixelsWide, 1400)
        XCTAssertEqual(representation.pixelsHigh, 1400)
    }

    func test_regenerateFeed_createsFeedAssetAliases() throws {
        let channel = makeChannel(name: "Science Weekly")
        let relativePath = Paths.relativeEpisodePath(forFileName: "episode.mp3", in: channel)
        let sourceAudioURL = try createDownloadedEpisodeFile(named: relativePath)
        let sourceArtworkURL = try createSharedArtworkFile(videoID: "episode123", width: 1400, height: 1400)
        let episode = makeEpisode(channelID: channel.id, videoID: "episode123", fileName: relativePath)
        store.channels = [channel]
        store.episodes = [episode]

        store.regenerateFeed()

        let audioAliasURL = Paths.feedAudioURL(forVideoID: "episode123", in: feedDir)
        let artworkAliasURL = Paths.feedArtworkURL(forVideoID: "episode123", in: feedDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: audioAliasURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artworkAliasURL.path))

        let audioAliasValues = try audioAliasURL.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        let artworkAliasValues = try artworkAliasURL.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        XCTAssertNotEqual(audioAliasValues.isSymbolicLink, true)
        XCTAssertNotEqual(artworkAliasValues.isSymbolicLink, true)

        let sourceAudioValues = try sourceAudioURL.resourceValues(forKeys: [.fileSizeKey])
        let sourceArtworkValues = try sourceArtworkURL.resourceValues(forKeys: [.fileSizeKey])
        XCTAssertEqual(audioAliasValues.fileSize, sourceAudioValues.fileSize)
        XCTAssertEqual(artworkAliasValues.fileSize, sourceArtworkValues.fileSize)
    }

    func test_regenerateFeed_movesManagedEpisodeSidecarArtworkIntoSharedStorage() throws {
        let channel = makeChannel(name: "Science Weekly")
        let relativePath = Paths.relativeEpisodePath(forFileName: "episode.mp3", in: channel)
        _ = try createDownloadedEpisodeFile(named: relativePath)

        let sidecarArtworkURL = Paths.managedEpisodeArtworkURL(forRelativeEpisodePath: relativePath, in: tempDir)
        try FileManager.default.createDirectory(
            at: sidecarArtworkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("jpg".utf8).write(to: sidecarArtworkURL)

        let episode = makeEpisode(channelID: channel.id, videoID: "episode123", fileName: relativePath)
        store.channels = [channel]
        store.episodes = [episode]

        store.regenerateFeed()

        let sharedArtworkURL = Paths.sharedArtworkURL(forVideoID: episode.videoID, in: tempDir)
        let feedArtworkURL = Paths.feedArtworkURL(forVideoID: episode.videoID, in: feedDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarArtworkURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedArtworkURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: feedArtworkURL.path))
        XCTAssertEqual(store.artworkURL(for: episode)?.path, sharedArtworkURL.path)
        XCTAssertEqual(store.channelArtworkURL(for: channel.id)?.path, sharedArtworkURL.path)
    }

    func test_regenerateFeed_onlyDownloadedEpisodesInFeed() throws {
        let channel = makeChannel()
        let downloaded = makeEpisode(channelID: channel.id, videoID: "dl1", fileName: "dl1.mp3")
        let pending = makeEpisode(channelID: channel.id, videoID: "pend1", fileName: nil)
        store.channels = [channel]
        store.episodes = [downloaded, pending]
        store.regenerateFeed()
        let content = try String(contentsOf: Paths.feedFileURL(in: feedDir), encoding: .utf8)
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
        let content = try String(contentsOf: Paths.feedFileURL(in: feedDir), encoding: .utf8)
        let newerRange = content.range(of: "newer")!
        let olderRange = content.range(of: "older")!
        XCTAssertTrue(newerRange.lowerBound < olderRange.lowerBound, "regenerateFeed should emit the newest episode first")
    }

    func test_regenerateFeed_usesConfiguredServerPort() throws {
        store.serverPort = 9999
        store.channels = [makeChannel()]
        store.episodes = []
        store.regenerateFeed()
        let content = try String(contentsOf: Paths.feedFileURL(in: feedDir), encoding: .utf8)
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

        let content = try String(contentsOf: Paths.feedFileURL(in: feedDir), encoding: .utf8)
        XCTAssertTrue(content.contains("http://new.example.com:8888/feed.xml"))
        XCTAssertTrue(content.contains("http://new.example.com:8888/feed-assets/vid1.mp3"))
        XCTAssertFalse(content.contains("http://old.example.com:8888"))
    }

    func test_commitServerHost_blankInputResetsToDefault() {
        store.serverHost = "custom.example.com"

        store.commitServerHost("   ")

        XCTAssertEqual(store.serverHost, "")
    }

    func test_commitServerHost_trimsWhitespace() {
        store.commitServerHost("  custom.example.com  ")

        XCTAssertEqual(store.serverHost, "custom.example.com")
    }

    func test_commitServerPort_validInputUpdatesPort() {
        store.commitServerPort("9999")

        XCTAssertEqual(store.serverPort, 9999)
    }

    func test_commitServerPort_trimsWhitespace() {
        store.commitServerPort("  9999  ")

        XCTAssertEqual(store.serverPort, 9999)
    }

    func test_commitServerPort_blankInputResetsToDefault() {
        store.serverPort = 9999

        store.commitServerPort("   ")

        XCTAssertEqual(store.serverPort, store.defaultServerPort)
    }

    func test_commitServerPort_invalidInputResetsToDefault() {
        store.serverPort = 9999

        store.commitServerPort("rrr")

        XCTAssertEqual(store.serverPort, store.defaultServerPort)
    }

    func test_commitServerPort_outOfRangeInputResetsToDefault() {
        store.serverPort = 9999

        store.commitServerPort("70000")

        XCTAssertEqual(store.serverPort, store.defaultServerPort)
    }

    func test_regenerateFeed_wrapsIPv6HostInURLs() throws {
        let channel = makeChannel()
        let episode = makeEpisode(channelID: channel.id, videoID: "vid1", fileName: "vid1.mp3")
        store.channels = [channel]
        store.episodes = [episode]
        store.serverHost = "fd7a:115c:a1e0::42"

        store.regenerateFeed()

        let content = try String(contentsOf: Paths.feedFileURL(in: feedDir), encoding: .utf8)
        XCTAssertTrue(content.contains("http://[fd7a:115c:a1e0::42]:8888/feed.xml"))
        XCTAssertTrue(content.contains("http://[fd7a:115c:a1e0::42]:8888/feed-assets/vid1.mp3"))
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

    func test_autoFetchDownloadTargets_onlyIncludesUndownloadedPendingAutoDownloads() {
        let channel = makeChannel()
        var newPending = makeEpisode(channelID: channel.id, videoID: "new-pending", daysAgo: 1)
        newPending.isPendingAutoDownload = true
        let oldPending = makeEpisode(channelID: channel.id, videoID: "old-pending", daysAgo: 2)
        var newDownloaded = makeEpisode(channelID: channel.id, videoID: "new-downloaded", fileName: "new-downloaded.mp3")
        newDownloaded.isPendingAutoDownload = true
        store.channels = [channel]
        store.episodes = [oldPending, newDownloaded, newPending]

        let result = store.autoFetchDownloadTargets(for: Set())

        XCTAssertEqual(result.map(\.videoID), ["new-pending"])
    }

    func test_autoFetchDownloadTargets_retriesPendingAutoDownloadAfterNewFlagCleared() {
        let channel = makeChannel()
        var retryable = makeEpisode(channelID: channel.id, videoID: "retryable")
        retryable.isPendingAutoDownload = true
        store.channels = [channel]
        store.episodes = [retryable]

        let result = store.autoFetchDownloadTargets(for: Set())

        XCTAssertEqual(result.map(\.videoID), ["retryable"])
    }

    func test_autoFetchDownloadTargets_skipsKnownUndownloadedSingleEpisodeSource() {
        let source = Channel(
            url: "https://www.youtube.com/watch?v=solo123",
            name: "Solo Creator",
            sourceKind: .singleEpisode,
            relatedCollectionURL: "https://www.youtube.com/@solo/videos"
        )
        let episode = makeEpisode(channelID: source.id, videoID: "solo123")
        store.channels = [source]
        store.episodes = [episode]

        let result = store.autoFetchDownloadTargets(for: Set())

        XCTAssertTrue(result.isEmpty)
    }

    func test_autoFetchDownloadTargets_filtersByChannelAndSortsNewestFirst() {
        let channelA = makeChannel(name: "A", urlHandle: "a")
        let channelB = makeChannel(name: "B", urlHandle: "b")
        var newest = makeEpisode(channelID: channelA.id, videoID: "newest", daysAgo: 0)
        newest.isPendingAutoDownload = true
        var older = makeEpisode(channelID: channelA.id, videoID: "older", daysAgo: 3)
        older.isPendingAutoDownload = true
        var otherChannel = makeEpisode(channelID: channelB.id, videoID: "other-channel", daysAgo: 1)
        otherChannel.isPendingAutoDownload = true
        store.channels = [channelA, channelB]
        store.episodes = [older, otherChannel, newest]

        let result = store.autoFetchDownloadTargets(for: [channelA.id])

        XCTAssertEqual(result.map(\.videoID), ["newest", "older"])
    }

    func test_autoFetchDownloadTargets_limitsScheduledDownloadsPerChannel() {
        let channelA = makeChannel(name: "A", urlHandle: "a")
        let channelB = makeChannel(name: "B", urlHandle: "b")

        let channelAEpisodes = (0..<7).map { index -> Episode in
            var episode = makeEpisode(channelID: channelA.id, videoID: "a\(index)", daysAgo: index)
            episode.isPendingAutoDownload = true
            return episode
        }
        let channelBEpisodes = (0..<2).map { index -> Episode in
            var episode = makeEpisode(channelID: channelB.id, videoID: "b\(index)", daysAgo: index)
            episode.isPendingAutoDownload = true
            return episode
        }

        store.channels = [channelA, channelB]
        store.episodes = channelAEpisodes + channelBEpisodes

        let result = store.autoFetchDownloadTargets(for: Set(), maxPerChannel: 5)

        XCTAssertEqual(result.filter { $0.channelID == channelA.id }.count, 5)
        XCTAssertEqual(result.filter { $0.channelID == channelB.id }.count, 2)
        XCTAssertEqual(
            result.filter { $0.channelID == channelA.id }.map(\.videoID),
            ["a0", "a1", "a2", "a3", "a4"]
        )
        XCTAssertEqual(
            result.filter { $0.channelID == channelB.id }.map(\.videoID),
            ["b0", "b1"]
        )
    }

    func test_autoFetchDownloadTargets_rotatesOlderPendingRetriesBackIntoCappedSelection() {
        let channel = makeChannel()
        let now = Date()
        let recentAttempt = now.addingTimeInterval(-60)
        let olderAttempt = now.addingTimeInterval(-600)

        let episodes = (0..<7).map { index -> Episode in
            var episode = makeEpisode(channelID: channel.id, videoID: "ep\(index)", daysAgo: index)
            episode.isPendingAutoDownload = true
            if index < 5 {
                episode.lastAutoDownloadAttemptAt = recentAttempt
            } else if index == 5 {
                episode.lastAutoDownloadAttemptAt = olderAttempt
            }
            return episode
        }

        store.channels = [channel]
        store.episodes = episodes

        let result = store.autoFetchDownloadTargets(for: Set(), maxPerChannel: 5)

        XCTAssertTrue(result.map(\.videoID).contains("ep6"))
        XCTAssertTrue(result.map(\.videoID).contains("ep5"))
        XCTAssertEqual(result.count, 5)
    }

    func test_recordAutoDownloadAttempt_marksOnlySelectedScheduledTargets() {
        let channel = makeChannel()
        let episodes = (0..<7).map { index -> Episode in
            var episode = makeEpisode(channelID: channel.id, videoID: "ep\(index)", daysAgo: index)
            episode.isPendingAutoDownload = true
            return episode
        }
        store.channels = [channel]
        store.episodes = episodes

        let targets = store.autoFetchDownloadTargets(for: Set(), maxPerChannel: 5)
        store.recordAutoDownloadAttempt(for: targets)

        XCTAssertEqual(store.episodes.filter { $0.lastAutoDownloadAttemptAt != nil }.count, 5)
        XCTAssertTrue(store.episodes.contains { $0.videoID == "ep5" && $0.lastAutoDownloadAttemptAt == nil })
        XCTAssertTrue(store.episodes.contains { $0.videoID == "ep6" && $0.lastAutoDownloadAttemptAt == nil })
    }

    func test_autoFetch_doesNotRecordLastAutoFetchAtWhenAnotherRefreshIsRunning() async {
        store.isFetching = true

        await store.autoFetch()

        XCTAssertNil(store.lastAutoFetchAt)
    }

    func test_addSource_collectionImmediatelyFetchesInitialEpisodesAsNewWithoutPendingAutoDownload() async throws {
        let resolvedName = "Science Updates"
        let initialVideos = [
            makeVideoInfo(videoID: "fresh0", daysAgo: 0),
            makeVideoInfo(videoID: "fresh1", daysAgo: 1),
        ]

        store = AppStore(
            stateFileURL: tempStateFile,
            appSupportURL: tempAppSupportDir,
            defaultEpisodesDirectory: defaultEpisodesDir,
            shouldLoadPersistentState: false,
            autoCheckDependencies: false,
            resolveChannelNameOverride: { _ in resolvedName },
            listVideosOverride: { _, _ in initialVideos }
        )
        store.episodesDirectory = tempDir

        try await store.addSource(url: "https://www.youtube.com/@science/videos")

        XCTAssertEqual(store.channels.count, 1)
        XCTAssertEqual(store.channels[0].name, resolvedName)
        XCTAssertTrue(store.channels[0].hasCompletedInitialImport)
        XCTAssertEqual(Set(store.episodes.map(\.videoID)), Set(["fresh0", "fresh1"]))
        XCTAssertTrue(store.episodes.allSatisfy(\.isNew))
        XCTAssertTrue(store.episodes.allSatisfy { !$0.isPendingAutoDownload })
    }

    func test_fetchNewEpisodes_manualRefreshReplacesNewWithoutQueueingAutoDownload() async {
        let channel = Channel(
            url: "https://www.youtube.com/@science/videos",
            name: "Science",
            hasCompletedInitialImport: true
        )
        var existingEpisode = makeEpisode(channelID: channel.id, videoID: "existing", daysAgo: 2)
        existingEpisode.isNew = true

        store = AppStore(
            stateFileURL: tempStateFile,
            appSupportURL: tempAppSupportDir,
            defaultEpisodesDirectory: defaultEpisodesDir,
            shouldLoadPersistentState: false,
            autoCheckDependencies: false,
            listVideosOverride: { _, _ in
                [
                    self.makeVideoInfo(videoID: "new-manual", daysAgo: 0),
                    self.makeVideoInfo(videoID: "existing", daysAgo: 2),
                ]
            }
        )
        store.episodesDirectory = tempDir
        store.channels = [channel]
        store.episodes = [existingEpisode]

        let didComplete = await store.fetchNewEpisodes(for: [channel.id], context: .manual)

        XCTAssertTrue(didComplete)
        XCTAssertFalse(try! XCTUnwrap(store.episodes.first(where: { $0.videoID == "existing" })).isNew)
        let manualEpisode = try! XCTUnwrap(store.episodes.first(where: { $0.videoID == "new-manual" }))
        XCTAssertTrue(manualEpisode.isNew)
        XCTAssertFalse(manualEpisode.isPendingAutoDownload)
    }

    func test_fetchNewEpisodes_scheduledRefreshReplacesNewAndQueuesAutoDownloadForImportedCollection() async {
        let channel = Channel(
            url: "https://www.youtube.com/@science/videos",
            name: "Science",
            hasCompletedInitialImport: true
        )
        var existingEpisode = makeEpisode(channelID: channel.id, videoID: "existing", daysAgo: 2)
        existingEpisode.isNew = true

        store = AppStore(
            stateFileURL: tempStateFile,
            appSupportURL: tempAppSupportDir,
            defaultEpisodesDirectory: defaultEpisodesDir,
            shouldLoadPersistentState: false,
            autoCheckDependencies: false,
            listVideosOverride: { _, _ in
                [
                    self.makeVideoInfo(videoID: "new-scheduled", daysAgo: 0),
                    self.makeVideoInfo(videoID: "existing", daysAgo: 2),
                ]
            }
        )
        store.episodesDirectory = tempDir
        store.channels = [channel]
        store.episodes = [existingEpisode]

        let didComplete = await store.fetchNewEpisodes(for: [channel.id], context: .scheduled)

        XCTAssertTrue(didComplete)
        XCTAssertFalse(try! XCTUnwrap(store.episodes.first(where: { $0.videoID == "existing" })).isNew)
        let scheduledEpisode = try! XCTUnwrap(store.episodes.first(where: { $0.videoID == "new-scheduled" }))
        XCTAssertTrue(scheduledEpisode.isNew)
        XCTAssertTrue(scheduledEpisode.isPendingAutoDownload)
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

    func test_deleteEpisodes_removesFromList() async {
        let chID = UUID()
        let ep1 = makeEpisode(channelID: chID, videoID: "v1")
        let ep2 = makeEpisode(channelID: chID, videoID: "v2")
        store.episodes = [ep1, ep2]
        await store.deleteEpisodes([ep1.id])
        XCTAssertEqual(store.episodes.count, 1)
        XCTAssertEqual(store.episodes[0].videoID, "v2")
    }

    func test_deleteEpisodes_removesMP3File() async throws {
        let chID = UUID()
        let ep = makeEpisode(channelID: chID, videoID: "v1", fileName: "v1.mp3")
        store.episodes = [ep]
        let episodesDir = Paths.ensureEpisodesDirectory(in: tempDir)
        let mp3Path = episodesDir.appendingPathComponent("v1.mp3")
        try Data("fake".utf8).write(to: mp3Path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mp3Path.path))

        await store.deleteEpisodes([ep.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: mp3Path.path))
    }

    func test_deleteEpisodes_removesSharedArtwork() async throws {
        let chID = UUID()
        let ep = makeEpisode(channelID: chID, videoID: "v1", fileName: "v1.mp3")
        store.episodes = [ep]
        let artworkPath = Paths.sharedArtworkURL(forVideoID: ep.videoID, in: tempDir)
        try FileManager.default.createDirectory(at: artworkPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fake".utf8).write(to: artworkPath)

        await store.deleteEpisodes([ep.id])

        XCTAssertFalse(FileManager.default.fileExists(atPath: artworkPath.path))
    }

    func test_deleteEpisodes_removesEmptySingleEpisodeSource() async {
        let source = Channel(
            url: "https://www.youtube.com/watch?v=solo123",
            name: "Solo Creator",
            sourceKind: .singleEpisode,
            relatedCollectionURL: "https://www.youtube.com/@solo/videos"
        )
        let episode = makeEpisode(channelID: source.id, videoID: "solo123")
        store.channels = [source]
        store.episodes = [episode]

        await store.deleteEpisodes([episode.id])

        XCTAssertTrue(store.channels.isEmpty)
        XCTAssertTrue(store.episodes.isEmpty)
    }

    func test_deleteEpisodes_removesNestedMP3File() async throws {
        let channel = makeChannel(name: "Science Weekly")
        let relativePath = Paths.relativeEpisodePath(forFileName: "v1.mp3", in: channel)
        let ep = makeEpisode(channelID: channel.id, videoID: "v1", fileName: relativePath)
        store.channels = [channel]
        store.episodes = [ep]
        let mp3Path = Paths.episodeFileURL(forRelativePath: relativePath, in: tempDir)
        try FileManager.default.createDirectory(at: mp3Path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fake".utf8).write(to: mp3Path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mp3Path.path))

        await store.deleteEpisodes([ep.id])

        XCTAssertFalse(FileManager.default.fileExists(atPath: mp3Path.path))
    }

    func test_deleteEpisodes_clearsQueuedDownloadStatus() async {
        let channel = makeChannel()
        let episode = makeEpisode(channelID: channel.id, videoID: "queued-delete")
        store.channels = [channel]
        store.episodes = [episode]
        store.activeDownloadStatus[episode.videoID] = DownloadStatus(progress: 0, phase: .queued)

        await store.deleteEpisodes([episode.id])

        XCTAssertTrue(store.activeDownloadStatus.isEmpty)
        XCTAssertTrue(store.episodes.isEmpty)
    }

    func test_deleteEpisodes_doesNotRemoveMatchingStemFromOtherChannelDirectory() async throws {
        let deletedChannel = makeChannel(name: "Delete Me")
        let keptChannel = makeChannel(name: "Keep Me")
        let deletedRelativePath = Paths.relativeEpisodePath(forFileName: "shared-name.mp3", in: deletedChannel)
        let keptRelativePath = Paths.relativeEpisodePath(forFileName: "shared-name.mp3", in: keptChannel)
        let deletedEpisode = makeEpisode(channelID: deletedChannel.id, videoID: "delete-me", fileName: deletedRelativePath)
        let keptEpisode = makeEpisode(channelID: keptChannel.id, videoID: "keep-me", fileName: keptRelativePath)
        store.channels = [deletedChannel, keptChannel]
        store.episodes = [deletedEpisode, keptEpisode]

        let deletedURL = Paths.episodeFileURL(forRelativePath: deletedRelativePath, in: tempDir)
        let keptURL = Paths.episodeFileURL(forRelativePath: keptRelativePath, in: tempDir)
        try FileManager.default.createDirectory(at: deletedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: keptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("delete".utf8).write(to: deletedURL)
        try Data("keep".utf8).write(to: keptURL)

        await store.deleteEpisodes([deletedEpisode.id])

        XCTAssertFalse(FileManager.default.fileExists(atPath: deletedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keptURL.path))
    }

    // MARK: - removeEpisodeDownloads

    func test_removeEpisodeDownloads_keepsEpisodeInList() async throws {
        let chID = UUID()
        let ep = makeEpisode(channelID: chID, videoID: "v1", fileName: "v1.mp3")
        store.episodes = [ep]
        let mp3Path = Paths.ensureEpisodesDirectory(in: tempDir).appendingPathComponent("v1.mp3")
        try Data("fake".utf8).write(to: mp3Path)

        await store.removeEpisodeDownloads([ep.id])

        XCTAssertEqual(store.episodes.count, 1, "Episode should remain in list")
        XCTAssertNil(store.episodes[0].fileName, "fileName should be cleared")
        XCTAssertFalse(store.episodes[0].isDownloaded, "isDownloaded should be false")
    }

    func test_removeEpisodeDownloads_deletesMP3File() async throws {
        let chID = UUID()
        let ep = makeEpisode(channelID: chID, videoID: "v1", fileName: "v1.mp3")
        store.episodes = [ep]
        let mp3Path = Paths.ensureEpisodesDirectory(in: tempDir).appendingPathComponent("v1.mp3")
        try Data("fake".utf8).write(to: mp3Path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mp3Path.path))

        await store.removeEpisodeDownloads([ep.id])

        XCTAssertFalse(FileManager.default.fileExists(atPath: mp3Path.path), "MP3 file should be deleted from disk")
    }

    func test_removeEpisodeDownloads_deletesSharedArtwork() async throws {
        let chID = UUID()
        let ep = makeEpisode(channelID: chID, videoID: "v1", fileName: "v1.mp3")
        store.episodes = [ep]
        let artworkPath = Paths.sharedArtworkURL(forVideoID: ep.videoID, in: tempDir)
        try FileManager.default.createDirectory(at: artworkPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("art".utf8).write(to: artworkPath)

        await store.removeEpisodeDownloads([ep.id])

        XCTAssertFalse(FileManager.default.fileExists(atPath: artworkPath.path), "Artwork should be deleted from shared storage")
    }

    func test_removeEpisodeDownloads_ignoresNonDownloadedEpisodes() async {
        let chID = UUID()
        let ep = makeEpisode(channelID: chID, videoID: "v1") // no fileName
        store.episodes = [ep]

        await store.removeEpisodeDownloads([ep.id])

        XCTAssertEqual(store.episodes.count, 1, "Episode should remain in list")
        XCTAssertNil(store.episodes[0].fileName, "fileName should still be nil")
    }

    // MARK: - deleteChannels

    func test_deleteChannels_removesEpisodes() async {
        let ch = makeChannel()
        store.channels = [ch]
        store.episodes = [makeEpisode(channelID: ch.id, videoID: "v1")]
        await store.deleteChannels([ch.id])
        XCTAssertTrue(store.channels.isEmpty)
        XCTAssertTrue(store.episodes.isEmpty)
    }

    func test_deleteChannels_removesManagedFilesArtworkAndChannelDirectory() async throws {
        let channel = makeChannel(name: "Science Weekly")
        let relativePath = Paths.relativeEpisodePath(forFileName: "episode.mp3", in: channel)
        let episode = makeEpisode(channelID: channel.id, videoID: "episode123", fileName: relativePath)
        store.channels = [channel]
        store.episodes = [episode]

        let episodeFileURL = try createDownloadedEpisodeFile(named: relativePath)
        let sidecarArtworkURL = Paths.managedEpisodeArtworkURL(forRelativeEpisodePath: relativePath, in: tempDir)
        try Data("jpg".utf8).write(to: sidecarArtworkURL)
        let sharedArtworkURL = Paths.sharedArtworkURL(forVideoID: episode.videoID, in: tempDir)
        try FileManager.default.createDirectory(
            at: sharedArtworkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("shared".utf8).write(to: sharedArtworkURL)

        await store.deleteChannels([channel.id])

        XCTAssertFalse(FileManager.default.fileExists(atPath: episodeFileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarArtworkURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sharedArtworkURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: Paths.channelEpisodesDir(for: channel, in: tempDir).path))
        XCTAssertTrue(store.channels.isEmpty)
        XCTAssertTrue(store.episodes.isEmpty)
    }

    func test_channelArtworkURL_prefersNewestDownloadedEpisodeArtwork() throws {
        let channel = makeChannel()
        let older = makeEpisode(channelID: channel.id, videoID: "older", daysAgo: 5, fileName: "older.mp3")
        let newer = makeEpisode(channelID: channel.id, videoID: "newer", daysAgo: 1, fileName: "newer.mp3")
        store.channels = [channel]
        store.episodes = [older, newer]
        let olderArtwork = Paths.sharedArtworkURL(forVideoID: "older", in: tempDir)
        let newerArtwork = Paths.sharedArtworkURL(forVideoID: "newer", in: tempDir)
        try FileManager.default.createDirectory(at: olderArtwork.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: olderArtwork)
        try Data("new".utf8).write(to: newerArtwork)

        XCTAssertEqual(store.channelArtworkURL(for: channel.id)?.lastPathComponent, "newer.jpg")
    }

    func test_sharedArtworkVisibleFromSecondMachineAndRegeneratesLocalFeedArtwork() throws {
        let channel = makeChannel(name: "Machine A Channel")
        let relativePath = Paths.relativeEpisodePath(forFileName: "machine-a.mp3", in: channel)
        store.episodesDirectory = defaultEpisodesDir
        _ = try createDownloadedEpisodeFile(named: relativePath)
        let episode = makeEpisode(channelID: channel.id, videoID: "machineA1", fileName: relativePath)
        store.channels = [channel]
        store.episodes = [episode]
        _ = try createSharedArtworkFile(videoID: episode.videoID, width: 1400, height: 1400)
        store.save()

        let machineBAppSupport = tempDir.appendingPathComponent("machine-b-app-support", isDirectory: true)
        try FileManager.default.createDirectory(at: machineBAppSupport, withIntermediateDirectories: true)
        let machineBStateFile = machineBAppSupport.appendingPathComponent("state.json")
        let machineBLocalData = try JSONSerialization.data(withJSONObject: [
            "episodesDirectory": defaultEpisodesDir.path,
            "serverPort": 9999,
            "autoFetchInterval": 0,
            "autoStartServer": false,
        ] as [String: Any])
        try machineBLocalData.write(to: machineBStateFile)

        let machineBStore = AppStore(
            stateFileURL: machineBStateFile,
            appSupportURL: machineBAppSupport,
            defaultEpisodesDirectory: defaultEpisodesDir,
            shouldLoadPersistentState: true,
            autoCheckDependencies: false
        )

        let sharedArtworkURL = Paths.sharedArtworkURL(forVideoID: episode.videoID, in: defaultEpisodesDir)
        let machineBFeedArtworkURL = Paths.feedArtworkURL(forVideoID: episode.videoID, in: Paths.serverDirectory(in: machineBAppSupport))
        XCTAssertEqual(machineBStore.artworkURL(for: episode)?.path, sharedArtworkURL.path)
        XCTAssertEqual(machineBStore.channelArtworkURL(for: channel.id)?.path, sharedArtworkURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: machineBFeedArtworkURL.path))
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

    private func writeLocalState(_ payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: tempStateFile)
    }

    private func writeSharedState(_ payload: [String: Any], in episodesDir: URL) throws {
        let syncDir = episodesDir.appendingPathComponent(Paths.syncDirectoryName)
        try FileManager.default.createDirectory(at: syncDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: Paths.sharedStateFile(in: episodesDir))
    }

    func test_load_prunesEpisodesWithoutMatchingChannels() throws {
        let validChannel = makeChannel(name: "Valid", urlHandle: "valid")
        let validEpisode = makeEpisode(channelID: validChannel.id, videoID: "keep")
        let orphanEpisode = makeEpisode(channelID: UUID(), videoID: "orphan")

        try writeLocalState([
            "episodesDirectory": defaultEpisodesDir.path,
            "serverPort": 8888,
            "autoFetchInterval": 0,
            "autoStartServer": false,
        ])
        try writeSharedState([
            "channels": [[
                "id": validChannel.id.uuidString,
                "url": validChannel.url,
                "name": validChannel.name,
                "dateAdded": validChannel.dateAdded.timeIntervalSince1970,
                "sourceKind": validChannel.sourceKind.rawValue,
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
                    "isNew": validEpisode.isNew,
                ],
                [
                    "id": orphanEpisode.id.uuidString,
                    "channelID": orphanEpisode.channelID.uuidString,
                    "videoID": orphanEpisode.videoID,
                    "title": orphanEpisode.title,
                    "publishDate": orphanEpisode.publishDate.timeIntervalSince1970,
                    "durationSeconds": orphanEpisode.durationSeconds,
                    "isPlayed": orphanEpisode.isPlayed,
                    "isNew": orphanEpisode.isNew,
                ],
            ],
        ], in: defaultEpisodesDir)

        let loadedStore = AppStore(
            stateFileURL: tempStateFile,
            appSupportURL: tempAppSupportDir,
            defaultEpisodesDirectory: defaultEpisodesDir,
            shouldLoadPersistentState: true,
            autoCheckDependencies: false
        )

        XCTAssertEqual(loadedStore.allEpisodesCount, 1)
        XCTAssertEqual(loadedStore.episodes.count, 1)
        XCTAssertEqual(loadedStore.episodes.first?.videoID, "keep")
    }

    func test_load_resetsMissingTemporaryEpisodesDirectoryToDefault() throws {
        let missingTempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try writeLocalState([
            "episodesDirectory": missingTempDirectory.path,
            "serverPort": 8888,
            "autoFetchInterval": 0,
            "autoStartServer": false,
        ])

        let loadedStore = AppStore(
            stateFileURL: tempStateFile,
            appSupportURL: tempAppSupportDir,
            defaultEpisodesDirectory: defaultEpisodesDir,
            shouldLoadPersistentState: true,
            autoCheckDependencies: false
        )

        XCTAssertEqual(loadedStore.episodesDirectory.standardizedFileURL, defaultEpisodesDir.standardizedFileURL)
    }

    func test_load_defaultsEpisodesDirectoryWhenStateOmitsIt() throws {
        try writeLocalState([
            "serverPort": 8888,
            "autoFetchInterval": 0,
            "autoStartServer": false,
        ])

        let loadedStore = AppStore(
            stateFileURL: tempStateFile,
            appSupportURL: tempAppSupportDir,
            defaultEpisodesDirectory: defaultEpisodesDir,
            shouldLoadPersistentState: true,
            autoCheckDependencies: false
        )

        XCTAssertEqual(loadedStore.episodesDirectory.standardizedFileURL, defaultEpisodesDir.standardizedFileURL)
    }

    func test_saveAndLoad_preservesServerHostAndServerPort() {
        store.serverHost = "custom.example.com"
        store.serverPort = 9999

        store.save()

        let reloadedStore = AppStore(
            stateFileURL: tempStateFile,
            appSupportURL: tempAppSupportDir,
            defaultEpisodesDirectory: defaultEpisodesDir,
            shouldLoadPersistentState: true,
            autoCheckDependencies: false
        )

        XCTAssertEqual(reloadedStore.serverHost, "custom.example.com")
        XCTAssertEqual(reloadedStore.serverPort, 9999)
    }

    func test_saveAndLoad_preservesChannelsAndEpisodesViaSharedState() {
        let channel = makeChannel()
        let episode = makeEpisode(channelID: channel.id, videoID: "sync1")
        store.episodesDirectory = defaultEpisodesDir
        store.channels = [channel]
        store.episodes = [episode]

        store.save()

        let reloadedStore = AppStore(
            stateFileURL: tempStateFile,
            appSupportURL: tempAppSupportDir,
            defaultEpisodesDirectory: defaultEpisodesDir,
            shouldLoadPersistentState: true,
            autoCheckDependencies: false
        )

        XCTAssertEqual(reloadedStore.channels.count, 1)
        XCTAssertEqual(reloadedStore.channels.first?.name, channel.name)
        XCTAssertEqual(reloadedStore.episodes.count, 1)
        XCTAssertEqual(reloadedStore.episodes.first?.videoID, "sync1")
    }

    func test_sharedState_channelsVisibleFromSecondMachineLocalState() throws {
        // Simulate Machine A: save channels and episodes to the shared episodes directory.
        let channel = makeChannel(name: "Machine A Channel")
        let episode = makeEpisode(channelID: channel.id, videoID: "machineA1")
        store.episodesDirectory = defaultEpisodesDir
        store.channels = [channel]
        store.episodes = [episode]
        store.save()

        // Simulate Machine B: its own local state file pointing at the same episodes directory
        // but with different machine-specific settings (e.g. different server port).
        let machineBStateFile = tempDir.appendingPathComponent("machine-b-state.json")
        let machineBLocalData = try JSONSerialization.data(withJSONObject: [
            "episodesDirectory": defaultEpisodesDir.path,
            "serverPort": 9999,
            "autoFetchInterval": 0,
            "autoStartServer": false,
        ] as [String: Any])
        try machineBLocalData.write(to: machineBStateFile)

        let machineBStore = AppStore(
            stateFileURL: machineBStateFile,
            appSupportURL: tempAppSupportDir,
            defaultEpisodesDirectory: defaultEpisodesDir,
            shouldLoadPersistentState: true,
            autoCheckDependencies: false
        )

        // Machine B sees Machine A's channels and episodes.
        XCTAssertEqual(machineBStore.channels.count, 1)
        XCTAssertEqual(machineBStore.channels.first?.name, "Machine A Channel")
        XCTAssertEqual(machineBStore.episodes.count, 1)
        XCTAssertEqual(machineBStore.episodes.first?.videoID, "machineA1")
        // Machine B keeps its own server settings.
        XCTAssertEqual(machineBStore.serverPort, 9999)
    }

    func test_switchEpisodesDirectory_loadsSharedStateFromNewDirectory() throws {
        // Simulate an existing shared state in a "cloud" directory.
        let cloudDir = tempDir.appendingPathComponent("cloud", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudDir, withIntermediateDirectories: true)
        let channel = makeChannel(name: "Cloud Channel")
        let episode = makeEpisode(channelID: channel.id, videoID: "cloud1")
        try writeSharedState([
            "channels": [["id": channel.id.uuidString, "url": channel.url,
                          "name": channel.name, "dateAdded": channel.dateAdded.timeIntervalSince1970,
                          "sourceKind": channel.sourceKind.rawValue]],
            "episodes": [["id": episode.id.uuidString, "channelID": episode.channelID.uuidString,
                          "videoID": episode.videoID, "title": episode.title,
                          "publishDate": episode.publishDate.timeIntervalSince1970,
                          "durationSeconds": episode.durationSeconds, "isPlayed": false, "isNew": false]],
        ], in: cloudDir)

        // Fresh-install store starts empty; switching to the cloud dir should load its shared state.
        XCTAssertTrue(store.channels.isEmpty)
        store.switchEpisodesDirectory(to: cloudDir)

        XCTAssertEqual(store.channels.count, 1)
        XCTAssertEqual(store.channels.first?.name, "Cloud Channel")
        XCTAssertEqual(store.episodes.count, 1)
        XCTAssertEqual(store.episodes.first?.videoID, "cloud1")
        XCTAssertEqual(store.episodesDirectory, cloudDir)
    }

    func test_switchEpisodesDirectory_doesNotOverwriteExistingSharedState() throws {
        // Mac A has channels/episodes in the cloud dir already.
        let cloudDir = tempDir.appendingPathComponent("cloud", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudDir, withIntermediateDirectories: true)
        let channel = makeChannel(name: "Existing Channel")
        try writeSharedState([
            "channels": [["id": channel.id.uuidString, "url": channel.url,
                          "name": channel.name, "dateAdded": channel.dateAdded.timeIntervalSince1970,
                          "sourceKind": channel.sourceKind.rawValue]],
            "episodes": [],
        ], in: cloudDir)

        // A fresh-install store (empty) switching to the cloud dir must not clobber the existing data.
        store.switchEpisodesDirectory(to: cloudDir)

        let sharedStateURL = Paths.sharedStateFile(in: cloudDir)
        let data = try Data(contentsOf: sharedStateURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let channels = json["channels"] as! [[String: Any]]
        XCTAssertEqual(channels.count, 1, "Existing shared state must not be overwritten with empty data")
    }

    func test_switchEpisodesDirectory_abortsWhenSharedStateExistsButIsUnreadable() throws {
        let cloudDir = tempDir.appendingPathComponent("cloud", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudDir, withIntermediateDirectories: true)

        // Write corrupt data (not valid JSON) to the shared state file.
        let syncDir = cloudDir.appendingPathComponent(Paths.syncDirectoryName)
        try FileManager.default.createDirectory(at: syncDir, withIntermediateDirectories: true)
        try Data("not valid json {{{".utf8).write(to: Paths.sharedStateFile(in: cloudDir))

        let originalDir = store.episodesDirectory
        store.switchEpisodesDirectory(to: cloudDir)

        // Directory must not change and existing channels must be preserved.
        XCTAssertEqual(store.episodesDirectory, originalDir, "Switch must abort when shared state is unreadable")
        XCTAssertTrue(store.channels.isEmpty)

        // The corrupt file must not be overwritten with empty data.
        let corruptData = try Data(contentsOf: Paths.sharedStateFile(in: cloudDir))
        XCTAssertEqual(String(data: corruptData, encoding: .utf8), "not valid json {{{")
    }

    func test_cleanupPartialArtifacts_removesOnlyMatchingFiles() async throws {
        let channel = makeChannel()
        let episode = makeEpisode(channelID: channel.id, videoID: "partial")
        store.channels = [channel]
        let episodesDir = Paths.ensureEpisodesDirectory(in: tempDir)

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
        let customEpisodesDir = tempDir.appendingPathComponent("custom-episodes", isDirectory: true)
        try FileManager.default.createDirectory(at: customEpisodesDir, withIntermediateDirectories: true)

        let channel = makeChannel()
        let downloadedEpisode = makeEpisode(channelID: channel.id, videoID: "reset-me", fileName: "reset-me.mp3")
        store.channels = [channel]
        store.episodes = [downloadedEpisode]
        store.episodesDirectory = customEpisodesDir
        store.serverPort = 9999
        store.autoFetchInterval = 24
        store.autoStartServer = true
        store.activeDownloadStatus = [
            "reset-me": DownloadStatus(progress: 0.5, phase: .convertingAudio)
        ]

        let episodesDir = Paths.ensureManagedEpisodesDirectory(in: customEpisodesDir)
        let audioFile = episodesDir.appendingPathComponent("reset-me.mp3")
        let showArtworkFile = Paths.showArtworkURL(in: feedDir)
        let feedAssetsDir = Paths.ensureFeedAssetsDirectory(in: feedDir)
        let feedAssetAudio = feedAssetsDir.appendingPathComponent("reset-me.mp3")
        try Data("audio".utf8).write(to: audioFile)
        try Data("cover".utf8).write(to: showArtworkFile)
        try Data("alias".utf8).write(to: feedAssetAudio)
        FeedGenerator.write(
            episodes: [downloadedEpisode],
            channels: [channel],
            baseURL: "http://localhost:9999",
            episodesDirectory: customEpisodesDir,
            to: feedDir
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
        XCTAssertEqual(store.episodesDirectory.standardizedFileURL, defaultEpisodesDir.standardizedFileURL)
        XCTAssertEqual(store.serverPort, 8888)
        XCTAssertEqual(store.autoFetchInterval, 0)
        XCTAssertFalse(store.autoStartServer)
        XCTAssertFalse(store.isServerRunning)
        XCTAssertFalse(store.hasActiveDownloads)
        XCTAssertTrue(store.activeDownloadStatus.isEmpty)
        XCTAssertEqual(store.statusMessage, "Ready")

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: episodesDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: Paths.feedFileURL(in: feedDir).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: showArtworkFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: feedAssetsDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: binDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logsDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logsDir.appendingPathComponent("recast.log").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempStateFile.path))

        let reloadedStore = AppStore(
            stateFileURL: tempStateFile,
            appSupportURL: tempAppSupportDir,
            defaultEpisodesDirectory: defaultEpisodesDir,
            shouldLoadPersistentState: true,
            autoCheckDependencies: false
        )

        XCTAssertTrue(reloadedStore.channels.isEmpty)
        XCTAssertTrue(reloadedStore.episodes.isEmpty)
        XCTAssertEqual(reloadedStore.episodesDirectory.standardizedFileURL, defaultEpisodesDir.standardizedFileURL)
        XCTAssertEqual(reloadedStore.serverPort, 8888)
        XCTAssertEqual(reloadedStore.autoFetchInterval, 0)
        XCTAssertFalse(reloadedStore.autoStartServer)
    }

    func test_resetToDefaults_preservesUnownedEpisodesDirectoryArtifacts() async throws {
        let customEpisodesDir = tempDir.appendingPathComponent("shared-episodes", isDirectory: true)
        try FileManager.default.createDirectory(at: customEpisodesDir, withIntermediateDirectories: true)

        let channel = makeChannel()
        let downloadedEpisode = makeEpisode(channelID: channel.id, videoID: "reset-me", fileName: "reset-me.mp3")
        let partialEpisode = makeEpisode(channelID: channel.id, videoID: "partial-me")
        store.channels = [channel]
        store.episodes = [downloadedEpisode, partialEpisode]
        store.episodesDirectory = customEpisodesDir

        let episodesDir = Paths.ensureManagedEpisodesDirectory(in: customEpisodesDir)
        let managedAudioFile = episodesDir.appendingPathComponent("reset-me.mp3")
        let managedPartialFile = episodesDir.appendingPathComponent("\(String(partialEpisode.suggestedFileName.dropLast(4))).webm")
        let unrelatedAudioFile = episodesDir.appendingPathComponent("keep-me.mp3")

        try Data("audio".utf8).write(to: managedAudioFile)
        try Data("partial".utf8).write(to: managedPartialFile)
        try Data("keep".utf8).write(to: unrelatedAudioFile)

        await store.resetToDefaults()

        XCTAssertFalse(FileManager.default.fileExists(atPath: managedAudioFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedPartialFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedAudioFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: episodesDir.path))
    }

    func test_resetToDefaults_removesNestedManagedArtifactsAndPrunesEmptyChannelFolder() async throws {
        let customEpisodesDir = tempDir.appendingPathComponent("nested-episodes", isDirectory: true)
        try FileManager.default.createDirectory(at: customEpisodesDir, withIntermediateDirectories: true)

        let channel = makeChannel(name: "Science Weekly")
        let relativePath = Paths.relativeEpisodePath(forFileName: "reset-me.mp3", in: channel)
        let downloadedEpisode = makeEpisode(channelID: channel.id, videoID: "reset-me", fileName: relativePath)
        store.channels = [channel]
        store.episodes = [downloadedEpisode]
        store.episodesDirectory = customEpisodesDir

        let channelDir = Paths.ensureManagedChannelEpisodesDirectory(for: channel, in: customEpisodesDir)
        let audioFile = Paths.episodeFileURL(forRelativePath: relativePath, in: customEpisodesDir)
        let artworkFile = Paths.sharedArtworkURL(forVideoID: downloadedEpisode.videoID, in: customEpisodesDir)
        try Data("audio".utf8).write(to: audioFile)
        try FileManager.default.createDirectory(at: artworkFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("art".utf8).write(to: artworkFile)

        await store.resetToDefaults()

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artworkFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: channelDir.path))
    }
}
