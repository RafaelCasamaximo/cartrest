import CoreGraphics
import Foundation

/// The nominal dimensions are generated alongside the STLs. Units are millimeters,
/// and the face starts at the top left, with X increasing right and Y increasing down.
struct Geometry: Decodable {
    let unit: String
    let body: Body
    let recess: Recess
    let label: Label
    let arrow: Arrow

    struct CornerRadii: Decodable {
        let topLeft: CGFloat
        let topRight: CGFloat
        let bottomRight: CGFloat
        let bottomLeft: CGFloat

        fileprivate func scaled(by factor: CGFloat) -> CornerRadii {
            CornerRadii(
                topLeft: topLeft * factor,
                topRight: topRight * factor,
                bottomRight: bottomRight * factor,
                bottomLeft: bottomLeft * factor
            )
        }
    }

    struct Body: Decodable {
        let width: CGFloat
        let height: CGFloat
        let thickness: CGFloat
        let cornerRadii: CornerRadii

        func outline(in rect: CGRect) -> CGPath {
            let scale = min(rect.width / width, rect.height / height)
            return roundedOutline(in: rect, cornerRadii: cornerRadii.scaled(by: scale), chamfer: 0)
        }
    }

    /// The label outline already accounts for clearance inside the recess.
    struct Label: Decodable {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let radius: CGFloat
        let chamfer: CGFloat

        init(x: CGFloat = 0, y: CGFloat = 0, width: CGFloat, height: CGFloat, radius: CGFloat, chamfer: CGFloat) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.radius = radius
            self.chamfer = chamfer
        }

        func outline(in rect: CGRect) -> CGPath {
            let scale = min(rect.width / width, rect.height / height)
            return roundedOutline(in: rect, radius: radius * scale, chamfer: chamfer * scale)
        }
    }

    struct Recess: Decodable {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let radius: CGFloat
        let chamfer: CGFloat
        let depth: CGFloat

        func outline(in rect: CGRect) -> CGPath {
            let scale = min(rect.width / width, rect.height / height)
            return roundedOutline(in: rect, radius: radius * scale, chamfer: chamfer * scale)
        }
    }

    struct Arrow: Decodable {
        let centerX: CGFloat
        let top: CGFloat
        let width: CGFloat
        let height: CGFloat
        let depth: CGFloat
    }

    static func load(bundle: Bundle = .main) throws -> Geometry {
        guard let url = bundle.url(forResource: "dimensions", withExtension: "json") else {
            throw GeometryError.missingResource
        }
        let geometry = try JSONDecoder().decode(Geometry.self, from: Data(contentsOf: url))
        try geometry.validateDimensions()
        return geometry
    }

    /// Scales the STL footprint in XY. Thickness and recess depth stay fixed so the
    /// recess remains suitable for vinyl at every width.
    func scaled(toWidth width: CGFloat) -> Geometry {
        let factor = width / body.width
        guard factor.isFinite, factor > 0, (body.height * factor).isFinite else { return self }
        return Geometry(
            unit: unit,
            body: Body(
                width: width, height: body.height * factor,
                thickness: body.thickness, cornerRadii: body.cornerRadii.scaled(by: factor)
            ),
            recess: Recess(
                x: recess.x * factor, y: recess.y * factor,
                width: recess.width * factor, height: recess.height * factor,
                radius: recess.radius * factor, chamfer: recess.chamfer * factor,
                depth: recess.depth
            ),
            label: Label(
                x: label.x * factor, y: label.y * factor,
                width: label.width * factor, height: label.height * factor,
                radius: label.radius * factor, chamfer: label.chamfer * factor
            ),
            arrow: Arrow(
                centerX: arrow.centerX * factor, top: arrow.top * factor,
                width: arrow.width * factor, height: arrow.height * factor,
                depth: arrow.depth
            )
        )
    }

    private func validateDimensions() throws {
        let lengths = [
            body.width, body.height, body.thickness,
            recess.width, recess.height, recess.depth,
            label.width, label.height,
            arrow.width, arrow.height, arrow.depth,
        ]
        guard unit == "mm", lengths.allSatisfy({ $0.isFinite && $0 > 0 }),
              recess.depth < body.thickness,
              arrow.depth < body.thickness else { throw GeometryError.invalidDimensions }

        let positions = [recess.x, recess.y, label.x, label.y, arrow.centerX, arrow.top]
        guard positions.allSatisfy(\.isFinite) else { throw GeometryError.invalidDimensions }

        let face = CGRect(x: 0, y: 0, width: body.width, height: body.height)
        let recessRect = CGRect(x: recess.x, y: recess.y, width: recess.width, height: recess.height)
        let labelRect = CGRect(x: label.x, y: label.y, width: label.width, height: label.height)
        let arrowRect = CGRect(x: arrow.centerX - arrow.width / 2, y: arrow.top, width: arrow.width, height: arrow.height)
        guard face.contains(recessRect), recessRect.contains(labelRect),
              face.contains(arrowRect) else { throw GeometryError.invalidDimensions }

        // Require each corner to fit its rectangle so the preview follows the actual STL dimensions.
        let limit = min(body.width, body.height) / 2
        let radii = [
            body.cornerRadii.topLeft, body.cornerRadii.topRight,
            body.cornerRadii.bottomRight, body.cornerRadii.bottomLeft,
        ]
        guard radii.allSatisfy({ (0...limit).contains($0) }),
              isValidCorner(radius: recess.radius, chamfer: recess.chamfer, shortSide: min(recess.width, recess.height)),
              isValidCorner(radius: label.radius, chamfer: label.chamfer, shortSide: min(label.width, label.height))
        else { throw GeometryError.invalidDimensions }
    }

    private func isValidCorner(radius: CGFloat, chamfer: CGFloat, shortSide: CGFloat) -> Bool {
        (0...(shortSide / 2)).contains(radius) && (0...(shortSide - radius)).contains(chamfer)
    }
}

private enum GeometryError: LocalizedError {
    case missingResource
    case invalidDimensions

    var errorDescription: String? {
        switch self {
        case .missingResource: return "The Cartrest dimensions file is missing."
        case .invalidDimensions: return "The Cartrest dimensions file contains invalid measurements."
        }
    }
}

/// Cut outline shared by the preview and PDF. The origin is at the top left.
/// A positive chamfer replaces the rounded bottom-left corner.
func outline(in rect: CGRect, radius: CGFloat, chamfer: CGFloat) -> CGPath {
    roundedOutline(in: rect, radius: radius, chamfer: chamfer)
}

private func roundedOutline(in rect: CGRect, radius: CGFloat, chamfer: CGFloat) -> CGPath {
    let radii = Geometry.CornerRadii(
        topLeft: radius, topRight: radius,
        bottomRight: radius, bottomLeft: radius
    )
    return roundedOutline(in: rect, cornerRadii: radii, chamfer: chamfer)
}

private func roundedOutline(in rect: CGRect, cornerRadii: Geometry.CornerRadii, chamfer: CGFloat) -> CGPath {
    let path = CGMutablePath()
    guard !rect.isEmpty, !rect.isInfinite,
          rect.minX.isFinite, rect.minY.isFinite,
          rect.maxX.isFinite, rect.maxY.isFinite else { return path }

    let left = rect.minX
    let right = rect.maxX
    let top = rect.minY
    let bottom = rect.maxY
    let maxRadius = min(rect.width, rect.height) / 2
    func clamp(_ value: CGFloat, to limit: CGFloat) -> CGFloat {
        value.isFinite ? min(max(value, 0), limit) : 0
    }
    let topLeft = clamp(cornerRadii.topLeft, to: maxRadius)
    let topRight = clamp(cornerRadii.topRight, to: maxRadius)
    let bottomRight = clamp(cornerRadii.bottomRight, to: maxRadius)
    let bottomLeft = clamp(cornerRadii.bottomLeft, to: maxRadius)
    let maxChamfer = min(rect.width - bottomRight, rect.height - topLeft)
    let clampedChamfer = clamp(chamfer, to: maxChamfer)

    func addCorner(at corner: CGPoint, toward next: CGPoint, radius: CGFloat) {
        if radius > 0 {
            path.addArc(tangent1End: corner, tangent2End: next, radius: radius)
        } else {
            path.addLine(to: corner)
        }
    }

    path.move(to: CGPoint(x: left + topLeft, y: top))
    addCorner(at: CGPoint(x: right, y: top), toward: CGPoint(x: right, y: bottom), radius: topRight)
    addCorner(at: CGPoint(x: right, y: bottom), toward: CGPoint(x: left, y: bottom), radius: bottomRight)
    if clampedChamfer > 0 {
        path.addLine(to: CGPoint(x: left + clampedChamfer, y: bottom))
        path.addLine(to: CGPoint(x: left, y: bottom - clampedChamfer))
    } else {
        addCorner(at: CGPoint(x: left, y: bottom), toward: CGPoint(x: left, y: top), radius: bottomLeft)
    }
    addCorner(at: CGPoint(x: left, y: top), toward: CGPoint(x: right, y: top), radius: topLeft)
    path.closeSubpath()
    return path
}
