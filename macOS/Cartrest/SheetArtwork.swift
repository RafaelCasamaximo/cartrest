import CoreGraphics
import Foundation
import ImageIO

/// Artwork has a stable ID and retains its crop when the selection changes.
/// The normalized zoom and offset controls also drive export.
struct SheetArtwork: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let image: CGImage
    var isSample = false
    var zoom: CGFloat = 1
    var x: CGFloat = 0
    var y: CGFloat = 0
    var copies = 1

    static func sample(named filename: String, in bundle: Bundle) -> SheetArtwork? {
        guard let resources = bundle.resourceURL else { return nil }
        let url = resources.appending(path: "SampleArtwork", directoryHint: .isDirectory).appending(path: filename)
        return try? load(url, isSample: true)
    }

    /// Keeps selection order and reports each file that failed to load.
    /// Invalid files leave room for the next file in the batch.
    static func loadBatch(_ urls: [URL], availableSlots: Int, maxCopies: Int) -> ArtworkImportResult {
        var artworks: [SheetArtwork] = []
        var failures: [String] = []
        for url in urls {
            if artworks.count >= availableSlots {
                failures.append("Each export supports up to \(maxCopies) stickers.")
                break
            }
            do {
                artworks.append(try load(url))
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        return ArtworkImportResult(artworks: artworks, failures: failures)
    }

    static func load(_ url: URL, isSample: Bool = false) throws -> SheetArtwork {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ArtworkImportError.invalidFile(url.lastPathComponent)
        }

        // Image I/O applies the source orientation before cropping. The longest
        // side of the decoded first image is capped at 4,600 px to limit batch memory.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4600
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ArtworkImportError.invalidFile(url.lastPathComponent)
        }
        return SheetArtwork(name: url.deletingPathExtension().lastPathComponent,
                            image: image, isSample: isSample)
    }
}

struct ArtworkImportResult: Sendable {
    let artworks: [SheetArtwork]
    let failures: [String]
}

private enum ArtworkImportError: LocalizedError {
    case invalidFile(String)

    var errorDescription: String? {
        switch self {
        case .invalidFile(let name):
            "Could not open \(name). Try saving the image as PNG or JPEG."
        }
    }
}
