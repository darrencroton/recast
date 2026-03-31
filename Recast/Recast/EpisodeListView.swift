import SwiftUI

struct EpisodeListView: View {
    @Environment(AppStore.self) private var store
    let channelIDs: Set<UUID>

    private var episodes: [Episode] {
        let filtered = channelIDs.isEmpty
            ? store.episodes
            : store.episodes.filter { channelIDs.contains($0.channelID) }
        return filtered.sorted { $0.publishDate > $1.publishDate }
    }

    var body: some View {
        Group {
            if episodes.isEmpty {
                ContentUnavailableView {
                    Label("No Episodes", systemImage: "waveform")
                } description: {
                    Text("Press Fetch to check for new episodes.")
                }
            } else {
                List(episodes) { episode in
                    EpisodeRow(episode: episode, isDownloading: store.activeDownloads.contains(episode.videoID))
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(navigationTitle)
    }

    private var navigationTitle: String {
        if channelIDs.count == 1,
           let ch = store.channels.first(where: { channelIDs.contains($0.id) }) {
            return ch.name
        }
        if channelIDs.count > 1 { return "\(channelIDs.count) Channels" }
        return "All Episodes"
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let isDownloading: Bool

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(episode.title)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(episode.publishDate, style: .date)
                    Text("·")
                    Text(episode.formattedDuration)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isDownloading {
            ProgressView()
                .controlSize(.small)
        } else if episode.isDownloaded {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
        }
    }
}
