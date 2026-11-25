import SwiftUI

/// Draws the coaster, cut outline, or sheet at screen scale.
/// The 3D model and the exporter supply the same physical coordinates.
struct PreviewCanvas: View {
    let mode: PreviewMode
    let geometry: Geometry
    let palette: CartridgePalette
    let label: Geometry.Label
    let artwork: ArtworkOptions?
    let artworks: [ArtworkOptions]
    let placements: [SheetPlacement]
    let page: Int
    let pageCount: Int
    let bottomInset: CGFloat

    private var matColor: Color { Color(cartrestHex: palette.mat.center) }
    private var gridColor: Color { Color(cartrestHex: palette.grid) }

    var body: some View {
        Canvas { context, size in
            let (start, end) = gradientEndpoints(in: size)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(cartrestHex: palette.mat.highlight), matColor,
                                  Color(cartrestHex: palette.mat.shadow)]),
                startPoint: start, endPoint: end
            ))
            // Reserve room for the measurement display below the coaster or sheet.
            let availableSize = CGSize(width: size.width, height: max(1, size.height - bottomInset))
            switch mode {
            case .coaster:
                drawCoaster(context, size: size, availableSize: availableSize)
            case .cut:
                if let artwork {
                    drawCut(context, artwork: artwork, size: size, availableSize: availableSize)
                } else {
                    drawGrid(context, size: size, from: .zero, scale: 4)
                }
            case .sheet:
                drawSheet(context, size: availableSize)
            case .threeD:
                // The interactive 3D model sits above the mat in this mode.
                let center = CGPoint(x: size.width / 2, y: availableSize.height / 2)
                drawGrid(context, size: size, from: center, scale: 4.5)
            }
        }
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isImage)
    }

    private func gradientEndpoints(in size: CGSize) -> (CGPoint, CGPoint) {
        switch palette.mat.direction {
        case .diagonal:
            (.zero, CGPoint(x: size.width, y: size.height))
        case .reverseDiagonal:
            (CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height))
        case .horizontal:
            (.zero, CGPoint(x: size.width, y: 0))
        case .vertical:
            (.zero, CGPoint(x: 0, y: size.height))
        }
    }

    private var accessibilityDescription: String {
        switch mode {
        case .coaster: "Preview of the sticker on the coaster"
        case .cut: "Preview of the cut outline and bleed"
        case .threeD: "Cutting mat behind the 3D preview"
        case .sheet:
            pageCount > 0 ? "Page \(page) of \(pageCount) with \(placements.count) \(placements.count == 1 ? "sticker" : "stickers")" : "Blank A4 sheet"
        }
    }

    // A shared scale for both axes preserves proportions. The scale is in screen points per millimeter.
    private func fit(_ size: CGSize, within area: CGSize, margin: CGSize) -> (CGRect, CGFloat) {
        let availableWidth = max(1, area.width - margin.width)
        let availableHeight = max(1, area.height - margin.height)
        let scale = min(availableWidth / size.width, availableHeight / size.height)
        let width = size.width * scale
        let height = size.height * scale
        let x = (area.width - width) / 2
        let y = (area.height - height) / 2
        return (CGRect(x: x, y: y, width: width, height: height), scale)
    }

    // The exporter and the preview both measure from the top left, with Y increasing downwards.
    private func transform(_ bounds: CGRect, relativeTo rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: rect.minX + bounds.minX * scale, y: rect.minY + bounds.minY * scale,
               width: bounds.width * scale, height: bounds.height * scale)
    }

    // Anchor the mat grid to the coaster or artwork so it follows the same scale.
    private func drawGrid(_ context: GraphicsContext, size: CGSize, from origin: CGPoint, scale: CGFloat) {
        guard palette.mat.gridOpacity > 0 else { return }
        for (step, opacity) in [(5.0, 0.10), (20.0, 0.17)] {
            let spacing = step * scale
            guard spacing >= 3 else { continue }
            var grid = Path()
            for x in stride(from: origin.x.truncatingRemainder(dividingBy: spacing), to: size.width, by: spacing) {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: origin.y.truncatingRemainder(dividingBy: spacing), to: size.height, by: spacing) {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(gridColor.opacity(opacity * palette.mat.gridOpacity)), lineWidth: 0.65)
        }
    }

    private func drawCoaster(_ ctx: GraphicsContext, size: CGSize, availableSize: CGSize) {
        let body = geometry.body
        let (rect, scale) = fit(
            CGSize(width: body.width, height: body.height), within: availableSize,
            margin: CGSize(width: 112, height: 66)
        )
        drawGrid(ctx, size: size, from: rect.origin, scale: scale)
        let coasterShape = Path(body.outline(in: rect))
        var shadow = ctx
        shadow.addFilter(.shadow(color: .black.opacity(0.52), radius: 12, x: 0, y: 9))
        shadow.fill(coasterShape, with: .color(Color(cartrestHex: palette.shell.shadow)))
        ctx.fill(coasterShape, with: .linearGradient(
            Gradient(colors: [Color(cartrestHex: palette.shell.highlight), Color(cartrestHex: palette.shell.shadow)]),
            startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
        ))
        ctx.stroke(coasterShape, with: .color(.white.opacity(0.26)), lineWidth: 1)
        let recess = geometry.recess
        let recessRect = transform(recess.bounds, relativeTo: rect, scale: scale)
        let recessShape = Path(recess.outline(in: recessRect))
        ctx.fill(recessShape, with: .color(Color(cartrestHex: palette.recess)))
        ctx.stroke(recessShape, with: .color(.white.opacity(0.25)), lineWidth: 0.6)
        if let grip = geometry.grip {
            let gripShape = Path(grip.outline(in: transform(grip.bounds, relativeTo: rect, scale: scale)))
            ctx.fill(gripShape, with: .color(Color(cartrestHex: palette.recess)))
            ctx.stroke(gripShape, with: .color(.white.opacity(0.20)), lineWidth: 0.6)
        }
        // The image includes bleed. On the coaster, the mask shows the final
        // sticker outline inside the recess.
        if let artwork {
            let artworkRect = transform(CGRect(x: label.x - artwork.bleedMM, y: label.y - artwork.bleedMM,
                                   width: label.width + 2 * artwork.bleedMM,
                                   height: label.height + 2 * artwork.bleedMM),
                            relativeTo: rect, scale: scale)
            drawArtwork(artwork, in: artworkRect, clippedToCut: true, ctx: ctx)
        }

        guard let arrow = geometry.arrow else { return }
        var triangle = Path()
        triangle.move(to: CGPoint(x: rect.minX + (arrow.centerX - arrow.width / 2) * scale,
                                  y: rect.minY + arrow.top * scale))
        triangle.addLine(to: CGPoint(x: rect.minX + (arrow.centerX + arrow.width / 2) * scale,
                                      y: rect.minY + arrow.top * scale))
        triangle.addLine(to: CGPoint(x: rect.minX + arrow.centerX * scale,
                                      y: rect.minY + (arrow.top + arrow.height) * scale))
        triangle.closeSubpath()
        ctx.fill(triangle, with: .color(.black.opacity(0.25)))
        ctx.stroke(triangle, with: .color(.white.opacity(0.28)), lineWidth: 0.65)
    }

    private func drawCut(_ ctx: GraphicsContext, artwork: ArtworkOptions, size: CGSize, availableSize: CGSize) {
        let metrics = ArtworkExporter.measure(artwork)
        let (rect, scale) = fit(
            CGSize(width: metrics.artworkWidthMM, height: metrics.artworkHeightMM), within: availableSize,
            margin: CGSize(width: 104, height: 74)
        )
        drawGrid(ctx, size: size, from: rect.origin, scale: scale)
        drawArtwork(artwork, in: rect, clippedToCut: false, ctx: ctx)
        let cut = rect.insetBy(dx: artwork.bleedMM * scale, dy: artwork.bleedMM * scale)
        var shadedRegion = Path(rect)
        shadedRegion.addPath(Path(label.outline(in: cut)))
        // Even-odd fill shades the region between the bleed edge and the cut outline.
        ctx.fill(shadedRegion, with: .color(matColor.opacity(0.42)), style: FillStyle(eoFill: true))
        drawCutLine(artwork, cut: cut, scale: scale, context: ctx)
    }

    private func drawSheet(_ ctx: GraphicsContext, size: CGSize) {
        // The preview uses the PDF sheet size, placements, and ruler.
        let (sheet, scale) = fit(ArtworkExporter.sheetSize, within: size,
                                         margin: CGSize(width: 28, height: 30))
        var shadow = ctx
        shadow.addFilter(.shadow(color: .black.opacity(0.50), radius: 10, x: 0, y: 8))
        shadow.fill(Path(sheet), with: .color(.white))
        ctx.draw(Text("Cartrest").font(.system(size: 4.7 * scale, weight: .semibold)).foregroundColor(.black),
                 at: CGPoint(x: sheet.minX + 10 * scale, y: sheet.minY + 9 * scale),
                 anchor: .topLeading)
        for placement in placements where artworks.indices.contains(placement.artworkIndex) {
            let item = artworks[placement.artworkIndex]
            let rect = transform(placement.rect, relativeTo: sheet, scale: scale)
            drawArtwork(item, in: rect, clippedToCut: false, ctx: ctx)
            let cut = rect.insetBy(dx: item.bleedMM * scale, dy: item.bleedMM * scale)
            drawCutLine(item, cut: cut, scale: scale, context: ctx)
        }
        var ruler = Path()
        let origin = ArtworkExporter.rulerOrigin
        let width = ArtworkExporter.rulerLength
        let start = CGPoint(x: sheet.minX + origin.x * scale, y: sheet.minY + origin.y * scale)
        ruler.move(to: start)
        ruler.addLine(to: CGPoint(x: start.x + width * scale, y: start.y))
        for mark in [0, width / 2, width] {
            ruler.move(to: CGPoint(x: start.x + mark * scale, y: start.y - 1.5 * scale))
            ruler.addLine(to: CGPoint(x: start.x + mark * scale, y: start.y + 1.5 * scale))
        }
        ctx.stroke(ruler, with: .color(.black), lineWidth: 0.55)
        let rulerLabel = Double(width).formatted(.number.precision(.fractionLength(0)))
        ctx.draw(Text("\(rulerLabel) mm").font(.system(size: 2.8 * scale)).foregroundColor(.black),
                 at: CGPoint(x: start.x + width * scale, y: start.y + 3 * scale),
                 anchor: .topTrailing)
    }

    private func drawArtwork(_ item: ArtworkOptions, in rect: CGRect, clippedToCut: Bool, ctx: GraphicsContext) {
        let scale = rect.width / (item.widthMM + 2 * item.bleedMM)
        let bleed = item.bleedMM * scale
        let area = rect.insetBy(dx: bleed, dy: bleed)
        var clippingContext = ctx
        clippingContext.clip(to: clippedToCut
                     ? Path(outline(in: area, radius: item.radiusMM * scale, chamfer: item.chamferMM * scale))
                     : Path(rect))
        // A white backing matches the way the exporter handles transparent pixels.
        clippingContext.fill(Path(rect), with: .color(.white))
        let imageRect = transform(ArtworkExporter.imageRect(item), relativeTo: rect, scale: scale)
        clippingContext.draw(Image(decorative: item.image, scale: 1).interpolation(.high), in: imageRect)
    }

    private func drawCutLine(_ item: ArtworkOptions, cut: CGRect, scale: CGFloat, context: GraphicsContext) {
        let cutPath = Path(outline(in: cut, radius: item.radiusMM * scale, chamfer: item.chamferMM * scale))
        context.stroke(cutPath, with: .color(.white.opacity(0.95)), lineWidth: 1.25)
        context.stroke(cutPath, with: .color(.black.opacity(0.85)),
                        style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))
    }
}
