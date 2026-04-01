import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Sidebar selection model

enum SidebarItem: Hashable {
    case allEpisodes
    case channel(UUID)
}

private enum FocusedPane: Hashable {
    case sidebar
    case episodes
}

private enum SelectionActionContext {
    case none
    case channels(Set<UUID>)
    case episodes(Set<UUID>)
}

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: Set<SidebarItem> = []
    @State private var selectedEpisodeIDs: Set<UUID> = []
    @State private var showAddSheet = false
    @State private var searchQuery = ""
    @State private var episodeFilter: EpisodeFilter = .all
    @State private var focusedPane: FocusedPane?

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

    private var activeChannelScope: Set<UUID> {
        showingAllEpisodes ? Set() : selectedChannelIDs
    }

    private var visibleEpisodeIDs: Set<UUID> {
        Set(store.filteredEpisodes(for: activeChannelScope, query: searchQuery, filter: episodeFilter).map(\.id))
    }

    private var actionableEpisodeIDs: Set<UUID> {
        selectedEpisodeIDs.intersection(visibleEpisodeIDs)
    }

    private var selectedVisibleEpisodes: [Episode] {
        store
            .filteredEpisodes(for: activeChannelScope, query: searchQuery, filter: episodeFilter)
            .filter { actionableEpisodeIDs.contains($0.id) }
    }

    private var sidebarSummaryTitle: String {
        episodeFilter.sidebarTitle
    }

    private var sidebarSummaryCount: Int {
        store.episodeCount(for: activeChannelScope, query: searchQuery, filter: episodeFilter)
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

    private var selectionContext: SelectionActionContext {
        switch focusedPane {
        case .sidebar:
            return selectedChannelIDs.isEmpty ? .none : .channels(selectedChannelIDs)
        case .episodes:
            if !actionableEpisodeIDs.isEmpty {
                return .episodes(actionableEpisodeIDs)
            }
            return selectedChannelIDs.isEmpty ? .none : .channels(selectedChannelIDs)
        case nil:
            if !actionableEpisodeIDs.isEmpty {
                return .episodes(actionableEpisodeIDs)
            }
            if !selectedChannelIDs.isEmpty {
                return .channels(selectedChannelIDs)
            }
            return .none
        }
    }

    private var canRefreshSelectedChannels: Bool {
        guard case .channels(let ids) = selectionContext else { return false }
        return !ids.isEmpty && !store.isFetching
    }

    private var isRefreshingSelectedChannels: Bool {
        guard case .channels(let ids) = selectionContext else { return false }
        return !ids.isEmpty && store.isFetching
    }

    private var canDeleteSelectedItems: Bool {
        switch selectionContext {
        case .channels(let ids), .episodes(let ids):
            return !ids.isEmpty
        case .none:
            return false
        }
    }

    private var canDownloadSelectedEpisodes: Bool {
        guard case .episodes = selectionContext else { return false }
        return selectedVisibleEpisodes.contains {
            !$0.isDownloaded && !store.activeDownloads.contains($0.videoID)
        }
    }

    var body: some View {
        if !store.ytDlpReady || !store.ffmpegReady {
            SetupView()
        } else {
            mainContent
                .onAppear {
                    store.onLaunch()
                    ensureDefaultSidebarSelection()
                }
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
            ToolbarItem(placement: .automatic) {
                if !store.channels.isEmpty {
                    Picker("Filter", selection: $episodeFilter) {
                        ForEach(EpisodeFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Filter episodes")
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                globalActions
                selectionActions
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            statusBar
        }
        .sheet(isPresented: $showAddSheet) {
            AddChannelSheet()
        }
        .onChange(of: store.channels.count) { _, newCount in
            if newCount == 0 {
                selection.removeAll()
                selectedEpisodeIDs.removeAll()
                focusedPane = nil
            } else {
                ensureDefaultSidebarSelection()
            }
        }
        .onChange(of: visibleEpisodeIDs) { _, newValue in
            selectedEpisodeIDs.formIntersection(newValue)
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
                Label(sidebarSummaryTitle, systemImage: "rectangle.stack")
                    .tag(SidebarItem.allEpisodes)
                    .badge(sidebarSummaryCount)

                Section("Channels") {
                    ForEach(store.channels) { channel in
                        ChannelRow(channel: channel, episodeCount: store.episodes(for: channel.id).count)
                            .tag(SidebarItem.channel(channel.id))
                            .contextMenu {
                                channelContextMenu(for: channel.id)
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .simultaneousGesture(TapGesture().onEnded {
            focusedPane = .sidebar
        })
        .navigationTitle("Channels")
        .onChange(of: selection) { old, new in
            enforceExclusiveSelection(old: old, new: new)
            if selection != old {
                selectedEpisodeIDs.removeAll()
                focusedPane = .sidebar
            }
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
                    searchQuery: searchQuery,
                    filterMode: $episodeFilter,
                    selectedEpisodeIDs: $selectedEpisodeIDs,
                    onActivateSelection: {
                        focusedPane = .episodes
                    }
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

    private var globalActions: some View {
        ControlGroup {
            serverToggle
            qrCodeButton
            addButton
        }
    }

    private var selectionActions: some View {
        ControlGroup {
            refreshSelectionButton
            downloadSelectionButton
            deleteSelectionButton
        }
    }

    private var addButton: some View {
        Button {
            showAddSheet = true
        } label: {
            Label("Add Channel", systemImage: "plus")
        }
        .help("Add a YouTube channel")
    }

    private var refreshSelectionButton: some View {
        Button {
            refreshChannelsFromToolbar()
        } label: {
            if isRefreshingSelectedChannels {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .disabled(!canRefreshSelectedChannels)
        .help("Refresh the selected channels")
    }

    private var downloadSelectionButton: some View {
        Button {
            downloadSelectedEpisodes()
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
        }
        .disabled(!canDownloadSelectedEpisodes)
        .help("Download the selected episodes")
    }

    private var deleteSelectionButton: some View {
        Button(role: .destructive) {
            deleteSelection()
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(!canDeleteSelectedItems)
        .help(deleteButtonHelpText)
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

    // MARK: - Selection actions

    private var deleteButtonHelpText: String {
        switch selectionContext {
        case .channels:
            return "Delete the selected channels"
        case .episodes:
            return "Delete the selected episodes"
        case .none:
            return "Delete the selected item"
        }
    }

    private func ensureDefaultSidebarSelection() {
        guard !store.channels.isEmpty, selection.isEmpty else { return }
        selection = [.allEpisodes]
    }

    private func refreshChannelsFromToolbar() {
        guard case .channels(let ids) = selectionContext else { return }
        refreshChannels(ids)
    }

    private func downloadSelectedEpisodes() {
        guard case .episodes(let ids) = selectionContext else { return }
        Task {
            await store.downloadEpisodes(ids)
        }
    }

    private func deleteSelection() {
        switch selectionContext {
        case .channels(let ids):
            deleteChannels(ids)
        case .episodes(let ids):
            deleteEpisodes(ids)
        case .none:
            break
        }
    }

    private func refreshChannels(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        Task {
            await store.fetchNewEpisodes(for: ids)
        }
    }

    private func deleteChannels(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        withAnimation {
            store.removeChannels(ids)
            selection.subtract(ids.map { SidebarItem.channel($0) })
            if selection.isEmpty, !store.channels.isEmpty {
                selection = [.allEpisodes]
            }
        }
        selectedEpisodeIDs.removeAll()
        focusedPane = .sidebar
    }

    private func deleteEpisodes(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        store.deleteEpisodes(ids)
        selectedEpisodeIDs.subtract(ids)
    }

    private func channelContextTarget(for channelID: UUID) -> Set<UUID> {
        selectedChannelIDs.contains(channelID) ? selectedChannelIDs : [channelID]
    }

    @ViewBuilder
    private func channelContextMenu(for channelID: UUID) -> some View {
        let targetIDs = channelContextTarget(for: channelID)

        Button {
            refreshChannels(targetIDs)
        } label: {
            Label(
                targetIDs.count == 1 ? "Refresh Channel" : "Refresh Selected Channels",
                systemImage: "arrow.clockwise"
            )
        }
        .disabled(store.isFetching)

        Button(role: .destructive) {
            deleteChannels(targetIDs)
        } label: {
            Label(
                targetIDs.count == 1 ? "Delete Channel" : "Delete Selected Channels",
                systemImage: "trash"
            )
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
