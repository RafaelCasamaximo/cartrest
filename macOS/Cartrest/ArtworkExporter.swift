import CoreGraphics
import CoreText
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One artwork item on the sheet. The dimensions specify the trim size before adding bleed to each edge.
struct ArtworkOptions {
    let image: CGImage
    let widthMM: CGFloat
    let heightMM: CGFloat
    let radiusMM: CGFloat
    let chamferMM: CGFloat
    let bleedMM: CGFloat
    let dpi: Int
    let zoom: CGFloat
    /// Crop offsets range from -1 to 1. Positive Y moves the artwork down.
    let x: CGFloat
    let y: CGFloat
    let copies: Int
}

struct ArtworkMetrics {
    let artworkWidthMM: CGFloat
    let artworkHeightMM: CGFloat
    let widthPX: Int
    let heightPX: Int
    let copiesPerPage: Int
    let pages: Int

    var canRasterize: Bool {
        widthPX > 0 && heightPX > 0 && widthPX <= ArtworkExporter.maxPixels / heightPX
    }
}

/// Position including bleed. Copies of the same item share an index into the artwork batch.
struct SheetPlacement {
    let artworkIndex: Int
    let rect: CGRect
}

enum ArtworkExporter {
    static let sheetSize = CGSize(width: 210, height: 297)
    static let rulerOrigin = CGPoint(x: 10, y: 275)
    static let rulerLength: CGFloat = 50
    static let maxCopies = 24

    // Quartz uses four bytes per pixel for RGB bitmaps, even for opaque backgrounds.
    static let maxPixels = 16_000_000
    private static let bleedRange: ClosedRange<CGFloat> = 0...10
    private static let margin: CGFloat = 10
    // Leave room for print details above the labels and the ruler below them.
    private static let gridTop: CGFloat = 29
    private static let gridBottom: CGFloat = 266
    private static let gap: CGFloat = 7
    private static let pointsPerMM: CGFloat = 72 / 25.4

    private enum ExportError: LocalizedError {
        case image
        case png
        case pdf
        case a4Fit
        case batch

        var errorDescription: String? {
            switch self {
            case .image: return "The image is too large or has invalid dimensions."
            case .png: return "The PNG could not be created."
            case .pdf: return "The PDF could not be created."
            case .a4Fit: return "The artwork including bleed does not fit on an A4 sheet."
            case .batch: return "Use the same dimensions, bleed and resolution for all artwork, with up to 24 labels in total."
            }
        }
    }

    /// The pixel dimensions are for rasterization. PDF placement and cut dimensions remain in millimeters.
    static func measure(_ options: ArtworkOptions) -> ArtworkMetrics {
        let size = artworkSize(options)
        let grid = a4Grid(size)
        let pixelsPerMM = CGFloat(boundedDPI(options.dpi)) / 25.4
        let validCopies = (1...maxCopies).contains(options.copies)
        let pages = validCopies && grid.capacity > 0
            ? (options.copies + grid.capacity - 1) / grid.capacity
            : 0

        return ArtworkMetrics(
            artworkWidthMM: size.width, artworkHeightMM: size.height,
            widthPX: pixels(size.width * pixelsPerMM), heightPX: pixels(size.height * pixelsPerMM),
            copiesPerPage: grid.capacity, pages: pages
        )
    }

    /// Computes the crop shared by the preview and export. Coordinates are in millimeters
    /// from the top left of the bleed area. The image keeps its aspect ratio and covers the entire area.
    static func imageRect(_ options: ArtworkOptions) -> CGRect {
        let size = artworkSize(options)
        let width = CGFloat(options.image.width)
        let height = CGFloat(options.image.height)
        let zoom = clamp(options.zoom, to: 1...3.5, fallback: 1)
        let scale = max(size.width / width, size.height / height) * zoom
        let imageWidth = width * scale
        let imageHeight = height * scale
        let x = clamp(options.x, to: -1...1)
        let y = clamp(options.y, to: -1...1)
        return CGRect(
            x: (size.width - imageWidth) * (1 - x) / 2,
            y: (size.height - imageHeight) * (1 - y) / 2,
            width: imageWidth,
            height: imageHeight
        )
    }

    static func png(_ options: ArtworkOptions) throws -> Data {
        try png(rasterizedArtwork(options), dpi: options.dpi)
    }

    static func png(_ image: CGImage, dpi resolution: Int) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else { throw ExportError.png }

        // The PNG pHYs chunk records physical resolution in whole pixels per meter.
        let dpi = boundedDPI(resolution)
        let pixelsPerMeter = Int((CGFloat(dpi) / 0.0254).rounded())
        let metadata: [String: Any] = [
            kCGImagePropertyDPIWidth as String: dpi,
            kCGImagePropertyDPIHeight as String: dpi,
            kCGImagePropertyPNGDictionary as String: [
                kCGImagePropertyPNGXPixelsPerMeter as String: pixelsPerMeter,
                kCGImagePropertyPNGYPixelsPerMeter as String: pixelsPerMeter,
            ],
        ]
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.png }
        return data as Data
    }

    /// Places copies in input order, in millimeters from the top left of the A4 sheet.
    /// The grid on each page is centered horizontally.
    static func layout(_ artworks: [ArtworkOptions]) -> [[SheetPlacement]] {
        guard let first = artworks.first, artworks.count <= maxCopies else { return [] }
        let size = artworkSize(first)
        let bleed = clamp(first.bleedMM, to: bleedRange)
        let dpi = boundedDPI(first.dpi)
        guard artworks.allSatisfy({
            $0.widthMM == first.widthMM && $0.heightMM == first.heightMM &&
            clamp($0.bleedMM, to: bleedRange) == bleed && boundedDPI($0.dpi) == dpi &&
            (1...maxCopies).contains($0.copies)
        }) else { return [] }
        let grid = a4Grid(size)
        let total = artworks.reduce(0) { $0 + $1.copies }
        guard grid.capacity > 0, total <= maxCopies else { return [] }

        let indices = artworks.indices.flatMap { Array(repeating: $0, count: artworks[$0].copies) }
        return stride(from: 0, to: indices.count, by: grid.capacity).map { pageStart in
            let pageEnd = min(pageStart + grid.capacity, indices.count)
            let page = indices[pageStart..<pageEnd]
            let columns = min(grid.columns, page.count)
            let gridWidth = CGFloat(columns) * size.width + CGFloat(columns - 1) * gap
            let left = (sheetSize.width - gridWidth) / 2
            return page.enumerated().map { index, artworkIndex in
                let x = left + CGFloat(index % columns) * (size.width + gap)
                let y = gridTop + CGFloat(index / columns) * (size.height + gap)
                return SheetPlacement(
                    artworkIndex: artworkIndex,
                    rect: CGRect(origin: CGPoint(x: x, y: y), size: size)
                )
            }
        }
    }

    static func pdf(_ options: ArtworkOptions) throws -> Data {
        try pdf([options])
    }

    static func pdf(_ artworks: [ArtworkOptions]) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw ExportError.pdf }
        try writePDF(artworks, to: consumer)
        guard data.length > 0 else { throw ExportError.pdf }
        return data as Data
    }

    /// Streams the batch to disk. Publishes the file only after Quartz closes the PDF and
    /// the reader verifies the page count. An existing file stays intact if export fails.
    static func pdf(_ artworks: [ArtworkOptions], to destination: URL) throws {
        guard destination.isFileURL else { throw ExportError.pdf }
        let files = FileManager.default
        let replacementDirectory = try files.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true
        )
        defer { try? files.removeItem(at: replacementDirectory) }
        let temporaryFile = replacementDirectory.appendingPathComponent("Cartrest.pdf")
        guard let consumer = CGDataConsumer(url: temporaryFile as CFURL) else { throw ExportError.pdf }
        let pages = try writePDF(artworks, to: consumer)
        guard let document = CGPDFDocument(temporaryFile as CFURL),
              document.numberOfPages == pages else { throw ExportError.pdf }

        // The replacement directory is on the same volume, so rename publishes the file atomically.
        let result = temporaryFile.withUnsafeFileSystemRepresentation { source in
            destination.withUnsafeFileSystemRepresentation { target in
                guard let source, let target else { return EINVAL }
                return Darwin.rename(source, target) == 0 ? 0 : errno
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
    }

    @discardableResult
    private static func writePDF(_ artworks: [ArtworkOptions], to consumer: CGDataConsumer) throws -> Int {
        guard let first = artworks.first else { throw ExportError.batch }
        let metrics = measure(first)
        guard metrics.copiesPerPage > 0 else { throw ExportError.a4Fit }
        let pages = layout(artworks)
        guard !pages.isEmpty else { throw ExportError.batch }
        guard metrics.canRasterize else { throw ExportError.image }

        var pageBox = CGRect(
            x: 0, y: 0, width: sheetSize.width * pointsPerMM, height: sheetSize.height * pointsPerMM
        )
        let metadata: [String: String] = [
            kCGPDFContextTitle as String: "Cartrest - Vinyl labels",
            kCGPDFContextCreator as String: "Cartrest",
        ]
        guard let context = CGContext(consumer: consumer, mediaBox: &pageBox, metadata as CFDictionary)
        else { throw ExportError.pdf }
        defer { context.closePDF() }

        // Copies of each item are consecutive, so only the current bitmap needs to be cached across pages.
        var raster: (index: Int, image: CGImage)?
        for (page, placements) in pages.enumerated() {
            try autoreleasepool {
                context.beginPDFPage(nil)
                defer { context.endPDFPage() }
                drawHeader(context, options: first, page: page, pages: pages.count)

                for placement in placements {
                    let options = artworks[placement.artworkIndex]
                    let image: CGImage
                    if let raster, raster.index == placement.artworkIndex {
                        image = raster.image
                    } else {
                        image = try rasterizedArtwork(options)
                        raster = (placement.artworkIndex, image)
                    }
                    let rect = placement.rect
                    let corner = point(rect.minX, rect.maxY)
                    context.draw(image, in: CGRect(
                        x: corner.x, y: corner.y, width: rect.width * pointsPerMM, height: rect.height * pointsPerMM
                    ))
                    let bleed = clamp(options.bleedMM, to: bleedRange)
                    let trimRect = rect.insetBy(dx: bleed, dy: bleed)
                    try strokeCutLine(context, rect: trimRect, options: options)
                }
                drawRuler(context)
            }
        }
        return pages.count
    }

    private static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>, fallback: CGFloat = 0) -> CGFloat {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : fallback))
    }

    static func boundedDPI(_ dpi: Int) -> Int {
        min(1200, max(72, dpi))
    }

    static func pixels(_ value: CGFloat) -> Int {
        guard value > 0, value < CGFloat(Int32.max) else { return 0 }
        return max(1, Int(value.rounded()))
    }

    private static func artworkSize(_ options: ArtworkOptions) -> CGSize {
        guard options.widthMM.isFinite, options.heightMM.isFinite,
              options.widthMM > 0, options.heightMM > 0 else { return .zero }
        let bleed = clamp(options.bleedMM, to: bleedRange)
        return CGSize(width: options.widthMM + 2 * bleed, height: options.heightMM + 2 * bleed)
    }

    private static func a4Grid(_ size: CGSize) -> (columns: Int, capacity: Int) {
        guard size.width > 0, size.height > 0 else { return (0, 0) }
        // The last row or column has no trailing gap, so include one gap in the available space.
        let columns = Int((sheetSize.width - 2 * margin + gap) / (size.width + gap))
        let rows = Int((gridBottom - gridTop + gap) / (size.height + gap))
        return (columns, columns * rows)
    }

    private static func rasterizedArtwork(_ options: ArtworkOptions) throws -> CGImage {
        let metrics = measure(options)
        let width = metrics.widthPX
        let height = metrics.heightPX
        guard metrics.canRasterize,
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { throw ExportError.image }

        // Transparent areas use the same white backing as the preview.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        let rect = imageRect(options)
        let scaleX = CGFloat(width) / metrics.artworkWidthMM
        let scaleY = CGFloat(height) / metrics.artworkHeightMM
        // The crop uses a top-left origin and the bitmap context starts at the bottom left.
        let destinationRect = CGRect(
            x: rect.minX * scaleX, y: (metrics.artworkHeightMM - rect.maxY) * scaleY,
            width: rect.width * scaleX, height: rect.height * scaleY
        )
        guard destinationRect.minX.isFinite, destinationRect.minY.isFinite,
              destinationRect.width.isFinite, destinationRect.height.isFinite else { throw ExportError.image }
        context.draw(options.image, in: destinationRect)
        guard let image = context.makeImage() else { throw ExportError.image }
        return image
    }

    private static func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * pointsPerMM, y: (sheetSize.height - y) * pointsPerMM)
    }

    private static func strokeCutLine(_ context: CGContext, rect: CGRect, options: ArtworkOptions) throws {
        let pathMM = outline(in: rect, radius: options.radiusMM, chamfer: options.chamferMM)
        // Flip Y and convert millimeters to points after creating the shared cut outline.
        var toPDF = CGAffineTransform(
            a: pointsPerMM, b: 0, c: 0, d: -pointsPerMM, tx: 0, ty: sheetSize.height * pointsPerMM
        )
        guard let path = pathMM.copy(using: &toPDF) else { throw ExportError.pdf }

        context.saveGState()
        defer { context.restoreGState() }
        // The light stroke behind the dark one keeps the cut line legible on different backgrounds.
        context.setLineDash(phase: 0, lengths: [3, 2])
        context.setLineWidth(1.15)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.addPath(path)
        context.strokePath()
        context.setLineWidth(0.42)
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.addPath(path)
        context.strokePath()
    }

    private static func drawText(_ context: CGContext, _ text: String, x: CGFloat, y: CGFloat, size: CGFloat) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributedText = NSAttributedString(
            string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        context.textPosition = point(x, y)
        CTLineDraw(CTLineCreateWithAttributedString(attributedText), context)
    }

    private static func formatMM(_ measurement: CGFloat) -> String {
        Double(measurement).formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX")))
    }

    private static func drawHeader(_ context: CGContext, options: ArtworkOptions, page: Int, pages: Int) {
        let width = formatMM(options.widthMM)
        let height = formatMM(options.heightMM)
        let bleed = formatMM(clamp(options.bleedMM, to: bleedRange))
        drawText(context, "Cartrest", x: 10, y: 13, size: 15)
        drawText(
            context, "Cut \(width) × \(height) mm   |   Bleed \(bleed) mm   |   \(boundedDPI(options.dpi)) dpi",
            x: 10, y: 20, size: 9
        )
        drawText(context, "Page \(page + 1) of \(pages)", x: 176, y: 20, size: 9)
    }

    private static func drawRuler(_ context: CGContext) {
        let x = rulerOrigin.x
        let y = rulerOrigin.y
        let midpoint = x + rulerLength / 2
        let end = x + rulerLength
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(0.7)
        let segments: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (x, y, end, y), (x, y - 2, x, y + 2),
            (midpoint, y - 1, midpoint, y + 1), (end, y - 2, end, y + 2),
        ]
        for (x1, y1, x2, y2) in segments {
            context.move(to: point(x1, y1))
            context.addLine(to: point(x2, y2))
        }
        context.strokePath()
        drawText(context, "0", x: x, y: y + 7, size: 8)
        drawText(context, formatMM(rulerLength / 2), x: midpoint - 1.6, y: y + 7, size: 8)
        drawText(context, "\(formatMM(rulerLength)) mm", x: end - 3, y: y + 7, size: 8)
        drawText(context, "Print on A4 at 100% (actual size).", x: 87, y: y, size: 9)
        drawText(context, "Check the ruler and cut along the dashed line.", x: 87, y: y + 6, size: 9)
    }
}
