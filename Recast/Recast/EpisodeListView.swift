import SwiftUI

struct EpisodeListView: View {
    @Environment(AppStore.self) private var store
    let channelIDs: Set<UUID>
    let searchQuery: String
    @Binding var filterMode: EpisodeFilter
    @Binding var selectedEpisodeIDs: Set<UUID>
    let onActivateSelection: () -> Void

    private var episodes: [Episode] {
        store.filteredEpisodes(for: channelIDs, query: searchQuery, filter: filterMode)
    }

    private var showChannelName: Bool {
        channelIDs.isEmpty || channelIDs.count > 1
    }

    private var visibleEpisodeIDs: Set<UUID> {
        Set(episodes.map(\.id))
    }

    private var selectedEpisodesByID: [UUID: Episode] {
        Dictionary(uniqueKeysWithValues: episodes.map { ($0.id, $0) })
    }

    var body: some View {
        Group {
            if store.filteredEpisodes(for: channelIDs, query: "").isEmpty {
                ContentUnavailableView {
                    Label("No Episodes", systemImage: "waveform")
                } description: {
                    Text("Select a channel, then press Refresh to check for new episodes.")
                }
            } else if episodes.isEmpty {
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    Text("No episodes match the current filter.")
                }
            } else {
                List(episodes, selection: $selectedEpisodeIDs) { episode in
                    EpisodeRow(
                        episode: episode,
                        isDownloading: store.activeDownloads.contains(episode.videoID),
                        progress: store.downloadProgress[episode.videoID],
                        showChannelName: showChannelName
                    )
                    .tag(episode.id)
                    .contextMenu { episodeContextMenu(for: episode) }
                }
                .listStyle(.inset)
                .simultaneousGesture(TapGesture().onEnded {
                    onActivateSelection()
                })
            }
        }
        .navigationTitle(navigationTitle)
        .onChange(of: visibleEpisodeIDs) { _, newValue in
            selectedEpisodeIDs.formIntersection(newValue)
        }
        .onChange(of: selectedEpisodeIDs) { _, newValue in
            if !newValue.isEmpty {
                onActivateSelection()
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func episodeContextMenu(for episode: Episode) -> some View {
        let targetIDs = contextTargetIDs(for: episode.id)
        let targetEpisodes = targetIDs.compactMap { selectedEpisodesByID[$0] }

        if canDownload(targetEpisodes) {
            Button {
                Task { await store.downloadEpisodes(targetIDs) }
            } label: {
                Label(
                    targetIDs.count == 1 ? "Download Episode" : "Download Selected Episodes",
                    systemImage: "arrow.down.circle"
                )
            }
        }

        if targetIDs.count == 1, let targetEpisode = targetEpisodes.first, store.activeDownloads.contains(targetEpisode.videoID) {
            Button(role: .destructive) {
                store.stopDownload(videoID: targetEpisode.videoID)
            } label: {
                Label("Stop Download", systemImage: "stop.circle")
            }
        } else if targetIDs.count == 1, let targetEpisode = targetEpisodes.first, targetEpisode.isDownloaded {
            Divider()

            Button {
                store.togglePlayed(targetEpisode.id)
            } label: {
                Label(
                    targetEpisode.isPlayed ? "Mark as Unplayed" : "Mark as Played",
                    systemImage: targetEpisode.isPlayed ? "circle" : "checkmark.circle"
                )
            }

            Button {
                store.revealInFinder(targetEpisode)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
        }

        Divider()

        Button(role: .destructive) {
            store.deleteEpisodes(targetIDs)
            selectedEpisodeIDs.subtract(targetIDs)
        } label: {
            Label(
                targetIDs.count == 1 ? "Delete Episode" : "Delete Selected Episodes",
                systemImage: "trash"
            )
        }
    }

    private var navigationTitle: String {
        if channelIDs.isEmpty { return "All Episodes" }
        if channelIDs.count == 1,
           let ch = store.channels.first(where: { channelIDs.contains($0.id) }) {
            return ch.name
        }
        if channelIDs.count > 1 { return "\(channelIDs.count) Channels" }
        return "Episodes"
    }

    private func contextTargetIDs(for episodeID: UUID) -> Set<UUID> {
        selectedEpisodeIDs.contains(episodeID) ? selectedEpisodeIDs : [episodeID]
    }

    private func canDownload(_ episodes: [Episode]) -> Bool {
        episodes.contains {
            !$0.isDownloaded && !store.activeDownloads.contains($0.videoID)
        }
    }
}

// MARK: - Episode Row

struct EpisodeRow: View {
    let episode: Episode
    let isDownloading: Bool
    let progress: Double?
    let showChannelName: Bool
    @Environment(AppStore.self) private var store
    @State private var isHoveringActionControl = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(episode.title)
                    .font(.body)
                    .lineLimit(2)
                    .foregroundStyle(episode.isPlayed ? .secondary : .primary)

                HStack(spacing: 8) {
                    if showChannelName,
                       let channelName = store.channels.first(where: { $0.id == episode.channelID })?.name {
                        Text(channelName)
                        Text("·")
                    }
                    Text(episode.publishDate, style: .date)
                    Text("·")
                    Text(episode.formattedDuration)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            actionAccessory
                .frame(width: 24, height: 24)
                .onHover { isHovering in
                    isHoveringActionControl = isDownloading && isHovering
                }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var actionAccessory: some View {
        if isDownloading {
            if isHoveringActionControl {
                Button(role: .destructive) {
                    store.stopDownload(videoID: episode.videoID)
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Stop download")
            } else if let progress {
                CircularProgressView(progress: progress)
                    .frame(width: 22, height: 22)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        } else if episode.isDownloaded {
            Image(systemName: episode.isPlayed ? "checkmark.circle" : "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(episode.isPlayed ? Color.secondary : .green)
        } else {
            Button {
                Task { await store.downloadEpisode(episode) }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .help("Download episode")
        }
    }
}

// MARK: - Circular progress indicator

struct CircularProgressView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 2.5)
                .foregroundStyle(.quaternary)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .foregroundStyle(.tint)
                .rotationEffect(.degrees(-90))

            Text("\(Int(progress * 100))")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
