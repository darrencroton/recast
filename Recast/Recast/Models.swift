import Foundation

struct Channel: Identifiable, Codable, Hashable {
    var id: UUID
    var url: String
    var name: String
    var dateAdded: Date

    init(url: String, name: String) {
        self.id = UUID()
        self.url = url
        self.name = name
        self.dateAdded = .now
    }
}

struct Episode: Identifiable, Codable, Hashable {
    var id: UUID
    var channelID: UUID
    var videoID: String
    var title: String
    var publishDate: Date
    var durationSeconds: Int
    var fileName: String?
    var isPlayed: Bool

    var isDownloaded: Bool { fileName != nil }

    init(channelID: UUID, videoID: String, title: String, publishDate: Date, durationSeconds: Int) {
        self.id = UUID()
        self.channelID = channelID
        self.videoID = videoID
        self.title = title
        self.publishDate = publishDate
        self.durationSeconds = durationSeconds
        self.isPlayed = false
    }

    // Backwards-compatible decoding: isPlayed defaults to false if missing
    enum CodingKeys: String, CodingKey {
        case id, channelID, videoID, title, publishDate, durationSeconds, fileName, isPlayed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        channelID = try c.decode(UUID.self, forKey: .channelID)
        videoID = try c.decode(String.self, forKey: .videoID)
        title = try c.decode(String.self, forKey: .title)
        publishDate = try c.decode(Date.self, forKey: .publishDate)
        durationSeconds = try c.decode(Int.self, forKey: .durationSeconds)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
        isPlayed = try c.decodeIfPresent(Bool.self, forKey: .isPlayed) ?? false
    }

    var formattedDuration: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        let s = durationSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
