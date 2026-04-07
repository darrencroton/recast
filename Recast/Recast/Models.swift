import Foundation

enum EpisodeFilter: String, CaseIterable {
    case all = "All"
    case downloaded = "Downloaded"
    case new = "New"
    case unplayed = "Unplayed"

    var sidebarTitle: String {
        switch self {
        case .all:
            return "All Episodes"
        case .downloaded:
            return "Downloaded"
        case .new:
            return "New"
        case .unplayed:
            return "Unplayed"
        }
    }
}

enum DownloadPhase: Equatable {
    case queued
    case preparing
    case fetchingArtwork
    case downloadingAudio
    case convertingAudio
    case embeddingMetadata
    case embeddingArtwork

    var label: String {
        switch self {
        case .queued:
            return "Queued for download"
        case .preparing:
            return "Preparing download"
        case .fetchingArtwork:
            return "Fetching artwork"
        case .downloadingAudio:
            return "Downloading source audio"
        case .convertingAudio:
            return "Converting to MP3"
        case .embeddingMetadata:
            return "Embedding metadata"
        case .embeddingArtwork:
            return "Embedding artwork"
        }
    }
}

struct DownloadStatus: Equatable {
    var progress: Double
    var phase: DownloadPhase
}

enum ChannelSourceKind: String, Codable, Hashable {
    case collection
    case singleEpisode

    var sidebarSubtitlePrefix: String {
        switch self {
        case .collection:
            return ""
        case .singleEpisode:
            return "Saved "
        }
    }
}

struct Channel: Identifiable, Codable, Hashable {
    var id: UUID
    var url: String
    var name: String
    var dateAdded: Date
    var sourceKind: ChannelSourceKind
    var relatedCollectionURL: String?

    init(
        url: String,
        name: String,
        sourceKind: ChannelSourceKind = .collection,
        relatedCollectionURL: String? = nil
    ) {
        self.id = UUID()
        self.url = url
        self.name = name
        self.dateAdded = .now
        self.sourceKind = sourceKind
        self.relatedCollectionURL = relatedCollectionURL
    }

    var isSingleEpisodeSource: Bool {
        sourceKind == .singleEpisode
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
    var isNew: Bool

    var isDownloaded: Bool { fileName != nil }

    init(channelID: UUID, videoID: String, title: String, publishDate: Date, durationSeconds: Int) {
        self.id = UUID()
        self.channelID = channelID
        self.videoID = videoID
        self.title = title
        self.publishDate = publishDate
        self.durationSeconds = durationSeconds
        self.isPlayed = false
        self.isNew = false
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

    var suggestedFileName: String {
        "\(Self.fileDatePrefix(for: publishDate)) - \(Self.sanitizedFileComponent(from: title, fallback: videoID)) [\(videoID)].mp3"
    }

    static func sanitizedFileComponent(from value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "-_()[]&,.'"))

        let cleaned = value
            .components(separatedBy: allowed.inverted)
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let limited = String(cleaned.prefix(120))
        return limited.isEmpty ? fallback : limited
    }

    static func fileDatePrefix(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }
}
