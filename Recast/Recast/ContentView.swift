import AppKit
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

enum ChannelRefreshState {
    case current
    case queued
}

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: Set<SidebarItem> = []
    @State private var selectedEpisodeIDs: Set<UUID> = []
    @State private var showAddSheet = false
    @State private var searchQuery = ""
    @State private var episodeFilter: EpisodeFilter = .all
    @State private var focusedPane: FocusedPane?
    @State private var isHoveringRefreshControl = false
    @State private var isHoveringDownloadControl = false
    @State private var showDeleteConfirmation = false
    @State private var pendingDeletion: SelectionActionContext = .none

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
        if store.isFetching { return true }
        guard case .channels(let ids) = selectionContext else { return false }
        return !ids.isEmpty
    }

    private var isRefreshingSelectedChannels: Bool {
        store.isFetching
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
        if store.hasPendingDownloads { return true }
        guard case .episodes = selectionContext else { return false }
        return selectedVisibleEpisodes.contains {
            !$0.isDownloaded && store.downloadStatus(for: $0) == nil
        }
    }

    var body: some View {
        if !store.ytDlpReady || !store.ffmpegReady {
            SetupView()
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
            } detail: {
                detail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusBar
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
        .sheet(isPresented: $showAddSheet) {
            AddChannelSheet()
        }
        .alert(deleteConfirmationTitle, isPresented: $showDeleteConfirmation) {
            Button(deleteConfirmationButtonLabel, role: .destructive) {
                Task {
                    await deleteSelection(pendingDeletion)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
        .onChange(of: store.channels.count) { _, newCount in
            if newCount == 0 {
                selection.removeAll()
                selectedEpisodeIDs.removeAll()
                focusedPane = nil
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
                    Label("No Sources", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("Press + to add a YouTube channel, playlist, or episode.")
                }
                .listRowSeparator(.hidden)
            } else {
                Label(sidebarSummaryTitle, systemImage: "rectangle.stack")
                    .tag(SidebarItem.allEpisodes)
                    .badge(sidebarSummaryCount)

                Section("Sources") {
                    ForEach(store.channels) { channel in
                        ChannelRow(
                            channel: channel,
                            episodeCount: store.episodes(for: channel.id).count,
                            refreshState: refreshState(for: channel.id)
                        )
                            .tag(SidebarItem.channel(channel.id))
                            .contextMenu {
                                channelContextMenu(for: channel.id)
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .background {
            SidebarEmptySpaceDeselectionBridge(selection: $selection)
        }
        .simultaneousGesture(TapGesture().onEnded {
            focusedPane = .sidebar
        })
        .navigationTitle("Sources")
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
        VStack(spacing: 0) {
            if store.isFetching || store.hasPendingDownloads {
                operationSummaryBar
            }

            Group {
                if store.channels.isEmpty {
                    ContentUnavailableView {
                        Label("Get Started", systemImage: "plus.circle")
                    } description: {
                        Text("Add a YouTube channel, playlist, or episode to begin downloading audio.")
                    }
                } else {
                    EpisodeListView(
                        channelIDs: activeChannelScope,
                        searchQuery: searchQuery,
                        filterMode: $episodeFilter,
                        selectedEpisodeIDs: $selectedEpisodeIDs,
                        onRequestDeleteEpisodes: { ids in
                            requestDeletion(.episodes(ids))
                        },
                        onActivateSelection: {
                            focusedPane = .episodes
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            Label("Add Source", systemImage: "plus")
        }
        .help("Add a YouTube channel, playlist, or episode")
    }

    private var refreshSelectionButton: some View {
        Button {
            if store.isFetching {
                store.stopFetch()
            } else {
                refreshChannelsFromToolbar()
            }
        } label: {
            if isRefreshingSelectedChannels {
                if isHoveringRefreshControl {
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(.red)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            } else {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .disabled(!canRefreshSelectedChannels)
        .onHover { isHovering in
            isHoveringRefreshControl = store.isFetching && isHovering
        }
        .help(store.isFetching ? "Stop current refresh" : "Refresh the selected sources")
    }

    private var downloadSelectionButton: some View {
        Button {
            if store.hasPendingDownloads {
                store.stopAllDownloads()
            } else {
                downloadSelectedEpisodes()
            }
        } label: {
            if store.hasPendingDownloads {
                if isHoveringDownloadControl {
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(.red)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            } else {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
        .disabled(!canDownloadSelectedEpisodes)
        .onHover { isHovering in
            isHoveringDownloadControl = store.hasPendingDownloads && isHovering
        }
        .help(store.hasPendingDownloads ? "Stop all downloads" : "Download the selected episodes")
    }

    private var deleteSelectionButton: some View {
        Button(role: .destructive) {
            requestDeletion(selectionContext)
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
            return "Delete the selected sources and downloads"
        case .episodes:
            let hasDownloads = selectedVisibleEpisodes.contains { $0.isDownloaded }
            if hasDownloads {
                return "Delete episode files and remove from list"
            } else {
                return "Remove the selected episodes from your list"
            }
        case .none:
            return "Delete the selected item"
        }
    }

    private var deleteConfirmationTitle: String {
        switch pendingDeletion {
        case .channels(let ids):
            return ids.count == 1 ? "Delete Source?" : "Delete \(ids.count) Sources?"
        case .episodes(let ids):
            return ids.count == 1 ? "Delete Episode?" : "Delete \(ids.count) Episodes?"
        case .none:
            return "Delete?"
        }
    }

    private var deleteConfirmationMessage: String {
        switch pendingDeletion {
        case .channels(let ids):
            return ids.count == 1
                ? "This deletes the source, its episodes, and downloaded files."
                : "This deletes the sources, their episodes, and downloaded files."
        case .episodes(let ids):
            let hasDownloads = store.episodes.filter { ids.contains($0.id) }.contains { $0.isDownloaded }
            if hasDownloads {
                return "This will permanently delete the downloaded files and remove the episodes from your list. To keep episodes in your list, use Remove Download from the right-click menu instead."
            } else {
                return "The episodes will be removed from your list."
            }
        case .none:
            return ""
        }
    }

    private var deleteConfirmationButtonLabel: String {
        "Delete"
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

    private func requestDeletion(_ context: SelectionActionContext) {
        guard case .none = context else {
            pendingDeletion = context
            showDeleteConfirmation = true
            return
        }
    }

    private func deleteSelection(_ context: SelectionActionContext? = nil) async {
        switch context ?? selectionContext {
        case .channels(let ids):
            await deleteChannels(ids)
        case .episodes(let ids):
            await deleteEpisodes(ids)
        case .none:
            break
        }
    }

    private func refreshChannels(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        selection = Set(ids.map { SidebarItem.channel($0) })
        selectedEpisodeIDs.removeAll()
        focusedPane = .sidebar
        Task {
            await store.fetchNewEpisodes(for: ids)
        }
    }

    private func refreshState(for channelID: UUID) -> ChannelRefreshState? {
        guard store.activeRefreshChannelIDs.contains(channelID) else { return nil }
        return store.currentRefreshChannelID == channelID ? .current : .queued
    }

    private func showRefreshingChannels() {
        guard !store.activeRefreshChannelIDs.isEmpty else { return }
        selection = Set(store.activeRefreshChannelIDs.map { SidebarItem.channel($0) })
        selectedEpisodeIDs.removeAll()
        focusedPane = .sidebar
    }

    private func showActiveDownloads() {
        let activeEpisodeIDs = Set(store.activeDownloadEpisodes.map(\.id))
        guard !activeEpisodeIDs.isEmpty else { return }
        searchQuery = ""
        episodeFilter = .all
        selection = [.allEpisodes]
        selectedEpisodeIDs = activeEpisodeIDs
        focusedPane = .episodes
    }

    private func deleteChannels(_ ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        await store.deleteChannels(ids)
        withAnimation {
            selection.subtract(ids.map { SidebarItem.channel($0) })
        }
        selectedEpisodeIDs.removeAll()
        focusedPane = .sidebar
    }

    private func deleteEpisodes(_ ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        await store.deleteEpisodes(ids)
        selectedEpisodeIDs.subtract(ids)
    }

    private func channelContextTarget(for channelID: UUID) -> Set<UUID> {
        selectedChannelIDs.contains(channelID) ? selectedChannelIDs : [channelID]
    }

    @ViewBuilder
    private func channelContextMenu(for channelID: UUID) -> some View {
        let targetIDs = channelContextTarget(for: channelID)

        if store.isFetching {
            Button(role: .destructive) {
                store.stopFetch()
            } label: {
                Label("Stop Refresh", systemImage: "stop.circle")
            }
        } else {
            Button {
                refreshChannels(targetIDs)
            } label: {
                Label(
                    targetIDs.count == 1 ? "Refresh Source" : "Refresh Selected Sources",
                    systemImage: "arrow.clockwise"
                )
            }
        }

        Button(role: .destructive) {
            requestDeletion(.channels(targetIDs))
        } label: {
            Label(
                targetIDs.count == 1 ? "Delete Source" : "Delete Selected Sources",
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

    private var operationSummaryBar: some View {
        VStack(spacing: 0) {
            if store.isFetching {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Refreshing \(store.activeRefreshChannelIDs.count) source\(store.activeRefreshChannelIDs.count == 1 ? "" : "s")")
                            .font(.subheadline)
                        if let currentRefreshChannelName = store.currentRefreshChannelName {
                            Text("Currently checking \(currentRefreshChannelName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Show") {
                        showRefreshingChannels()
                    }
                    Button("Stop", role: .destructive) {
                        store.stopFetch()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            if store.hasPendingDownloads {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        if store.activeDownloadEpisodes.count == 1,
                           let episode = store.activeDownloadEpisodes.first,
                           let downloadStatus = store.downloadStatus(for: episode) {
                            Text(downloadStatus.phase.label)
                                .font(.subheadline)
                            Text(episode.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Downloading \(store.activeDownloadEpisodes.count) episode\(store.activeDownloadEpisodes.count == 1 ? "" : "s")")
                                .font(.subheadline)
                            Text("Progress stays visible even if you browse elsewhere.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Show") {
                        showActiveDownloads()
                    }
                    Button("Stop All", role: .destructive) {
                        store.stopAllDownloads()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct SidebarEmptySpaceDeselectionBridge: NSViewRepresentable {
    @Binding var selection: Set<SidebarItem>

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> SidebarSelectionMonitorView {
        let view = SidebarSelectionMonitorView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: SidebarSelectionMonitorView, context: Context) {
        context.coordinator.selection = $selection
        nsView.coordinator = context.coordinator
        nsView.configureIfNeeded()
    }

    final class Coordinator {
        var selection: Binding<Set<SidebarItem>>

        init(selection: Binding<Set<SidebarItem>>) {
            self.selection = selection
        }

        func clearSelection() {
            guard !selection.wrappedValue.isEmpty else { return }
            selection.wrappedValue.removeAll()
        }
    }
}

private final class SidebarSelectionMonitorView: NSView {
    weak var tableView: NSTableView?
    var coordinator: SidebarEmptySpaceDeselectionBridge.Coordinator?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitorIfNeeded()
        configureIfNeeded()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow !== window {
            removeMonitor()
            tableView = nil
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureIfNeeded()
    }

    deinit {
        removeMonitor()
    }

    func configureIfNeeded() {
        guard let tableView = resolveTableView() else { return }
        tableView.allowsEmptySelection = true
        self.tableView = tableView
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleMouseDown(event) ?? event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }
        guard let tableView = resolveTableView() else { return event }

        let pointInTable = tableView.convert(event.locationInWindow, from: nil)
        guard tableView.bounds.contains(pointInTable) else { return event }
        guard tableView.row(at: pointInTable) == -1 else { return event }

        tableView.deselectAll(nil)
        coordinator?.clearSelection()
        return event
    }

    private func resolveTableView() -> NSTableView? {
        let referencePoint = convert(
            NSPoint(x: bounds.midX, y: bounds.midY),
            to: nil
        )

        if let tableView, tableView.window === window {
            let pointInTable = tableView.convert(referencePoint, from: nil)
            if tableView.bounds.contains(pointInTable) {
                return tableView
            }
        }

        var ancestor: NSView? = self
        while let view = ancestor {
            if let tableView = view.firstDescendant(of: NSTableView.self, containing: referencePoint) {
                return tableView
            }
            ancestor = view.superview
        }

        return nil
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type, containing windowPoint: NSPoint) -> T? {
        if let selfAsType = self as? T {
            let pointInSelf = selfAsType.convert(windowPoint, from: nil)
            if selfAsType.bounds.contains(pointInSelf) {
                return selfAsType
            }
        }

        for subview in subviews {
            if let match = subview.firstDescendant(of: type, containing: windowPoint) {
                return match
            }
        }

        return nil
    }
}

// MARK: - Channel Row

struct ChannelRow: View {
    @Environment(AppStore.self) private var store
    let channel: Channel
    let episodeCount: Int
    let refreshState: ChannelRefreshState?

    var body: some View {
        HStack(spacing: 10) {
            ChannelArtworkView(
                artworkURL: store.channelArtworkURL(for: channel.id),
                channelName: channel.name
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(channel.sourceKind.sidebarSubtitlePrefix)\(episodeCount) episode\(episodeCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            refreshAccessory
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var refreshAccessory: some View {
        switch refreshState {
        case .current:
            ProgressView()
                .controlSize(.small)
        case .queued:
            Image(systemName: "arrow.clockwise.circle")
                .foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
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
