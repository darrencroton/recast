import AppKit
import SwiftUI

struct SettingsView: View {
    private let serverLabelWidth: CGFloat = 132
    private let serverContentWidth: CGFloat = 250
    private let serverHostFieldWidth: CGFloat = 190
    private let serverPortFieldWidth: CGFloat = 96

    @Environment(AppStore.self) private var store
    @State private var isResetConfirmationPresented = false
    @State private var isResetting = false
    @State private var serverHostDraft = ""
    @State private var serverPortDraft = ""
    @State private var isEditingServerHost = false
    @State private var isEditingServerPort = false

    var body: some View {
        @Bindable var bindableStore = store

        Form {
            Section("Output") {
                LabeledContent("Episodes folder") {
                    HStack {
                        Text(store.episodesDirectory.path)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(store.episodesDirectory.path)

                        Button("Choose…") {
                            chooseOutputDir()
                        }
                    }
                }
            }

            Section("Podcast Server") {
                serverSettingsRow("Start server when app launches") {
                    Toggle("", isOn: $bindableStore.autoStartServer)
                        .labelsHidden()
                        .onChange(of: store.autoStartServer) {
                            store.save()
                        }
                }

                serverSettingsRow("DNS") {
                    serverOverrideField(
                        helperText: "Leave blank to use the current local address"
                    ) {
                        draftTextField(
                            text: $serverHostDraft,
                            placeholder: store.localIPAddress ?? "localhost",
                            width: serverHostFieldWidth,
                            alignment: .right
                        ) { isEditing in
                            isEditingServerHost = isEditing
                            if !isEditing {
                                commitServerHostDraft()
                            }
                        } onCommit: {
                            commitServerHostDraft()
                        }
                    }
                }

                serverSettingsRow("Port") {
                    serverOverrideField(
                        helperText: "Leave blank to use the default port"
                    ) {
                        draftTextField(
                            text: $serverPortDraft,
                            placeholder: String(store.defaultServerPort),
                            width: serverPortFieldWidth,
                            alignment: .right
                        ) { isEditing in
                            isEditingServerPort = isEditing
                            if !isEditing {
                                commitServerPortDraft()
                            }
                        } onCommit: {
                            commitServerPortDraft()
                        }
                    }
                }

                serverSettingsRow("Feed URL", usesFlexibleContentWidth: true) {
                    Text(store.feedURL)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.9)
                        .textSelection(.enabled)
                }
            }

            Section("Automation") {
                Picker("Check for new episodes", selection: $bindableStore.autoFetchInterval) {
                    Text("Manually").tag(0)
                    Text("Every 6 hours").tag(6)
                    Text("Every 12 hours").tag(12)
                    Text("Every 24 hours").tag(24)
                }
                .onChange(of: store.autoFetchInterval) {
                    store.save()
                    store.restartAutoFetchTimer()
                }
            }

            Section("About") {
                LabeledContent("yt-dlp") {
                    Label(store.ytDlpReady ? "Installed" : "Not found",
                          systemImage: store.ytDlpReady ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(store.ytDlpReady ? .green : .red)
                }
                LabeledContent("ffmpeg") {
                    Label(store.ffmpegReady ? "Installed" : "Not found",
                          systemImage: store.ffmpegReady ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(store.ffmpegReady ? .green : .red)
                }
            }

            Section("Reset") {
                Text("Remove all channels, episode history, Recast-downloaded audio, generated feed files, installed tools, and settings. Diagnostic logs are kept.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Reset App to Defaults…", role: .destructive) {
                    isResetConfirmationPresented = true
                }
                .disabled(isResetting)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 420)
        .background(SettingsWindowClickMonitor())
        .onAppear {
            syncServerDraftsFromStore()
        }
        .onChange(of: store.serverHost) {
            if !isEditingServerHost {
                serverHostDraft = store.serverHost
            }
        }
        .onChange(of: store.serverPort) {
            if !isEditingServerPort {
                serverPortDraft = serverPortDisplayValue
            }
        }
        .alert("Reset Recast to Defaults?", isPresented: $isResetConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task {
                    isResetting = true
                    await store.resetToDefaults()
                    isResetting = false
                }
            }
        } message: {
            Text("This will remove saved channels, episode state, Recast-managed downloads, generated feed files, installed tools, and custom settings. Diagnostic logs are kept.")
        }
    }

    private func chooseOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose the folder where Recast should store downloaded podcast episodes."
        if panel.runModal() == .OK, let url = panel.url {
            store.episodesDirectory = url
            store.save()
        }
    }

    private func syncServerDraftsFromStore() {
        serverHostDraft = store.serverHost
        serverPortDraft = serverPortDisplayValue
    }

    private func draftTextField(
        text: Binding<String>,
        placeholder: String,
        width: CGFloat,
        alignment: NSTextAlignment,
        onEditingChanged: @escaping (Bool) -> Void,
        onCommit: @escaping () -> Void
    ) -> some View {
        CommitOnEndEditingTextField(
            text: text,
            placeholder: placeholder,
            alignment: alignment,
            onEditingChanged: onEditingChanged,
            onCommit: onCommit
        )
        .frame(width: width)
    }

    private func serverOverrideField<Content: View>(
        helperText: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            content()
            Text(helperText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func serverSettingsRow<Content: View>(
        _ title: String,
        usesFlexibleContentWidth: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .frame(width: serverLabelWidth, alignment: .leading)
            Spacer(minLength: 0)
            if usesFlexibleContentWidth {
                content()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                content()
                    .frame(width: serverContentWidth, alignment: .trailing)
            }
        }
    }

    private func commitServerHostDraft() {
        store.commitServerHost(serverHostDraft)
        serverHostDraft = store.serverHost
    }

    private func commitServerPortDraft() {
        store.commitServerPort(serverPortDraft)
        serverPortDraft = serverPortDisplayValue
    }

    private var serverPortDisplayValue: String {
        store.serverPort == store.defaultServerPort ? "" : String(store.serverPort)
    }
}

private struct CommitOnEndEditingTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var alignment: NSTextAlignment
    var onEditingChanged: (Bool) -> Void
    var onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.stringValue = text
        field.placeholderString = placeholder
        field.alignment = alignment
        field.bezelStyle = .roundedBezel
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        nsView.placeholderString = placeholder
        nsView.alignment = alignment

        if !context.coordinator.isEditing, nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommitOnEndEditingTextField
        var isEditing = false

        init(parent: CommitOnEndEditingTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
            parent.onEditingChanged(true)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let newValue = field.stringValue
            if parent.text != newValue {
                parent.text = newValue
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let newValue = field.stringValue
            if parent.text != newValue {
                parent.text = newValue
            }

            if isEditing {
                isEditing = false
                parent.onEditingChanged(false)
            }

            parent.onCommit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard
                commandSelector == #selector(NSResponder.insertNewline(_:)) ||
                commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
            else {
                return false
            }

            guard let field = control as? NSTextField else {
                parent.onCommit()
                return true
            }

            let newValue = field.stringValue
            if parent.text != newValue {
                parent.text = newValue
            }

            if !(field.window?.makeFirstResponder(nil) ?? false) {
                if isEditing {
                    isEditing = false
                    parent.onEditingChanged(false)
                }
                parent.onCommit()
            }

            return true
        }
    }
}

private struct SettingsWindowClickMonitor: NSViewRepresentable {
    func makeNSView(context: Context) -> ClickMonitorView {
        ClickMonitorView()
    }

    func updateNSView(_ nsView: ClickMonitorView, context: Context) {}
}

private final class ClickMonitorView: NSView {
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitorIfNeeded()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow !== window {
            removeMonitor()
        }
    }

    deinit {
        removeMonitor()
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
        guard
            let editor = window.firstResponder as? NSTextView,
            editor.isFieldEditor,
            let textField = editor.delegate as? NSView
        else {
            return event
        }

        let pointInField = textField.convert(event.locationInWindow, from: nil)
        guard !textField.bounds.contains(pointInField) else { return event }

        window.makeFirstResponder(nil)
        return event
    }
}
