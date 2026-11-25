import CoreGraphics
import CoreText
import Foundation

/// Composes the live proof and the flattened artwork in top-left millimeter coordinates.
enum LabelDesignRenderer {
    private static let ocrB: Data? = {
        guard let url = Bundle.main.url(forResource: "OCRB", withExtension: "otf", subdirectory: "LabelDesigner/Fonts")
        else { return nil }
        return try? Data(contentsOf: url)
    }()

    static func render(
        _ draft: LabelDraft,
        catalog: LabelDesignCatalog,
        label: Geometry.Label,
        bleed: CGFloat,
        dpi: Int,
        previewLimit: CGFloat? = nil
    ) throws -> CGImage {
        guard let template = catalog.template(draft.templateID) else { throw LabelDesignError.missingTemplate }
        let canvasSize = CGSize(width: label.width + 2 * bleed, height: label.height + 2 * bleed)
        guard label.width > 0, label.height > 0, bleed >= 0, bleed.isFinite,
              canvasSize.width.isFinite, canvasSize.height.isFinite else { throw LabelDesignError.canvas }

        // The preview may use fewer pixels, yet its placements match the full-size image.
        let printScale = CGFloat(ArtworkExporter.boundedDPI(dpi)) / 25.4
        let scale = previewLimit.map { min(printScale, $0 / max(canvasSize.width, canvasSize.height)) } ?? printScale
        let width = ArtworkExporter.pixels(canvasSize.width * scale)
        let height = ArtworkExporter.pixels(canvasSize.height * scale)
        guard width > 0, height > 0, width <= ArtworkExporter.maxPixels / height,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw LabelDesignError.canvas }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / canvasSize.width, y: -CGFloat(height) / canvasSize.height)
        context.interpolationQuality = .high

        let canvas = CGRect(origin: .zero, size: canvasSize)
        let trim = CGRect(x: bleed, y: bleed, width: label.width, height: label.height)
        fill(context, canvas, draft.backgroundColor)
        if let artwork = draft.background {
            let frame = backgroundFrame(draft, template: template, artwork: artwork.image, label: label,
                                        bleed: bleed, dpi: dpi, trim: trim)
            drawImage(artwork.image, in: frame, context: context)
        }
        if draft.effects.isActive {
            guard let background = context.makeImage() else { throw LabelDesignError.canvas }
            let processed = try LabelArtworkFilters.render(background, effects: draft.effects, pixelsPerMM: scale)
            drawImage(processed, in: canvas, context: context)
        }

        drawHeader(draft, template: template, catalog: catalog, canvas: canvas, trim: trim, context: context)
        drawFooter(draft, template: template, canvas: canvas, trim: trim, context: context)
        drawTitle(draft, trim: trim, context: context)
        for role in LabelMarkRole.allCases {
            if let mark = draft.marks[role] { drawMark(mark, role: role, catalog: catalog, trim: trim, context: context) }
        }

        guard let image = context.makeImage() else { throw LabelDesignError.canvas }
        return image
    }

    private static func backgroundFrame(
        _ draft: LabelDraft, template: LabelTemplate, artwork: CGImage, label: Geometry.Label,
        bleed: CGFloat, dpi: Int, trim: CGRect
    ) -> CGRect {
        if draft.imageMode == .fill {
            let options = ArtworkOptions(image: artwork, widthMM: label.width, heightMM: label.height,
                                         radiusMM: label.radius, chamferMM: label.chamfer, bleedMM: bleed,
                                         dpi: dpi, zoom: draft.zoom, x: draft.panX, y: draft.panY, copies: 1)
            return ArtworkExporter.imageRect(options)
        }

        // Keep fitted art visible between the two optional bands at the starting zoom.
        let header = headerHeight(draft, template: template, trim: trim)
        let footer = productCode(draft).isEmpty ? 0 : trim.height * template.footerHeight
        let field = CGRect(x: trim.minX, y: trim.minY + header, width: trim.width,
                           height: trim.height - header - footer)
        let fitted = aspectFit(artwork, in: field)
        let size = CGSize(width: fitted.width * draft.zoom, height: fitted.height * draft.zoom)
        return CGRect(x: field.midX - size.width / 2 + field.width * draft.panX * 0.4,
                      y: field.midY - size.height / 2 + field.height * draft.panY * 0.4,
                      width: size.width, height: size.height)
    }

    private static func drawHeader(
        _ draft: LabelDraft, template: LabelTemplate, catalog: LabelDesignCatalog,
        canvas: CGRect, trim: CGRect, context: CGContext
    ) {
        let height = headerHeight(draft, template: template, trim: trim)
        guard height > 0 else { return }
        let layout = catalog.headerLayout(for: template)
        let band = headerBand(layout?.seam, trim: trim, canvas: canvas, height: height)

        context.saveGState()
        if draft.headerStyle == .shadow {
            // Quartz shadows use device space. Convert the print measurements to pixels.
            let pixelsPerMM = abs(context.ctm.d)
            context.setShadow(offset: CGSize(width: 0, height: -height * 0.045 * pixelsPerMM),
                              blur: height * 0.065 * pixelsPerMM, color: CGColor(gray: 0, alpha: 0.65))
        }
        context.addPath(band)
        context.setFillColor(color(draft.headerColor))
        context.fillPath()
        context.restoreGState()

        if let image = draft.headerLogo?.image ?? headerLogo(template, color: draft.headerColor, catalog: catalog) {
            let logoHeight = height * (layout?.logoHeight ?? 0.74) * draft.headerScale
            let x = trim.minX + trim.width * (layout?.logoCenter.x ?? 0.5)
            let y = trim.minY + height * (layout?.logoCenter.y ?? 0.5)
            let maxWidth = 2 * min(x - trim.minX, trim.maxX - x)
            let width = min(trim.width * (layout?.logoWidth ?? 0.80) * draft.headerScale, maxWidth)
            let bounds = CGRect(x: x - width / 2, y: y - logoHeight / 2, width: width, height: logoHeight)
            context.saveGState()
            context.clip(to: trim)
            context.addPath(band)
            context.clip()
            drawImage(image, in: aspectFit(image, in: bounds), context: context)
            context.restoreGState()
        }
    }

    private static func headerHeight(_ draft: LabelDraft, template: LabelTemplate, trim: CGRect) -> CGFloat {
        draft.headerStyle == .hidden ? 0 : trim.height * template.headerHeight * draft.headerHeightScale
    }

    private static func headerLogo(_ template: LabelTemplate, color: UInt32, catalog: LabelDesignCatalog) -> CGImage? {
        if let reverse = template.headerOnDark {
            let red = Double((color >> 16) & 255)
            let green = Double((color >> 8) & 255)
            let blue = Double(color & 255)
            let brightness = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
            if brightness < 0.5 { return catalog.image(reverse) }
        }
        return template.header.flatMap(catalog.image)
    }

    private static func headerBand(
        _ seam: [LabelHeaderLayout.Segment]?, trim: CGRect, canvas: CGRect, height: CGFloat
    ) -> CGPath {
        // Extend past the canvas so the shadow reaches the bleed without fading at the sides.
        let extent = canvas.insetBy(dx: -height, dy: -height)
        guard let seam, let first = seam.first, let last = seam.last else {
            return CGPath(rect: CGRect(x: extent.minX, y: extent.minY, width: extent.width,
                                      height: trim.minY + height - extent.minY), transform: nil)
        }

        func locate(_ point: LabelHeaderLayout.Point) -> CGPoint {
            CGPoint(x: trim.minX + point.x * trim.width, y: trim.minY + point.y * height)
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: extent.minX, y: extent.minY))
        path.addLine(to: CGPoint(x: extent.minX, y: locate(first.end).y))
        path.addLine(to: locate(first.end))
        for segment in seam.dropFirst() {
            let end = locate(segment.end)
            if let controls = segment.controls {
                path.addCurve(to: end, control1: locate(controls[0]), control2: locate(controls[1]))
            } else {
                path.addLine(to: end)
            }
        }
        path.addLine(to: CGPoint(x: extent.maxX, y: locate(last.end).y))
        path.addLine(to: CGPoint(x: extent.maxX, y: extent.minY))
        path.closeSubpath()
        return path
    }

    private static func drawTitle(_ draft: LabelDraft, trim: CGRect, context: CGContext) {
        let value = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let size = min(trim.width, trim.height) * 0.115 * draft.titleScale
        let center = CGPoint(x: trim.midX, y: trim.minY + trim.height * draft.titlePosition)
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
        drawText(value, font: font, center: center,
                 maxWidth: trim.width * 0.85, color: draft.titleColor, tracking: 0, context: context)
    }

    private static func drawMark(
        _ mark: LabelMarkPlacement, role: LabelMarkRole, catalog: LabelDesignCatalog,
        trim: CGRect, context: CGContext
    ) {
        guard let image = mark.custom?.image ?? mark.assetID.flatMap(catalog.image) else { return }
        let width = trim.width * (role == .rating ? 0.21 : 0.27) * mark.scale
        let height = trim.height * (role == .rating ? 0.21 : 0.14) * mark.scale
        let centerX = min(max(trim.minX + trim.width * mark.x, trim.minX + width / 2), trim.maxX - width / 2)
        let centerY = min(max(trim.minY + trim.height * mark.y, trim.minY + height / 2), trim.maxY - height / 2)
        let bounds = CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
        let fitted = aspectFit(image, in: bounds)
        if mark.backing != .none {
            let pad = min(trim.width, trim.height) * 0.015
            let path = CGPath(roundedRect: fitted.insetBy(dx: -pad, dy: -pad), cornerWidth: pad,
                              cornerHeight: pad, transform: nil)
            context.addPath(path)
            context.setFillColor(color(mark.backing == .light ? 0xf9f7f0 : 0x1c201f, alpha: 0.95))
            context.fillPath()
        }
        drawImage(image, in: fitted, context: context)
    }

    private static func drawFooter(
        _ draft: LabelDraft, template: LabelTemplate, canvas: CGRect, trim: CGRect, context: CGContext
    ) {
        let value = productCode(draft)
        guard !value.isEmpty, template.footerHeight > 0 else { return }

        let height = trim.height * template.footerHeight
        let top = trim.maxY - height
        fill(context, CGRect(x: 0, y: top, width: canvas.width, height: canvas.maxY - top), draft.footerColor)
        let size = height * 0.54 * draft.codeScale
        let usesOCRB = template.codeTypeface == .ocrB
        let font: CTFont
        if usesOCRB, let ocrB,
           let provider = CGDataProvider(data: ocrB as CFData), let face = CGFont(provider) {
            font = CTFontCreateWithGraphicsFont(face, size, nil, nil)
        } else {
            font = CTFontCreateWithName("Menlo-Bold" as CFString, size, nil)
        }
        // The DS code uses the font's own spacing and sits high in the light footer.
        let textWidth: CGFloat = usesOCRB && draft.codeAlignment == .right ? 0.925 : 0.82
        let centerY = top + height * (usesOCRB ? 0.38 : 0.45)
        let tracking = usesOCRB ? 0 : trim.width * 0.006
        drawText(value, font: font, center: CGPoint(x: trim.midX, y: centerY),
                 maxWidth: trim.width * textWidth, color: draft.codeColor, tracking: tracking,
                 alignment: draft.codeAlignment, context: context)
    }

    private static func productCode(_ draft: LabelDraft) -> String {
        draft.code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func aspectFit(_ image: CGImage, in bounds: CGRect) -> CGRect {
        let factor = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * factor, height: CGFloat(image.height) * factor)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    private static func drawImage(_ image: CGImage, in frame: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: frame.minX, y: frame.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: frame.size))
        context.restoreGState()
    }

    private static func drawText(
        _ text: String, font: CTFont, center: CGPoint, maxWidth: CGFloat,
        color tint: UInt32, tracking: CGFloat, alignment: LabelCodeAlignment = .center, context: CGContext
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): font,
            .init(kCTForegroundColorAttributeName as String): color(tint),
            .init(kCTKernAttributeName as String): tracking,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        guard width > 0 else { return }
        let factor = min(1, maxWidth / width)
        let left = center.x - maxWidth / 2 + (maxWidth - width * factor) * alignment.position

        context.saveGState()
        context.translateBy(x: left, y: center.y + (ascent - descent) * factor / 2)
        context.scaleBy(x: factor, y: -factor)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func fill(_ context: CGContext, _ rect: CGRect, _ tint: UInt32) {
        context.setFillColor(color(tint))
        context.fill(rect)
    }

    private static func color(_ value: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: alpha)
    }
}
