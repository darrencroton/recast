import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Sidebar selection model

enum SidebarItem: Hashable {
    case allEpisodes
    case channel(UUID)
}

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: Set<SidebarItem> = []
    @State private var showAddSheet = false
    @State private var searchQuery = ""

    private var selectedChannelIDs: Set<UUID> {
        var ids = Set<UUID>()
        for item in selection {
            if case .channel(let id) = item { ids.insert(id) }
        }
        return ids
    }

    private var showingAllEpisodes: Bool {
        selection.contains(.allEpisodes)
    }

    /// Keep sidebar selection mutually exclusive: All Episodes vs individual channels.
    private func enforceExclusiveSelection(old: Set<SidebarItem>, new: Set<SidebarItem>) {
        let addedAll = new.contains(.allEpisodes) && !old.contains(.allEpisodes)
        let addedChannel = new.contains(where: { if case .channel = $0 { return true }; return false })
            && !old.contains(where: { if case .channel = $0 { return true }; return false })

        if addedAll {
            // User just selected All Episodes — deselect any channels
            selection = [.allEpisodes]
        } else if addedChannel && old.contains(.allEpisodes) {
            // User selected a channel while All Episodes was selected — deselect All Episodes
            selection = new.filter { if case .channel = $0 { return true }; return false }
        }
    }

    var body: some View {
        if !store.ytDlpReady || !store.ffmpegReady {
            SetupView()
        } else {
            mainContent
                .onAppear { store.onLaunch() }
        }
    }

    private var mainContent: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detail
        }
        .searchable(text: $searchQuery, prompt: "Search episodes")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                serverToggle
                qrCodeButton
                fetchButton
                downloadAllButton
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
        List(selection: $selection) {
            if store.channels.isEmpty {
                ContentUnavailableView {
                    Label("No Channels", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("Press + to add a YouTube channel.")
                }
                .listRowSeparator(.hidden)
            } else {
                Label("All Episodes", systemImage: "rectangle.stack")
                    .tag(SidebarItem.allEpisodes)
                    .badge(store.episodes.count)

                Section("Channels") {
                    ForEach(store.channels) { channel in
                        ChannelRow(channel: channel, episodeCount: store.episodes(for: channel.id).count)
                            .tag(SidebarItem.channel(channel.id))
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    withAnimation {
                                        store.removeChannels([channel.id])
                                        selection.remove(.channel(channel.id))
                                    }
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Channels")
        .onChange(of: selection) { old, new in
            enforceExclusiveSelection(old: old, new: new)
        }
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if store.channels.isEmpty {
                ContentUnavailableView {
                    Label("Get Started", systemImage: "plus.circle")
                } description: {
                    Text("Add a YouTube channel to begin downloading episodes.")
                }
            } else if showingAllEpisodes || !selectedChannelIDs.isEmpty {
                EpisodeListView(
                    channelIDs: showingAllEpisodes ? Set() : selectedChannelIDs,
                    searchQuery: searchQuery
                )
            } else {
                ContentUnavailableView {
                    Label("Select a Channel", systemImage: "sidebar.left")
                } description: {
                    Text("Choose a channel from the sidebar, or select All Episodes.")
                }
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
                await store.fetchNewEpisodes(for: selectedChannelIDs)
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
        .help(selectedChannelIDs.isEmpty ? "Check all channels for new episodes" : "Check selected channels for new episodes")
    }

    private var downloadAllButton: some View {
        Button {
            Task {
                await store.downloadAllNew(for: showingAllEpisodes ? Set() : selectedChannelIDs)
            }
        } label: {
            Label("Download All", systemImage: "arrow.down.to.line")
        }
        .disabled(store.channels.isEmpty || !store.activeDownloads.isEmpty)
        .help("Download all undownloaded episodes")
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
                systemImage: store.isServerRunning
                    ? "antenna.radiowaves.left.and.right.circle.fill"
                    : "antenna.radiowaves.left.and.right.circle"
            )
        }
        .help(store.isServerRunning
              ? "Stop podcast server"
              : "Start podcast server on port \(store.serverPort)")
    }

    @State private var showQRPopover = false

    private var qrCodeButton: some View {
        Button {
            showQRPopover.toggle()
        } label: {
            Label("QR Code", systemImage: "qrcode")
        }
        .help("Show feed QR code for your phone")
        .popover(isPresented: $showQRPopover) {
            QRCodePopover(feedURL: store.feedURL)
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            if store.isFetching || !store.activeDownloads.isEmpty {
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
                Text(store.feedURL)
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
        HStack(spacing: 10) {
            ChannelMonogram(name: channel.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(episodeCount) episode\(episodeCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Channel Monogram

struct ChannelMonogram: View {
    let name: String

    private var initial: String {
        String(name.prefix(1)).uppercased()
    }

    private var color: Color {
        let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink]
        // Deterministic hash so the colour is stable across launches
        let hash = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return colors[abs(hash) % colors.count]
    }

    var body: some View {
        Text(initial)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color.gradient, in: Circle())
    }
}

// MARK: - QR Code Popover

struct QRCodePopover: View {
    let feedURL: String

    var body: some View {
        VStack(spacing: 12) {
            Text("Scan to Subscribe")
                .font(.headline)

            if let image = Self.generateQRCode(from: feedURL) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
            }

            Text(feedURL)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text("Add this URL in your podcast app.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
    }

    static func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
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
