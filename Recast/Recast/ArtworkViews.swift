import AppKit
import SwiftUI

private enum ArtworkImageCache {
    static let shared = NSCache<NSURL, NSImage>()
}

struct LocalArtworkImageView<Placeholder: View>: View {
    let url: URL?
    let contentMode: ContentMode
    let placeholder: Placeholder

    @State private var image: NSImage?

    init(url: URL?, contentMode: ContentMode = .fill, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let url else {
            image = nil
            return
        }

        if let cached = ArtworkImageCache.shared.object(forKey: url as NSURL) {
            image = cached
            return
        }

        guard let loadedImage = NSImage(contentsOf: url) else {
            image = nil
            return
        }

        ArtworkImageCache.shared.setObject(loadedImage, forKey: url as NSURL)
        image = loadedImage
    }
}

struct EpisodeArtworkView: View {
    let artworkURL: URL?

    var body: some View {
        LocalArtworkImageView(url: artworkURL) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary)
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}

struct ChannelArtworkView: View {
    let artworkURL: URL?
    let channelName: String

    var body: some View {
        if artworkURL != nil {
            LocalArtworkImageView(url: artworkURL) {
                ChannelMonogram(name: channelName)
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            ChannelMonogram(name: channelName)
        }
    }
}
