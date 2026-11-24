import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let width = 640
private let height = 400
private let canvasSize = CGSize(width: width, height: height)
private let midX = CGFloat(width) / 2
private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 255) / 255,
        green: CGFloat((hex >> 8) & 255) / 255,
        blue: CGFloat(hex & 255) / 255,
        alpha: alpha
    )
}

private func drawText(_ title: String, baseline: CGFloat, fontSize: CGFloat, weight: NSFont.Weight, ink: UInt32, in context: CGContext) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
        .foregroundColor: NSColor(cgColor: color(ink))!
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: title, attributes: attributes))
    let textWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
    context.textPosition = CGPoint(x: midX - textWidth / 2, y: baseline)
    CTLineDraw(line, context)
}

private func draw(in context: CGContext) {
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [color(0x28443a), color(0x132823)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 70, y: height), end: CGPoint(x: 580, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // The grid carries over the editor's cutting mat.
    for x in stride(from: 0, through: width, by: 20) {
        context.setStrokeColor(color(0x84af99, alpha: x.isMultiple(of: 100) ? 0.19 : 0.09))
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: x, y: 0))
        context.addLine(to: CGPoint(x: x, y: height))
        context.strokePath()
    }
    for y in stride(from: 0, through: height, by: 20) {
        context.setStrokeColor(color(0x84af99, alpha: y.isMultiple(of: 100) ? 0.19 : 0.09))
        context.move(to: CGPoint(x: 0, y: y))
        context.addLine(to: CGPoint(x: width, y: y))
        context.strokePath()
    }

    // Finder measures icon positions from the top. Core Graphics measures from the bottom.
    let iconsMidY: CGFloat = CGFloat(height) - 229
    for x: CGFloat in [174, 466] {
        let rect = CGRect(x: x - 73, y: iconsMidY - 68, width: 146, height: 133)
        let outline = CGPath(roundedRect: rect, cornerWidth: 17, cornerHeight: 17, transform: nil)
        context.setFillColor(color(0x9cbea5, alpha: 0.10))
        context.addPath(outline)
        context.fillPath()
        context.setStrokeColor(color(0xb0d9b7, alpha: 0.24))
        context.setLineWidth(1)
        context.addPath(outline)
        context.strokePath()
    }

    // Keep the arrow outside the draggable icon areas.
    context.setStrokeColor(color(0xa9d5af))
    context.setLineWidth(2.4)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: midX - 24, y: iconsMidY))
    context.addLine(to: CGPoint(x: midX + 24, y: iconsMidY))
    context.move(to: CGPoint(x: midX + 15, y: iconsMidY + 9))
    context.addLine(to: CGPoint(x: midX + 24, y: iconsMidY))
    context.addLine(to: CGPoint(x: midX + 15, y: iconsMidY - 9))
    context.strokePath()

    drawText("Cartrest", baseline: 325, fontSize: 43, weight: .semibold, ink: 0xf0f5e9, in: context)
    drawText("Drag Cartrest to Applications.", baseline: 291, fontSize: 16, weight: .medium, ink: 0xc7ddcb, in: context)
}

enum RenderError: LocalizedError {
    case image

    var errorDescription: String? { "Could not write the installer background." }
}

private func write(scale: Int, in file: URL) throws {
    guard let context = CGContext(data: nil, width: width * scale, height: height * scale, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw RenderError.image
    }
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.clip(to: CGRect(origin: .zero, size: canvasSize))
    draw(in: context)
    guard let image = context.makeImage(),
          let output = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw RenderError.image
    }
    let metadata = [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale]
    CGImageDestinationAddImage(output, image, metadata as CFDictionary)
    guard CGImageDestinationFinalize(output) else { throw RenderError.image }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Provide the output directory for the background.\n".utf8))
    exit(2)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
do {
    try write(scale: 1, in: directory.appendingPathComponent("background.png"))
    try write(scale: 2, in: directory.appendingPathComponent("background@2x.png"))
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
