import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedChannels: Set<UUID> = []
    @State private var showAddSheet = false

    var body: some View {
        if !store.ytDlpReady || !store.ffmpegReady {
            SetupView()
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                serverToggle
                fetchButton
                addButton
            }
        }
        .overlay(alignment: .bottom) {
            statusBar
        }
        .sheet(isPresented: $showAddSheet) {
            AddChannelSheet()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedChannels) {
            if store.channels.isEmpty {
                ContentUnavailableView {
                    Label("No Channels", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("Press + to add a YouTube channel.")
                }
                .listRowSeparator(.hidden)
            } else {
                ForEach(store.channels) { channel in
                    ChannelRow(channel: channel, episodeCount: store.episodes(for: channel.id).count)
                        .tag(channel.id)
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                withAnimation {
                                    store.removeChannels([channel.id])
                                    selectedChannels.remove(channel.id)
                                }
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Channels")
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if selectedChannels.isEmpty && !store.channels.isEmpty {
                ContentUnavailableView {
                    Label("Select a Channel", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a channel from the sidebar to view episodes.")
                }
            } else if store.channels.isEmpty {
                ContentUnavailableView {
                    Label("Get Started", systemImage: "plus.circle")
                } description: {
                    Text("Add a YouTube channel to begin downloading episodes.")
                }
            } else {
                EpisodeListView(channelIDs: selectedChannels)
            }
        }
    }

    // MARK: - Toolbar items

    private var addButton: some View {
        Button {
            showAddSheet = true
        } label: {
            Label("Add Channel", systemImage: "plus")
        }
        .help("Add a YouTube channel")
    }

    private var fetchButton: some View {
        Button {
            Task {
                await store.fetchNewEpisodes(for: selectedChannels)
            }
        } label: {
            if store.isFetching {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Fetch", systemImage: "arrow.clockwise")
            }
        }
        .disabled(store.channels.isEmpty || store.isFetching)
        .help(selectedChannels.isEmpty ? "Fetch all channels" : "Fetch selected channels")
    }

    private var serverToggle: some View {
        Button {
            if store.isServerRunning {
                store.stopServer()
            } else {
                store.startServer()
            }
        } label: {
            Label(
                store.isServerRunning ? "Stop Server" : "Start Server",
                systemImage: store.isServerRunning ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right.circle"
            )
        }
        .help(store.isServerRunning
              ? "Stop podcast server"
              : "Start podcast server on port \(store.serverPort)")
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            if store.isFetching {
                ProgressView()
                    .controlSize(.small)
            }
            Text(store.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if store.isServerRunning {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.green)
                Text("http://localhost:\(store.serverPort)/feed.xml")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Channel Row

struct ChannelRow: View {
    let channel: Channel
    let episodeCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(channel.name)
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(1)
            Text("\(episodeCount) episode\(episodeCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Setup View

struct SetupView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Welcome to Recast")
                .font(.title)
                .fontWeight(.semibold)

            Text("Recast needs a couple of tools to download audio from YouTube.\nThey'll be installed automatically — no terminal required.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 12) {
                DependencyRow(name: "yt-dlp", detail: "YouTube downloader", ready: store.ytDlpReady)
                DependencyRow(name: "ffmpeg", detail: "Audio converter", ready: store.ffmpegReady)
            }
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))

            if store.isInstallingDeps {
                ProgressView(store.statusMessage)
            } else {
                Button("Install & Continue") {
                    Task { await store.installDependencies() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DependencyRow: View {
    let name: String
    let detail: String
    let ready: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ready ? .green : .secondary)
            VStack(alignment: .leading) {
                Text(name).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
