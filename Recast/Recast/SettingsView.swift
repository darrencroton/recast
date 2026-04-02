import SwiftUI

struct SettingsView: View {
    private let serverLabelWidth: CGFloat = 132
    private let serverContentWidth: CGFloat = 250
    private let serverHostFieldWidth: CGFloat = 190
    private let serverPortFieldWidth: CGFloat = 96

    private enum Field: Hashable {
        case serverHost
        case serverPort
    }

    @Environment(AppStore.self) private var store
    @State private var isResetConfirmationPresented = false
    @State private var isResetting = false
    @State private var serverHostDraft = ""
    @State private var serverPortDraft = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        @Bindable var bindableStore = store

        Form {
            Section("Output") {
                LabeledContent("Episodes folder") {
                    HStack {
                        Text(store.outputDirectory.path)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(store.outputDirectory.path)

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
                        TextField(
                            "",
                            text: $serverHostDraft,
                            prompt: Text(store.localIPAddress ?? "localhost")
                                .foregroundStyle(.secondary)
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: serverHostFieldWidth)
                        .focused($focusedField, equals: .serverHost)
                        .onSubmit {
                            commitServerHostDraft()
                        }
                        .onChange(of: focusedField) {
                            if focusedField != .serverHost {
                                commitServerHostDraft()
                            }
                        }
                    }
                }

                serverSettingsRow("Port") {
                    serverOverrideField(
                        helperText: "Leave blank to use the default port"
                    ) {
                        TextField(
                            "",
                            text: $serverPortDraft,
                            prompt: Text(String(store.defaultServerPort))
                                .foregroundStyle(.secondary)
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: serverPortFieldWidth)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .serverPort)
                        .onSubmit {
                            commitServerPortDraft()
                        }
                        .onChange(of: focusedField) {
                            if focusedField != .serverPort {
                                commitServerPortDraft()
                            }
                        }
                    }
                }

                serverSettingsRow("Feed URL") {
                    Text(store.feedURL)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
                Text("Remove all channels, episode history, Recast-downloaded audio, generated feeds, installed tools, and settings. Diagnostic logs are kept.")
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
        .onAppear {
            syncServerDraftsFromStore()
        }
        .onChange(of: store.serverHost) {
            if focusedField != .serverHost {
                serverHostDraft = store.serverHost
            }
        }
        .onChange(of: store.serverPort) {
            if focusedField != .serverPort {
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
            Text("This will remove saved channels, episode state, Recast-managed downloads, generated feeds, installed tools, and custom settings. Diagnostic logs are kept.")
        }
    }

    private func chooseOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose a folder for podcast episodes and the RSS feed."
        if panel.runModal() == .OK, let url = panel.url {
            store.outputDirectory = url
            store.save()
        }
    }

    private func syncServerDraftsFromStore() {
        serverHostDraft = store.serverHost
        serverPortDraft = serverPortDisplayValue
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
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .frame(width: serverLabelWidth, alignment: .leading)
            Spacer(minLength: 0)
            content()
                .frame(width: serverContentWidth, alignment: .trailing)
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
