import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var isResetConfirmationPresented = false
    @State private var isResetting = false

    var body: some View {
        @Bindable var store = store

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
                LabeledContent("Address") {
                    HStack(spacing: 4) {
                        TextField("Auto-detected", text: $store.serverHost)
                            .frame(width: 180)
                            .onChange(of: store.serverHost) {
                                store.save()
                            }
                        Text(":")
                            .foregroundStyle(.secondary)
                        TextField("Port", value: $store.serverPort, format: .number)
                            .frame(width: 70)
                            .onChange(of: store.serverPort) {
                                store.save()
                            }
                    }
                }

                Toggle("Start server when app launches", isOn: $store.autoStartServer)
                    .onChange(of: store.autoStartServer) {
                        store.save()
                    }

                LabeledContent("Feed URL") {
                    Text(store.feedURL)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Automation") {
                Picker("Check for new episodes", selection: $store.autoFetchInterval) {
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
}
