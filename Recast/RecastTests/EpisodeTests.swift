import XCTest
@testable import Recast

final class EpisodeTests: XCTestCase {

    // MARK: - Helpers

    private func makeEpisode(durationSeconds: Int, fileName: String? = nil) -> Episode {
        var ep = Episode(
            channelID: UUID(),
            videoID: "abc123",
            title: "Test Episode",
            publishDate: .now,
            durationSeconds: durationSeconds
        )
        ep.fileName = fileName
        return ep
    }

    // MARK: - isDownloaded

    func test_isDownloaded_false_whenFileNameIsNil() {
        XCTAssertFalse(makeEpisode(durationSeconds: 60).isDownloaded)
    }

    func test_isDownloaded_true_whenFileNameIsSet() {
        XCTAssertTrue(makeEpisode(durationSeconds: 60, fileName: "abc123.mp3").isDownloaded)
    }

    func test_isDownloaded_true_afterAssigningFileName() {
        var ep = makeEpisode(durationSeconds: 60)
        XCTAssertFalse(ep.isDownloaded)
        ep.fileName = "abc123.mp3"
        XCTAssertTrue(ep.isDownloaded)
    }

    // MARK: - formattedDuration

    func test_formattedDuration_zero() {
        XCTAssertEqual(makeEpisode(durationSeconds: 0).formattedDuration, "0:00")
    }

    func test_formattedDuration_secondsOnly_belowMinute() {
        XCTAssertEqual(makeEpisode(durationSeconds: 59).formattedDuration, "0:59")
    }

    func test_formattedDuration_exactlyOneMinute() {
        XCTAssertEqual(makeEpisode(durationSeconds: 60).formattedDuration, "1:00")
    }

    func test_formattedDuration_minutesAndSeconds() {
        XCTAssertEqual(makeEpisode(durationSeconds: 90).formattedDuration, "1:30")
    }

    func test_formattedDuration_secondsPaddedToTwoDigits() {
        XCTAssertEqual(makeEpisode(durationSeconds: 65).formattedDuration, "1:05")
    }

    func test_formattedDuration_justUnderOneHour() {
        XCTAssertEqual(makeEpisode(durationSeconds: 3599).formattedDuration, "59:59")
    }

    func test_formattedDuration_exactlyOneHour() {
        XCTAssertEqual(makeEpisode(durationSeconds: 3600).formattedDuration, "1:00:00")
    }

    func test_formattedDuration_hoursMinutesAndSeconds() {
        XCTAssertEqual(makeEpisode(durationSeconds: 3661).formattedDuration, "1:01:01")
    }

    func test_formattedDuration_hoursWithPaddedMinutesAndSeconds() {
        XCTAssertEqual(makeEpisode(durationSeconds: 3605).formattedDuration, "1:00:05")
    }

    func test_formattedDuration_largeValue() {
        // 10h 30m 5s
        XCTAssertEqual(makeEpisode(durationSeconds: 37_805).formattedDuration, "10:30:05")
    }
}
