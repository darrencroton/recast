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

    private var isRefreshingCurrentScope: Bool {
        if channelIDs.isEmpty {
            return store.isFetching
        }
        return !store.activeRefreshChannelIDs.isDisjoint(with: channelIDs)
    }

    var body: some View {
        Group {
            if store.filteredEpisodes(for: channelIDs, query: "").isEmpty, isRefreshingCurrentScope {
                ContentUnavailableView {
                    Label("Discovering Episodes", systemImage: "arrow.clockwise")
                } description: {
                    Text("Fetching episodes for the current selection.")
                }
            } else if store.filteredEpisodes(for: channelIDs, query: "").isEmpty {
                ContentUnavailableView {
                    Label("No Episodes", systemImage: "waveform")
                } description: {
                    Text("Select a source, then press Refresh to check for episodes.")
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
                        downloadStatus: store.downloadStatus(for: episode),
                        showChannelName: showChannelName,
                        onStartDownload: {
                            selectedEpisodeIDs = [episode.id]
                            onActivateSelection()
                        }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                selectedEpisodeIDs = targetIDs
                onActivateSelection()
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
        if channelIDs.count > 1 { return "\(channelIDs.count) Sources" }
        return "Episodes"
    }

    private func contextTargetIDs(for episodeID: UUID) -> Set<UUID> {
        selectedEpisodeIDs.contains(episodeID) ? selectedEpisodeIDs : [episodeID]
    }

    private func canDownload(_ episodes: [Episode]) -> Bool {
        episodes.contains {
            !$0.isDownloaded && store.downloadStatus(for: $0) == nil
        }
    }
}

// MARK: - Episode Row

struct EpisodeRow: View {
    let episode: Episode
    let downloadStatus: DownloadStatus?
    let showChannelName: Bool
    let onStartDownload: () -> Void
    @Environment(AppStore.self) private var store
    @State private var isHoveringActionControl = false

    private var channelName: String {
        store.channels.first(where: { $0.id == episode.channelID })?.name ?? "Unknown Source"
    }

    private var isCurrentDownload: Bool {
        store.activeDownloads.contains(episode.videoID)
    }

    var body: some View {
        HStack(spacing: 12) {
            EpisodeArtworkView(artworkURL: store.artworkURL(for: episode))

            VStack(alignment: .leading, spacing: 3) {
                Text(episode.title)
                    .font(.body)
                    .lineLimit(2)
                    .foregroundStyle(episode.isPlayed ? .secondary : .primary)

                HStack(spacing: 8) {
                    if showChannelName {
                        Text(channelName)
                        Text("·")
                    }
                    Text(episode.publishDate, style: .date)
                    Text("·")
                    Text(episode.formattedDuration)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let downloadStatus {
                    Text(downloadStatus.phase.label)
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }

            Spacer()

            actionAccessory
                .frame(width: 24, height: 24)
                .onHover { isHovering in
                    isHoveringActionControl = isCurrentDownload && isHovering
                }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var actionAccessory: some View {
        if let downloadStatus {
            if isCurrentDownload && isHoveringActionControl {
                Button(role: .destructive) {
                    store.stopDownload(videoID: episode.videoID)
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Stop download")
            } else if downloadStatus.phase == .queued {
                CircularProgressView(symbolName: "pause.fill")
                    .frame(width: 22, height: 22)
            } else {
                CircularProgressView(progress: downloadStatus.progress)
                    .frame(width: 22, height: 22)
            }
        } else if episode.isDownloaded {
            Image(systemName: episode.isPlayed ? "checkmark.circle" : "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(episode.isPlayed ? Color.secondary : .green)
        } else {
            Button {
                onStartDownload()
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
    var progress: Double? = nil
    var symbolName: String? = nil

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 2.5)
                .foregroundStyle(.quaternary)

            if let progress {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(.tint)
                    .rotationEffect(.degrees(-90))

                Text("\(Int(progress * 100))")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
