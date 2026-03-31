import XCTest
@testable import Recast

final class FeedGeneratorTests: XCTestCase {

    // MARK: - Setup / teardown

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeChannel(name: String = "Test Channel") -> Channel {
        Channel(url: "https://www.youtube.com/@test/videos", name: name)
    }

    private func makeEpisode(
        channelID: UUID,
        videoID: String = "vid001",
        title: String = "Test Episode",
        fileName: String? = "vid001.mp3",
        daysAgo: Int = 0
    ) -> Episode {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        var ep = Episode(
            channelID: channelID,
            videoID: videoID,
            title: title,
            publishDate: date,
            durationSeconds: 3600
        )
        ep.fileName = fileName
        return ep
    }

    private func feedContent() throws -> String {
        let feedURL = tempDir.appendingPathComponent("feed.xml")
        return try String(contentsOf: feedURL, encoding: .utf8)
    }

    // MARK: - xmlEscape

    func test_xmlEscape_ampersand() {
        XCTAssertEqual(FeedGenerator.xmlEscape("AT&T"), "AT&amp;T")
    }

    func test_xmlEscape_lessThan() {
        XCTAssertEqual(FeedGenerator.xmlEscape("<b>bold</b>"), "&lt;b&gt;bold&lt;/b&gt;")
    }

    func test_xmlEscape_greaterThan() {
        XCTAssertEqual(FeedGenerator.xmlEscape("a > b"), "a &gt; b")
    }

    func test_xmlEscape_doubleQuote() {
        XCTAssertEqual(FeedGenerator.xmlEscape("say \"hi\""), "say &quot;hi&quot;")
    }

    func test_xmlEscape_singleQuote() {
        XCTAssertEqual(FeedGenerator.xmlEscape("it's"), "it&apos;s")
    }

    func test_xmlEscape_allFiveSpecialChars() {
        XCTAssertEqual(FeedGenerator.xmlEscape("& < > \" '"), "&amp; &lt; &gt; &quot; &apos;")
    }

    func test_xmlEscape_plainTextUnchanged() {
        XCTAssertEqual(FeedGenerator.xmlEscape("hello world 123"), "hello world 123")
    }

    func test_xmlEscape_emptyString() {
        XCTAssertEqual(FeedGenerator.xmlEscape(""), "")
    }

    func test_xmlEscape_multipleAmpersands() {
        XCTAssertEqual(FeedGenerator.xmlEscape("A&B&C"), "A&amp;B&amp;C")
    }

    // MARK: - formatDuration

    func test_formatDuration_zero() {
        XCTAssertEqual(FeedGenerator.formatDuration(0), "00:00:00")
    }

    func test_formatDuration_secondsOnly() {
        XCTAssertEqual(FeedGenerator.formatDuration(45), "00:00:45")
    }

    func test_formatDuration_minutesAndSeconds() {
        XCTAssertEqual(FeedGenerator.formatDuration(125), "00:02:05")
    }

    func test_formatDuration_allComponentsPadded() {
        XCTAssertEqual(FeedGenerator.formatDuration(3661), "01:01:01")
    }

    func test_formatDuration_largeHours() {
        XCTAssertEqual(FeedGenerator.formatDuration(36_000), "10:00:00")
    }

    func test_formatDuration_secondsPadded() {
        XCTAssertEqual(FeedGenerator.formatDuration(65), "00:01:05")
    }

    // MARK: - rfc2822

    func test_rfc2822_knownDate() {
        var comps = DateComponents()
        comps.year = 2024; comps.month = 1; comps.day = 15
        comps.hour = 12; comps.minute = 30; comps.second = 0
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(FeedGenerator.rfc2822(date), "Mon, 15 Jan 2024 12:30:00 +0000")
    }

    func test_rfc2822_startsWithDayAbbreviation() {
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let result = FeedGenerator.rfc2822(Date())
        XCTAssertTrue(days.contains(where: { result.hasPrefix($0) }), "Expected RFC 2822 string to start with a day abbreviation, got: \(result)")
    }

    func test_rfc2822_containsUTCOffset() {
        XCTAssertTrue(FeedGenerator.rfc2822(Date()).hasSuffix("+0000"))
    }

    // MARK: - write(): output file

    func test_write_createsFeedXMLFile() {
        let channel = makeChannel()
        FeedGenerator.write(episodes: [], channels: [channel], baseURL: "http://localhost:8888", to: tempDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("feed.xml").path))
    }

    func test_write_validXMLDeclaration() throws {
        FeedGenerator.write(episodes: [], channels: [makeChannel()], baseURL: "http://localhost:8888", to: tempDir)
        XCTAssertTrue(try feedContent().hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
    }

    func test_write_containsRSSRoot() throws {
        FeedGenerator.write(episodes: [], channels: [makeChannel()], baseURL: "http://localhost:8888", to: tempDir)
        let content = try feedContent()
        XCTAssertTrue(content.contains("<rss version=\"2.0\""))
        XCTAssertTrue(content.contains("</rss>"))
    }

    func test_write_containsiTunesNamespace() throws {
        FeedGenerator.write(episodes: [], channels: [makeChannel()], baseURL: "http://localhost:8888", to: tempDir)
        XCTAssertTrue(try feedContent().contains("xmlns:itunes"))
    }

    // MARK: - write(): episode inclusion/exclusion

    func test_write_includesEpisodeWithFileName() throws {
        let channel = makeChannel()
        let ep = makeEpisode(channelID: channel.id, videoID: "vid001", title: "My Talk", fileName: "vid001.mp3")
        FeedGenerator.write(episodes: [ep], channels: [channel], baseURL: "http://localhost:8888", to: tempDir)
        let content = try feedContent()
        XCTAssertTrue(content.contains("My Talk"))
        XCTAssertTrue(content.contains("vid001"))
    }

    func test_write_excludesEpisodeWithNilFileName() throws {
        let channel = makeChannel()
        let ep = makeEpisode(channelID: channel.id, videoID: "skipped99", title: "Not Downloaded", fileName: nil)
        FeedGenerator.write(episodes: [ep], channels: [channel], baseURL: "http://localhost:8888", to: tempDir)
        let content = try feedContent()
        XCTAssertFalse(content.contains("Not Downloaded"))
        XCTAssertFalse(content.contains("skipped99"))
    }

    func test_write_mixedEpisodes_onlyDownloadedAppear() throws {
        let channel = makeChannel()
        let downloaded = makeEpisode(channelID: channel.id, videoID: "d001", title: "Downloaded", fileName: "d001.mp3")
        let pending = makeEpisode(channelID: channel.id, videoID: "p001", title: "Pending", fileName: nil)
        FeedGenerator.write(episodes: [downloaded, pending], channels: [channel], baseURL: "http://localhost:8888", to: tempDir)
        let content = try feedContent()
        XCTAssertTrue(content.contains("Downloaded"))
        XCTAssertFalse(content.contains("Pending"))
    }

    // MARK: - write(): URLs and identifiers

    func test_write_enclosureURLUsesBaseURLAndFileName() throws {
        let channel = makeChannel()
        let ep = makeEpisode(channelID: channel.id, videoID: "vid003", title: "Test", fileName: "vid003.mp3")
        FeedGenerator.write(episodes: [ep], channels: [channel], baseURL: "http://localhost:9999", to: tempDir)
        XCTAssertTrue(try feedContent().contains("http://localhost:9999/episodes/vid003.mp3"))
    }

    func test_write_guidIsVideoID() throws {
        let channel = makeChannel()
        let ep = makeEpisode(channelID: channel.id, videoID: "uniqueGUID99", fileName: "uniqueGUID99.mp3")
        FeedGenerator.write(episodes: [ep], channels: [channel], baseURL: "http://localhost:8888", to: tempDir)
        XCTAssertTrue(try feedContent().contains("<guid isPermaLink=\"false\">uniqueGUID99</guid>"))
    }

    func test_write_youTubeLinkPresentForEpisode() throws {
        let channel = makeChannel()
        let ep = makeEpisode(channelID: channel.id, videoID: "abc456", fileName: "abc456.mp3")
        FeedGenerator.write(episodes: [ep], channels: [channel], baseURL: "http://localhost:8888", to: tempDir)
        XCTAssertTrue(try feedContent().contains("https://www.youtube.com/watch?v=abc456"))
    }

    // MARK: - write(): XML escaping

    func test_write_escapesAmpersandInTitle() throws {
        let channel = makeChannel()
        let ep = makeEpisode(channelID: channel.id, videoID: "v1", title: "Science & Nature", fileName: "v1.mp3")
        FeedGenerator.write(episodes: [ep], channels: [channel], baseURL: "http://localhost:8888", to: tempDir)
        let content = try feedContent()
        XCTAssertTrue(content.contains("Science &amp; Nature"))
        XCTAssertFalse(content.contains("<title>Science & Nature<"))
    }

    func test_write_escapesAngleBracketsInTitle() throws {
        let channel = makeChannel()
        let ep = makeEpisode(channelID: channel.id, videoID: "v2", title: "Talk: <AI> Systems", fileName: "v2.mp3")
        FeedGenerator.write(episodes: [ep], channels: [channel], baseURL: "http://localhost:8888", to: tempDir)
        let content = try feedContent()
        XCTAssertTrue(content.contains("Talk: &lt;AI&gt; Systems"))
    }

    func test_write_escapesSpecialCharsInChannelName() throws {
        let channel = makeChannel(name: "Channel & \"More\"")
        FeedGenerator.write(episodes: [], channels: [channel], baseURL: "http://localhost:8888", to: tempDir)
        let content = try feedContent()
        XCTAssertTrue(content.contains("Channel &amp; &quot;More&quot;"))
    }

    // MARK: - write(): channel metadata

    func test_write_channelNameAppearsInFeed() throws {
        let channel = makeChannel(name: "Science Weekly")
        let ep = makeEpisode(channelID: channel.id, fileName: "v.mp3")
        FeedGenerator.write(episodes: [ep], channels: [channel], baseURL: "http://localhost:8888", to: tempDir)
        XCTAssertTrue(try feedContent().contains("Science Weekly"))
    }

    func test_write_atomSelfLinkUsesBaseURL() throws {
        let channel = makeChannel()
        FeedGenerator.write(episodes: [], channels: [channel], baseURL: "http://localhost:1234", to: tempDir)
        XCTAssertTrue(try feedContent().contains("http://localhost:1234/feed.xml"))
    }

    // MARK: - write(): episode ordering

    func test_write_preservesInputOrder() throws {
        let channel = makeChannel()
        let first = makeEpisode(channelID: channel.id, videoID: "first", title: "First", fileName: "first.mp3", daysAgo: 1)
        let second = makeEpisode(channelID: channel.id, videoID: "second", title: "Second", fileName: "second.mp3", daysAgo: 10)
        FeedGenerator.write(episodes: [first, second], channels: [channel], baseURL: "http://localhost:8888", to: tempDir)
        let content = try feedContent()
        let firstRange = content.range(of: "first")!
        let secondRange = content.range(of: "second")!
        XCTAssertTrue(firstRange.lowerBound < secondRange.lowerBound, "write() should preserve the order of episodes it receives")
    }

    // MARK: - write(): empty inputs

    func test_write_emptyEpisodes_producesValidFeed() throws {
        FeedGenerator.write(episodes: [], channels: [makeChannel()], baseURL: "http://localhost:8888", to: tempDir)
        let content = try feedContent()
        XCTAssertTrue(content.contains("<channel>"))
        XCTAssertFalse(content.contains("<item>"))
    }
}
