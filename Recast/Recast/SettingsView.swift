import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store

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
                TextField("Port", value: $store.serverPort, format: .number)
                    .frame(width: 100)
                    .onChange(of: store.serverPort) {
                        store.save()
                    }

                LabeledContent("Feed URL") {
                    Text("http://localhost:\(store.serverPort)/feed.xml")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
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
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 280)
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
