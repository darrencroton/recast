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

private final class BundleLocator {}
