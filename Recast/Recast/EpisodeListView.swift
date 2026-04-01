import SwiftUI

struct EpisodeListView: View {
    @Environment(AppStore.self) private var store
    let channelIDs: Set<UUID>
    let searchQuery: String

    @State private var filterMode: EpisodeFilter = .all
    @State private var isSelectionMode = false
    @State private var selectedEpisodeIDs: Set<UUID> = []

    enum EpisodeFilter: String, CaseIterable {
        case all = "All"
        case downloaded = "Downloaded"
        case notDownloaded = "New"
        case unplayed = "Unplayed"
    }

    private var episodes: [Episode] {
        var result = store.filteredEpisodes(for: channelIDs, query: searchQuery)
        switch filterMode {
        case .all: break
        case .downloaded: result = result.filter(\.isDownloaded)
        case .notDownloaded: result = result.filter { !$0.isDownloaded }
        case .unplayed: result = result.filter { !$0.isPlayed && $0.isDownloaded }
        }
        return result
    }

    private var showChannelName: Bool {
        channelIDs.isEmpty || channelIDs.count > 1
    }

    private var visibleEpisodeIDs: Set<UUID> {
        Set(episodes.map(\.id))
    }

    private var selectedEpisodes: [Episode] {
        episodes.filter { selectedEpisodeIDs.contains($0.id) }
    }

    var body: some View {
        Group {
            if store.filteredEpisodes(for: channelIDs, query: "").isEmpty {
                ContentUnavailableView {
                    Label("No Episodes", systemImage: "waveform")
                } description: {
                    Text("Press Fetch to check for new episodes.")
                }
            } else if episodes.isEmpty {
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    Text("No episodes match the current filter.")
                }
            } else {
                List(episodes) { episode in
                    EpisodeRow(
                        episode: episode,
                        isDownloading: store.activeDownloads.contains(episode.videoID),
                        progress: store.downloadProgress[episode.videoID],
                        showChannelName: showChannelName,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedEpisodeIDs.contains(episode.id)
                    )
                    .contentShape(Rectangle())
                    .tag(episode.id)
                    .onTapGesture {
                        guard isSelectionMode else { return }
                        toggleSelection(for: episode.id)
                    }
                    .contextMenu { episodeContextMenu(for: episode) }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(navigationTitle)
        .onChange(of: visibleEpisodeIDs) { _, newValue in
            selectedEpisodeIDs.formIntersection(newValue)
            if newValue.isEmpty {
                isSelectionMode = false
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Filter", selection: $filterMode) {
                    ForEach(EpisodeFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .help("Filter episodes")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if isSelectionMode {
                    Button {
                        Task {
                            await store.downloadEpisodes(selectedEpisodeIDs)
                            selectedEpisodeIDs = Set(
                                selectedEpisodes
                                    .filter { !$0.isDownloaded }
                                    .map(\.id)
                            )
                            if selectedEpisodeIDs.isEmpty {
                                isSelectionMode = false
                            }
                        }
                    } label: {
                        Label("Download Selected", systemImage: "arrow.down.circle")
                    }
                    .disabled(selectedEpisodes.allSatisfy { $0.isDownloaded || store.activeDownloads.contains($0.videoID) })

                    Button(role: .destructive) {
                        store.deleteEpisodes(selectedEpisodeIDs)
                        selectedEpisodeIDs.removeAll()
                        isSelectionMode = false
                    } label: {
                        Label("Delete Selected", systemImage: "trash")
                    }
                    .disabled(selectedEpisodeIDs.isEmpty)
                }

                Button {
                    if isSelectionMode {
                        selectedEpisodeIDs.removeAll()
                    }
                    isSelectionMode.toggle()
                } label: {
                    Label(isSelectionMode ? "Done" : "Select", systemImage: isSelectionMode ? "checkmark.circle" : "checklist")
                }
                .disabled(episodes.isEmpty)
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func episodeContextMenu(for episode: Episode) -> some View {
        if episode.isDownloaded {
            Button {
                store.togglePlayed(episode.id)
            } label: {
                Label(
                    episode.isPlayed ? "Mark as Unplayed" : "Mark as Played",
                    systemImage: episode.isPlayed ? "circle" : "checkmark.circle"
                )
            }

            Button {
                store.revealInFinder(episode)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
        } else if !store.activeDownloads.contains(episode.videoID) {
            Button {
                Task { await store.downloadEpisode(episode) }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }

        Divider()

        Button(role: .destructive) {
            store.deleteEpisodes([episode.id])
        } label: {
            Label("Delete", systemImage: "trash")
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

    private func toggleSelection(for episodeID: UUID) {
        if selectedEpisodeIDs.contains(episodeID) {
            selectedEpisodeIDs.remove(episodeID)
        } else {
            selectedEpisodeIDs.insert(episodeID)
        }
    }
}

// MARK: - Episode Row

struct EpisodeRow: View {
    let episode: Episode
    let isDownloading: Bool
    let progress: Double?
    let showChannelName: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24)
            }

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
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var actionAccessory: some View {
        if isDownloading {
            if let progress {
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
