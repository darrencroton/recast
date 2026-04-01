import SwiftUI

struct AddChannelSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Channel or Episode")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Paste a YouTube channel, playlist, or direct episode URL.")
                .font(.body)
                .foregroundStyle(.secondary)

            TextField("https://www.youtube.com/@channel or https://www.youtube.com/watch?v=...", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 400)
                .onSubmit { add() }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    add()
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
                .keyboardShortcut(.defaultAction)
            }

            if isAdding {
                ProgressView("Resolving source…")
                    .controlSize(.small)
            }
        }
        .padding(32)
        .frame(minWidth: 480)
    }

    private func add() {
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        guard url.contains("youtube.com") || url.contains("youtu.be") else {
            errorMessage = "Please enter a valid YouTube URL."
            return
        }

        errorMessage = nil
        isAdding = true
        Task {
            do {
                try await store.addSource(url: url)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isAdding = false
        }
    }
}
