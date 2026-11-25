import CoreImage
import CoreImage.CIFilterBuiltins

struct LabelArtworkEffects: Sendable {
    var noiseAmount = 0.0
    var grainSize = 0.30
    var halftoneAmount = 0.0
    var screen: LabelHalftoneScreen = .cmyk
    var dotSpacing = 1.25
    var angle = 45.0

    var isActive: Bool { noiseAmount > 0 || halftoneAmount > 0 }
}

enum LabelHalftoneScreen: String, CaseIterable, Identifiable, Sendable {
    case cmyk = "CMYK"
    case monochrome = "Monochrome"

    var id: Self { self }
}

enum LabelArtworkFilters {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func render(_ image: CGImage, effects: LabelArtworkEffects, pixelsPerMM: CGFloat) throws -> CGImage {
        let source = CIImage(cgImage: image)
        var result = source
        if effects.halftoneAmount > 0 {
            guard let screen = screened(source, effects: effects, pixelsPerMM: pixelsPerMM),
                  let mixed = blend(source, screen, amount: effects.halftoneAmount) else {
                throw LabelDesignError.effects
            }
            result = mixed
        }
        if effects.noiseAmount > 0 {
            guard let texture = grain(over: result, size: effects.grainSize * pixelsPerMM),
                  let mixed = blend(result, texture, amount: effects.noiseAmount) else {
                throw LabelDesignError.effects
            }
            result = mixed
        }
        guard let rendered = context.createCGImage(result, from: source.extent) else {
            throw LabelDesignError.effects
        }
        return rendered
    }

    private static func screened(_ image: CIImage, effects: LabelArtworkEffects, pixelsPerMM: CGFloat) -> CIImage? {
        // The screen is centered on the cut. Millimeters keep its pitch stable across raster resolutions.
        let center = CGPoint(x: image.extent.midX, y: image.extent.midY)
        let width = Float(max(2, effects.dotSpacing * pixelsPerMM))
        let angle = Float(effects.angle * .pi / 180)
        switch effects.screen {
        case .cmyk:
            let filter = CIFilter.cmykHalftone()
            filter.inputImage = image.clampedToExtent()
            filter.center = center
            filter.width = width
            filter.angle = angle
            filter.sharpness = 0.72
            return filter.outputImage?.cropped(to: image.extent)
        case .monochrome:
            let filter = CIFilter.dotScreen()
            filter.inputImage = image.clampedToExtent()
            filter.center = center
            filter.width = width
            filter.angle = angle
            filter.sharpness = 0.72
            return filter.outputImage?.cropped(to: image.extent)
        }
    }

    private static func grain(over image: CIImage, size: CGFloat) -> CIImage? {
        guard let noise = CIFilter.randomGenerator().outputImage else { return nil }
        let scale = max(1, size)
        let monochrome = CIFilter.colorControls()
        monochrome.inputImage = noise.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        monochrome.saturation = 0

        let softLight = CIFilter.softLightBlendMode()
        softLight.inputImage = monochrome.outputImage?.cropped(to: image.extent)
        softLight.backgroundImage = image
        return softLight.outputImage
    }

    private static func blend(_ original: CIImage, _ textured: CIImage, amount: Double) -> CIImage? {
        let filter = CIFilter.dissolveTransition()
        filter.inputImage = original
        filter.targetImage = textured
        filter.time = Float(amount)
        return filter.outputImage
    }
}
