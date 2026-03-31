import XCTest
@testable import Recast

final class StoreTests: XCTestCase {

    private func makeStore() -> AppStore {
        let store = AppStore()
        store.channels = []
        store.episodes = []
        return store
    }

    private func makeSampleEpisodes(channelID: UUID) -> [Episode] {
        var eps: [Episode] = []
        for i in 0..<5 {
            var ep = Episode(
                channelID: channelID,
                videoID: "vid\(i)",
                title: "Episode \(i)",
                publishDate: Date(timeIntervalSince1970: Double(i * 86400)),
                durationSeconds: 300 + i * 60
            )
            if i < 3 { ep.fileName = "vid\(i).mp3" }
            if i == 0 { ep.isPlayed = true }
            eps.append(ep)
        }
        return eps
    }

    // MARK: - URL normalisation

    func testNormalizeYouTubeURL_mobileToDesktop() {
        let store = makeStore()
        let result = store.normalizeYouTubeURL("https://m.youtube.com/@creator")
        XCTAssertTrue(result.hasPrefix("https://www.youtube.com"))
        XCTAssertFalse(result.contains("m.youtube.com"))
    }

    func testNormalizeYouTubeURL_addsVideosSuffix() {
        let store = makeStore()
        let result = store.normalizeYouTubeURL("https://www.youtube.com/@creator")
        XCTAssertTrue(result.hasSuffix("/videos"))
    }

    func testNormalizeYouTubeURL_noDoubleVideosSuffix() {
        let store = makeStore()
        let result = store.normalizeYouTubeURL("https://www.youtube.com/@creator/videos")
        XCTAssertEqual(result, "https://www.youtube.com/@creator/videos")
    }

    func testNormalizeYouTubeURL_trailingSlash() {
        let store = makeStore()
        let result = store.normalizeYouTubeURL("https://www.youtube.com/@creator/")
        XCTAssertTrue(result.hasSuffix("/videos"))
    }

    func testNormalizeYouTubeURL_playlistUntouched() {
        let store = makeStore()
        let result = store.normalizeYouTubeURL("https://www.youtube.com/playlist?list=PLabc")
        XCTAssertEqual(result, "https://www.youtube.com/playlist?list=PLabc")
    }

    // MARK: - Episode filtering

    func testFilteredEpisodes_allChannels() {
        let store = makeStore()
        let chID = UUID()
        store.episodes = makeSampleEpisodes(channelID: chID)
        let result = store.filteredEpisodes(for: Set(), query: "")
        XCTAssertEqual(result.count, 5)
        // Should be sorted newest first
        XCTAssertTrue(result.first!.publishDate >= result.last!.publishDate)
    }

    func testFilteredEpisodes_singleChannel() {
        let store = makeStore()
        let chA = UUID()
        let chB = UUID()
        store.episodes = makeSampleEpisodes(channelID: chA) + [
            Episode(channelID: chB, videoID: "other", title: "Other",
                    publishDate: .now, durationSeconds: 100)
        ]
        let result = store.filteredEpisodes(for: [chA], query: "")
        XCTAssertEqual(result.count, 5)
        XCTAssertTrue(result.allSatisfy { $0.channelID == chA })
    }

    func testFilteredEpisodes_searchQuery() {
        let store = makeStore()
        let chID = UUID()
        store.episodes = makeSampleEpisodes(channelID: chID)
        let result = store.filteredEpisodes(for: Set(), query: "Episode 2")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Episode 2")
    }

    func testFilteredEpisodes_caseInsensitiveSearch() {
        let store = makeStore()
        let chID = UUID()
        store.episodes = makeSampleEpisodes(channelID: chID)
        let result = store.filteredEpisodes(for: Set(), query: "episode 3")
        XCTAssertEqual(result.count, 1)
    }

    func testFilteredEpisodes_noMatch() {
        let store = makeStore()
        let chID = UUID()
        store.episodes = makeSampleEpisodes(channelID: chID)
        let result = store.filteredEpisodes(for: Set(), query: "nonexistent")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Toggle played

    func testTogglePlayed() {
        let store = makeStore()
        let chID = UUID()
        store.episodes = makeSampleEpisodes(channelID: chID)
        let epID = store.episodes[1].id
        XCTAssertFalse(store.episodes[1].isPlayed)

        store.togglePlayed(epID)
        XCTAssertTrue(store.episodes[1].isPlayed)

        store.togglePlayed(epID)
        XCTAssertFalse(store.episodes[1].isPlayed)
    }

    // MARK: - Delete episodes

    func testDeleteEpisodes() {
        let store = makeStore()
        let chID = UUID()
        store.episodes = makeSampleEpisodes(channelID: chID)
        let toDelete = Set([store.episodes[0].id, store.episodes[1].id])

        store.deleteEpisodes(toDelete)
        XCTAssertEqual(store.episodes.count, 3)
        XCTAssertTrue(store.episodes.allSatisfy { !toDelete.contains($0.id) })
    }

    // MARK: - Remove channels

    func testRemoveChannelsRemovesEpisodes() {
        let store = makeStore()
        let ch = Channel(url: "https://www.youtube.com/@test/videos", name: "Test")
        store.channels = [ch]
        store.episodes = makeSampleEpisodes(channelID: ch.id)

        store.removeChannels([ch.id])
        XCTAssertTrue(store.channels.isEmpty)
        XCTAssertTrue(store.episodes.isEmpty)
    }

    // MARK: - Episodes helper

    func testEpisodesForChannel() {
        let store = makeStore()
        let chA = UUID()
        let chB = UUID()
        store.episodes = makeSampleEpisodes(channelID: chA) + [
            Episode(channelID: chB, videoID: "b1", title: "B1",
                    publishDate: .now, durationSeconds: 100)
        ]
        let result = store.episodes(for: chA)
        XCTAssertEqual(result.count, 5)
        XCTAssertTrue(result.allSatisfy { $0.channelID == chA })
    }

    // MARK: - Feed URL

    func testFeedURLContainsPort() {
        let store = makeStore()
        store.serverPort = 9999
        XCTAssertTrue(store.feedURL.contains("9999"))
        XCTAssertTrue(store.feedURL.hasSuffix("/feed.xml"))
    }

    // MARK: - Settings persistence shape

    func testAutoFetchIntervalDefaults() {
        let store = makeStore()
        XCTAssertEqual(store.autoFetchInterval, 0)
        XCTAssertFalse(store.autoStartServer)
    }
}
