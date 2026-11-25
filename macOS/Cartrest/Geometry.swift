import CoreGraphics
import Foundation

/// Console profiles supply nominal dimensions in millimeters,
/// and the face starts at the top left, with X increasing right and Y increasing down.
struct Geometry: Decodable, Sendable {
    let unit: String
    let body: Body
    let recess: Recess
    let label: Label
    let arrow: Arrow?
    let grip: Recess?

    struct CornerRadii: Decodable, Sendable {
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

    struct Body: Decodable, Sendable {
        let width: CGFloat
        let height: CGFloat
        let thickness: CGFloat
        let cornerRadii: CornerRadii
        // Custom outlines cover shapes with a tab or a keyed corner.
        let vertices: [Vertex]?

        func outline(in rect: CGRect) -> CGPath {
            let scale = min(rect.width / width, rect.height / height)
            if let vertices, !vertices.isEmpty {
                let path = CGMutablePath()
                path.addLines(between: vertices.map {
                    CGPoint(x: rect.minX + $0.x * scale, y: rect.minY + $0.y * scale)
                })
                path.closeSubpath()
                return path
            }
            return roundedOutline(in: rect, cornerRadii: cornerRadii.scaled(by: scale), chamfer: 0)
        }
    }

    struct Vertex: Decodable, Sendable {
        let x: CGFloat
        let y: CGFloat
    }

    /// The label outline already accounts for clearance inside the recess.
    struct Label: Decodable, Sendable {
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

    struct Recess: Decodable, Sendable {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let radius: CGFloat
        let chamfer: CGFloat
        let depth: CGFloat

        var bounds: CGRect { CGRect(x: x, y: y, width: width, height: height) }

        func outline(in rect: CGRect) -> CGPath {
            let scale = min(rect.width / width, rect.height / height)
            return roundedOutline(in: rect, radius: radius * scale, chamfer: chamfer * scale)
        }

        fileprivate func scaled(by factor: CGFloat) -> Recess {
            Recess(x: x * factor, y: y * factor, width: width * factor, height: height * factor,
                   radius: radius * factor, chamfer: chamfer * factor, depth: depth * factor)
        }
    }

    struct Arrow: Decodable, Sendable {
        let centerX: CGFloat
        let top: CGFloat
        let width: CGFloat
        let height: CGFloat
        let depth: CGFloat
    }

    /// Scales the same proportions as the STL export, including the recess in Z.
    func scaled(toWidth width: CGFloat) -> Geometry {
        let factor = width / body.width
        guard factor.isFinite, factor > 0, (body.height * factor).isFinite else { return self }
        return Geometry(
            unit: unit,
            body: Body(
                width: width, height: body.height * factor,
                thickness: body.thickness * factor, cornerRadii: body.cornerRadii.scaled(by: factor),
                vertices: body.vertices?.map { Vertex(x: $0.x * factor, y: $0.y * factor) }
            ),
            recess: recess.scaled(by: factor),
            label: Label(
                x: label.x * factor, y: label.y * factor,
                width: label.width * factor, height: label.height * factor,
                radius: label.radius * factor, chamfer: label.chamfer * factor
            ),
            arrow: arrow.map {
                Arrow(centerX: $0.centerX * factor, top: $0.top * factor,
                      width: $0.width * factor, height: $0.height * factor, depth: $0.depth * factor)
            },
            grip: grip?.scaled(by: factor)
        )
    }

    func validateDimensions() throws {
        guard unit == "mm", (10...500).contains(body.width), (0.01...1_000).contains(body.height),
              (0.01...100).contains(body.thickness) else {
            throw ProfileError.invalid("Use millimeters and positive body dimensions within the profile limits.")
        }

        let face = CGRect(x: 0, y: 0, width: body.width, height: body.height)
        try recess.validate(in: face, thickness: body.thickness, field: "recess")
        if let grip { try grip.validate(in: face, thickness: body.thickness, field: "grip") }

        let labelRect = CGRect(x: label.x, y: label.y, width: label.width, height: label.height)
        guard [label.x, label.y, label.width, label.height].allSatisfy(\.isFinite),
              label.width > 0, label.height > 0, recess.bounds.contains(labelRect),
              Self.isValidCorner(radius: label.radius, chamfer: label.chamfer,
                                 shortSide: min(label.width, label.height)) else {
            throw ProfileError.invalid("The label measurements must fit inside the recess.")
        }
        if let arrow {
            let rect = CGRect(x: arrow.centerX - arrow.width / 2, y: arrow.top, width: arrow.width, height: arrow.height)
            guard [arrow.centerX, arrow.top, arrow.width, arrow.height, arrow.depth].allSatisfy(\.isFinite),
                  arrow.width > 0, arrow.height > 0, arrow.depth > 0,
                  arrow.depth < body.thickness, face.contains(rect) else {
                throw ProfileError.invalid("The insertion arrow must fit on the front face.")
            }
        }
        if let vertices = body.vertices {
            guard (3...256).contains(vertices.count), vertices.allSatisfy({
                (0...body.width).contains($0.x) && (0...body.height).contains($0.y)
            }) else {
                throw ProfileError.invalid("Use 3–256 outline vertices within the body dimensions.")
            }
        }

        let limit = min(body.width, body.height) / 2
        let radii = [body.cornerRadii.topLeft, body.cornerRadii.topRight,
                     body.cornerRadii.bottomRight, body.cornerRadii.bottomLeft]
        guard radii.allSatisfy({ (0...limit).contains($0) }) else {
            throw ProfileError.invalid("Each body corner radius must be no larger than half the shorter side.")
        }
    }

    fileprivate static func isValidCorner(radius: CGFloat, chamfer: CGFloat, shortSide: CGFloat) -> Bool {
        (0...(shortSide / 2)).contains(radius) && (0...(shortSide - radius)).contains(chamfer)
    }
}

extension Geometry.Recess {
    func validate(in rect: CGRect, thickness: CGFloat, field: String) throws {
        guard [x, y, width, height, depth].allSatisfy(\.isFinite),
              width > 0, height > 0, depth > 0, depth < thickness, rect.contains(bounds),
              Geometry.isValidCorner(radius: radius, chamfer: chamfer, shortSide: min(width, height)) else {
            throw ProfileError.invalid("The \(field) measurements and depth must fit inside the body.")
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
