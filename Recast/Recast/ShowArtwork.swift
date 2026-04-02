import AppKit
import Foundation

enum ShowArtwork {
    private static let resourceName = "show-cover"
    private static let resourceExtension = "jpg"

    static func ensureExists(in outputDir: URL) {
        let fileManager = FileManager.default
        let destinationURL = Paths.showArtworkURL(in: outputDir)

        guard !fileManager.fileExists(atPath: destinationURL.path) else { return }
        guard let sourceURL = bundledArtworkURL() else {
            AppLogger.error("Bundled show artwork is missing.", category: "feed")
            return
        }

        do {
            try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            AppLogger.error("Failed to copy show artwork: \(error.localizedDescription)", category: "feed")
        }
    }

    private static func bundledArtworkURL() -> URL? {
        let bundles = [Bundle.main, Bundle(for: BundleLocator.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) {
                return url
            }
        }
        return nil
    }
}

enum EpisodeArtwork {
    private static let minimumDimension = 1400
    private static let maximumDimension = 3000

    static func ensurePodcastReady(at artworkURL: URL) {
        guard let metadata = metadata(for: artworkURL) else { return }
        guard needsNormalization(metadata: metadata) else { return }
        guard let image = NSImage(contentsOf: artworkURL) else {
            AppLogger.error("Failed to load episode artwork at \(artworkURL.path)", category: "feed")
            return
        }

        let targetDimension = targetDimension(for: metadata)
        guard let renderedData = renderJPEG(from: image, canvasDimension: targetDimension) else {
            AppLogger.error("Failed to render normalized episode artwork at \(artworkURL.path)", category: "feed")
            return
        }

        do {
            try renderedData.write(to: artworkURL, options: .atomic)
        } catch {
            AppLogger.error("Failed to save normalized episode artwork at \(artworkURL.path): \(error.localizedDescription)", category: "feed")
        }
    }

    private static func metadata(for artworkURL: URL) -> (width: Int, height: Int)? {
        guard let data = try? Data(contentsOf: artworkURL),
              let representation = NSBitmapImageRep(data: data)
        else {
            return nil
        }
        return (representation.pixelsWide, representation.pixelsHigh)
    }

    private static func needsNormalization(metadata: (width: Int, height: Int)) -> Bool {
        metadata.width != metadata.height
            || metadata.width < minimumDimension
            || metadata.height < minimumDimension
            || metadata.width > maximumDimension
            || metadata.height > maximumDimension
    }

    private static func targetDimension(for metadata: (width: Int, height: Int)) -> Int {
        min(max(max(metadata.width, metadata.height), minimumDimension), maximumDimension)
    }

    private static func renderJPEG(from image: NSImage, canvasDimension: Int) -> Data? {
        let canvasSize = NSSize(width: canvasDimension, height: canvasDimension)
        let bounds = NSRect(origin: .zero, size: canvasSize)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: canvasDimension,
            pixelsHigh: canvasDimension,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        guard let bitmap else { return nil }
        bitmap.size = canvasSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

        let backgroundRect = aspectFillRect(for: image.size, in: bounds)
        image.draw(in: backgroundRect)

        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()

        let foregroundRect = aspectFitRect(for: image.size, in: bounds.insetBy(dx: CGFloat(canvasDimension) * 0.04, dy: CGFloat(canvasDimension) * 0.04))
        image.draw(in: foregroundRect)

        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
    }

    private static func aspectFitRect(for sourceSize: NSSize, in bounds: NSRect) -> NSRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return bounds }
        let scale = min(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
        let size = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return NSRect(
            x: bounds.midX - (size.width / 2),
            y: bounds.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    private static func aspectFillRect(for sourceSize: NSSize, in bounds: NSRect) -> NSRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return bounds }
        let scale = max(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
        let size = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return NSRect(
            x: bounds.midX - (size.width / 2),
            y: bounds.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }
}

enum FeedAssetLinks {
    static func sync(downloadedEpisodes: [Episode], in outputDir: URL) {
        let fileManager = FileManager.default
        let feedAssetsDir = Paths.ensureFeedAssetsDirectory(in: outputDir)

        var desiredPaths: Set<String> = []
        for episode in downloadedEpisodes {
            guard let fileName = episode.fileName else { continue }

            let sourceAudioURL = Paths.episodeFileURL(forRelativePath: fileName, in: outputDir)
            let targetAudioURL = Paths.feedAudioURL(forVideoID: episode.videoID, in: outputDir)
            desiredPaths.insert(targetAudioURL.standardizedFileURL.path)
            refreshAlias(at: targetAudioURL, pointingTo: sourceAudioURL)

            let sourceArtworkURL = Paths.artworkURL(forEpisodeFileName: fileName, in: outputDir)
            let targetArtworkURL = Paths.feedArtworkURL(forVideoID: episode.videoID, in: outputDir)
            if fileManager.fileExists(atPath: sourceArtworkURL.path) {
                desiredPaths.insert(targetArtworkURL.standardizedFileURL.path)
                refreshAlias(at: targetArtworkURL, pointingTo: sourceArtworkURL)
            } else if fileManager.fileExists(atPath: targetArtworkURL.path) {
                try? fileManager.removeItem(at: targetArtworkURL)
            }
        }

        guard let existingURLs = try? fileManager.contentsOfDirectory(
            at: feedAssetsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for existingURL in existingURLs where !desiredPaths.contains(existingURL.standardizedFileURL.path) {
            try? fileManager.removeItem(at: existingURL)
        }
    }

    private static func refreshAlias(at targetURL: URL, pointingTo sourceURL: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }

        func createHardLink() -> Bool {
            do {
                try fileManager.linkItem(at: sourceURL, to: targetURL)
                return true
            } catch {
                return false
            }
        }

        func copyAlias() -> Bool {
            do {
                try fileManager.copyItem(at: sourceURL, to: targetURL)
                return true
            } catch {
                return false
            }
        }

        try? fileManager.removeItem(at: targetURL)
        if createHardLink() { return }

        try? fileManager.removeItem(at: targetURL)
        if createHardLink() { return }

        if copyAlias() { return }

        try? fileManager.removeItem(at: targetURL)
        if copyAlias() { return }

        AppLogger.error(
            "Failed to create feed asset alias \(targetURL.lastPathComponent)",
            category: "feed"
        )
    }
}

private final class BundleLocator {}
