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
    var hasCompletedInitialImport: Bool

    init(
        url: String,
        name: String,
        sourceKind: ChannelSourceKind = .collection,
        relatedCollectionURL: String? = nil,
        hasCompletedInitialImport: Bool = false
    ) {
        self.id = UUID()
        self.url = url
        self.name = name
        self.dateAdded = .now
        self.sourceKind = sourceKind
        self.relatedCollectionURL = relatedCollectionURL
        self.hasCompletedInitialImport = sourceKind == .singleEpisode ? true : hasCompletedInitialImport
    }

    var isSingleEpisodeSource: Bool {
        sourceKind == .singleEpisode
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case name
        case dateAdded
        case sourceKind
        case relatedCollectionURL
        case hasCompletedInitialImport
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        name = try container.decode(String.self, forKey: .name)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        sourceKind = try container.decode(ChannelSourceKind.self, forKey: .sourceKind)
        relatedCollectionURL = try container.decodeIfPresent(String.self, forKey: .relatedCollectionURL)
        hasCompletedInitialImport = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedInitialImport)
            ?? (sourceKind == .singleEpisode)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(name, forKey: .name)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encode(sourceKind, forKey: .sourceKind)
        try container.encodeIfPresent(relatedCollectionURL, forKey: .relatedCollectionURL)
        try container.encode(hasCompletedInitialImport, forKey: .hasCompletedInitialImport)
    }
}

enum EpisodeMetadataSource: String, Codable, Hashable {
    case exact
    case collectionListing
    case legacy
}

struct Episode: Identifiable, Codable, Hashable {
    var id: UUID
    var channelID: UUID
    var videoID: String
    var title: String
    var publishDate: Date
    var durationSeconds: Int
    var metadataSource: EpisodeMetadataSource
    var fileName: String?
    var isPlayed: Bool
    var isNew: Bool
    var isPendingAutoDownload: Bool
    var lastAutoDownloadAttemptAt: Date?

    var isDownloaded: Bool { fileName != nil }

    init(
        channelID: UUID,
        videoID: String,
        title: String,
        publishDate: Date,
        durationSeconds: Int,
        metadataSource: EpisodeMetadataSource = .exact
    ) {
        self.id = UUID()
        self.channelID = channelID
        self.videoID = videoID
        self.title = title
        self.publishDate = publishDate
        self.durationSeconds = durationSeconds
        self.metadataSource = metadataSource
        self.isPlayed = false
        self.isNew = false
        self.isPendingAutoDownload = false
        self.lastAutoDownloadAttemptAt = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case channelID
        case videoID
        case title
        case publishDate
        case durationSeconds
        case metadataSource
        case fileName
        case isPlayed
        case isNew
        case isPendingAutoDownload
        case lastAutoDownloadAttemptAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        channelID = try container.decode(UUID.self, forKey: .channelID)
        videoID = try container.decode(String.self, forKey: .videoID)
        title = try container.decode(String.self, forKey: .title)
        publishDate = try container.decode(Date.self, forKey: .publishDate)
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        metadataSource = try container.decodeIfPresent(EpisodeMetadataSource.self, forKey: .metadataSource) ?? .legacy
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        isPlayed = try container.decodeIfPresent(Bool.self, forKey: .isPlayed) ?? false
        isNew = try container.decodeIfPresent(Bool.self, forKey: .isNew) ?? false
        isPendingAutoDownload = try container.decodeIfPresent(Bool.self, forKey: .isPendingAutoDownload) ?? false
        lastAutoDownloadAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastAutoDownloadAttemptAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(channelID, forKey: .channelID)
        try container.encode(videoID, forKey: .videoID)
        try container.encode(title, forKey: .title)
        try container.encode(publishDate, forKey: .publishDate)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(metadataSource, forKey: .metadataSource)
        try container.encodeIfPresent(fileName, forKey: .fileName)
        try container.encode(isPlayed, forKey: .isPlayed)
        try container.encode(isNew, forKey: .isNew)
        try container.encode(isPendingAutoDownload, forKey: .isPendingAutoDownload)
        try container.encodeIfPresent(lastAutoDownloadAttemptAt, forKey: .lastAutoDownloadAttemptAt)
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
