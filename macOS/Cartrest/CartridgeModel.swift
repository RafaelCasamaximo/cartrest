import Foundation

/// Interprets the profile's construction recipe as an extrusion with shallow
/// cuts on its front and rear faces. Coordinates in the recipe are millimeters.
enum CartridgeModel {
    static func build(from profile: ConsoleProfile) throws -> CartridgeSTL {
        let geometry = profile.geometry
        let body = geometry.body
        let outer = Outline.body(body)
        try outer.validate(width: body.width, height: body.height)

        let cuts = try FaceCuts(profile)
        // A continuous plastic layer connects both faces even where cuts overlap in XY.
        let frontDepth = cuts.front.map(\.depth).max() ?? 0
        let rearDepth = cuts.rear.map(\.depth).max() ?? 0
        guard frontDepth + rearDepth < body.thickness else {
            throw ProfileError.invalid("Leave solid material between the deepest front and rear cuts.")
        }

        let label = geometry.label
        let labelOutline = Outline.rounded(CGRect(x: label.x, y: label.y, width: label.width, height: label.height),
                                           radius: label.radius, chamfer: label.chamfer)
        try labelOutline.checkFits(in: .rounded(geometry.recess))

        let outlines = (cuts.front + cuts.rear).map(\.outline)
        guard outlines.allSatisfy({ $0.points.count >= 3 }) else {
            throw ProfileError.invalid("Each cut must have a distinct outline.")
        }
        let slices = Scanlines(outlines: [outer] + outlines)
        var triangles: [MeshTriangle] = []
        let front = try slices.triangulate(outer: outer, cuts: cuts.front, flatZ: body.thickness,
                                          faceHeight: body.height, rear: false, into: &triangles)
        let rear = try slices.triangulate(outer: outer, cuts: cuts.rear, flatZ: 0,
                                         faceHeight: body.height, rear: true, into: &triangles)
        let walls = try Wall.between(front: front, rear: rear)
        Wall.triangulate(walls, into: &triangles)
        return try CartridgeSTL(triangles: triangles)
    }

    static func lowerBodyWidth(_ body: Geometry.Body, from y: Double) -> Double {
        let outline = Outline.body(body)
        // Include the cut through any edge crossing the top of the guide.
        var xs = outline.points.filter { $0.y >= y }.map(\.x)
        if let slice = outline.span(at: y) {
            xs.append(contentsOf: [slice.left, slice.right])
        }
        return (xs.max() ?? 0) - (xs.min() ?? 0)
    }
}

private typealias Point = SIMD2<Double>

/// These values are shared by neighboring bands. Rounding away trigonometric
/// noise ensures a line through a vertex gives that same vertex on both faces.
private func snap(_ value: Double) -> Double {
    (value * 10_000_000).rounded() / 10_000_000
}

private struct Span {
    let left: Double
    let right: Double

    var isPoint: Bool { left == right }
}

private struct Outline {
    let points: [Point]

    init(_ points: [Point]) {
        self.points = points.map { Point(snap($0.x), snap($0.y)) }
    }

    private var segments: [(Point, Point)] {
        points.indices.map { index in (points[index], points[(index + 1) % points.count]) }
    }

    static func body(_ body: Geometry.Body) -> Outline {
        let face = CGRect(x: 0, y: 0, width: body.width, height: body.height)
        let radii = body.cornerRadii
        return body.vertices.map { Outline($0.map { Point($0.x, $0.y) }) }
            ?? .rounded(face, radii: [radii.topLeft, radii.topRight, radii.bottomRight, radii.bottomLeft])
    }

    static func rounded(_ recess: Geometry.Recess) -> Outline {
        rounded(recess.bounds, radius: recess.radius, chamfer: recess.chamfer)
    }

    static func rounded(_ rect: CGRect, radius: Double, chamfer: Double) -> Outline {
        rounded(rect, radii: Array(repeating: radius, count: 4), chamfer: chamfer)
    }

    static func rounded(_ rect: CGRect, radii: [Double], chamfer: Double = 0) -> Outline {
        let corners = [Point(rect.maxX, rect.minY), Point(rect.maxX, rect.maxY),
                       Point(rect.minX, rect.maxY), Point(rect.minX, rect.minY)]
        var points: [Point] = []

        func append(_ point: Point) {
            let vertex = Point(snap(point.x), snap(point.y))
            if points.last != vertex { points.append(vertex) }
        }

        for (index, corner) in corners.enumerated() {
            if index == 2, chamfer > 0 {
                append(corner + Point(chamfer, 0))
                append(corner - Point(0, chamfer))
                continue
            }

            let radius = radii[(index + 1) % corners.count]
            if radius == 0 {
                append(corner)
                continue
            }

            let center = corner + Point(index < 2 ? -radius : radius, index == 0 || index == 3 ? radius : -radius)
            // Twelve segments per quarter-circle match the downloadable models.
            for step in 0...12 {
                let angle = Double(-90 + 90 * index) + Double(step) * 7.5
                let radians = angle * .pi / 180
                append(center + radius * Point(cos(radians), sin(radians)))
            }
        }
        if points.first == points.last { points.removeLast() }
        return Outline(points)
    }

    func span(at y: Double) -> Span? {
        let hits = intersections(at: y)
        guard let left = hits.min(), let right = hits.max() else { return nil }
        return Span(left: left, right: right)
    }

    func checkFits(in recess: Outline) throws {
        guard points.count >= 3 else { throw ProfileError.invalid("The label needs a distinct outline.") }
        let rows = Set((points + recess.points).map(\.y))
        for y in rows {
            guard let label = span(at: y) else { continue }
            guard let boundary = recess.span(at: y), boundary.left <= label.left, label.right <= boundary.right else {
                throw ProfileError.invalid("The label outline must fit inside the recess, including its corners.")
            }
        }
    }

    func validate(width: Double, height: Double) throws {
        guard points.count >= 3, Set(points).count == points.count,
              points.map(\.x).min() == 0, points.map(\.y).min() == 0,
              points.map(\.x).max() == snap(width), points.map(\.y).max() == snap(height)
        else {
            throw ProfileError.invalid("The body outline must reach the four declared bounds and use distinct vertices.")
        }
        let sides = segments
        for (index, edge) in sides.enumerated() {
            for other in sides.dropFirst(index + 1) {
                if edge.0 == other.1 || edge.1 == other.0 { continue }
                guard !Self.intersect(edge, other) else {
                    throw ProfileError.invalid("The body outline crosses itself.")
                }
            }
        }

        let rows = Set(points.map(\.y)).sorted()
        for (top, bottom) in zip(rows, rows.dropFirst()) {
            let hits = intersections(at: (top + bottom) / 2)
            guard hits.count == 2, hits[0] != hits[1] else {
                throw ProfileError.invalid("Every horizontal slice through the body must have a single continuous span.")
            }
        }
    }

    private func intersections(at y: Double) -> [Double] {
        var hits: [Double] = []
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            guard min(a.y, b.y) <= y, y <= max(a.y, b.y) else { continue }
            if a.y == b.y {
                hits.append(contentsOf: [a.x, b.x])
            } else {
                hits.append(snap(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y)))
            }
        }
        return hits
    }

    private static func intersect(_ first: (Point, Point), _ second: (Point, Point)) -> Bool {
        let (a, b) = first
        let (c, d) = second
        func turn(_ p: Point, _ q: Point, _ r: Point) -> Double {
            let u = q - p
            let v = r - p
            return u.x * v.y - u.y * v.x
        }
        func straddle(_ a: Double, _ b: Double) -> Bool {
            min(a, b) <= 0 && max(a, b) >= 0
        }
        return max(min(a.x, b.x), min(c.x, d.x)) <= min(max(a.x, b.x), max(c.x, d.x))
            && max(min(a.y, b.y), min(c.y, d.y)) <= min(max(a.y, b.y), max(c.y, d.y))
            && straddle(turn(a, b, c), turn(a, b, d)) && straddle(turn(c, d, a), turn(c, d, b))
    }
}

private struct Cut {
    let outline: Outline
    let depth: Double
}

private struct FaceCuts {
    var front: [Cut] = []
    var rear: [Cut] = []

    init(_ profile: ConsoleProfile) throws {
        let geometry = profile.geometry
        let body = geometry.body
        let face = CGRect(x: 0, y: 0, width: body.width, height: body.height)
        guard case .extrudeBody? = profile.instructions.first, profile.instructions.count <= 67 else {
            throw ProfileError.invalid("Start the instructions with extrudeBody. Use at most 67 instructions.")
        }

        func cut(_ recess: Geometry.Recess) -> Cut {
            Cut(outline: .rounded(recess), depth: recess.depth)
        }

        var hasLabel = false
        var hasArrow = false
        var hasGrip = false
        for instruction in profile.instructions.dropFirst() {
            switch instruction {
            case .extrudeBody:
                throw ProfileError.invalid("Use extrudeBody once, as the first instruction.")
            case .recessLabel:
                guard !hasLabel else { throw ProfileError.invalid("Use recessLabel once.") }
                hasLabel = true
                front.append(cut(geometry.recess))
            case .engraveArrow:
                guard let arrow = geometry.arrow, !hasArrow else {
                    throw ProfileError.invalid("Use engraveArrow once and supply geometry.arrow.")
                }
                hasArrow = true
                let halfWidth = arrow.width / 2
                let outline = Outline([Point(arrow.centerX - halfWidth, arrow.top),
                                       Point(arrow.centerX + halfWidth, arrow.top),
                                       Point(arrow.centerX, arrow.top + arrow.height)])
                front.append(Cut(outline: outline, depth: arrow.depth))
            case .recessGrip:
                guard let grip = geometry.grip, !hasGrip else {
                    throw ProfileError.invalid("Use recessGrip once and supply geometry.grip.")
                }
                hasGrip = true
                front.append(cut(grip))
            case .rearChannels(let row):
                guard (1...64).contains(row.count), row.width > 0, row.pitch > row.width,
                      row.x >= 0, (0..<body.height).contains(row.y),
                      (0..<body.thickness).contains(row.depth), row.depth > 0,
                      row.x + Double(row.count - 1) * row.pitch + row.width <= body.width,
                      rear.count + row.count <= 64 else {
                    throw ProfileError.invalid("Fit 1–64 separated rear channels within the body and use a positive depth.")
                }
                for index in 0..<row.count {
                    let x = row.x + Double(index) * row.pitch
                    let rect = CGRect(x: x, y: row.y, width: row.width, height: body.height - row.y)
                    rear.append(Cut(outline: .rounded(rect, radius: 0, chamfer: 0), depth: row.depth))
                }
            case .rearSlot(let slot):
                let height = body.height - slot.y
                guard slot.x >= 0, slot.y >= 0, slot.width > 0, height > 0,
                      slot.x + slot.width <= body.width, slot.depth > 0, slot.depth < body.thickness,
                      (0...min(slot.width / 2, height)).contains(slot.radius) else {
                    throw ProfileError.invalid("The rear slot must fit between its upper end and the insertion edge.")
                }
                let rect = CGRect(x: slot.x, y: slot.y, width: slot.width, height: height)
                rear.append(Cut(outline: .rounded(rect, radii: [slot.radius, slot.radius, 0, 0]), depth: slot.depth))
            case .rearRecess(let recess):
                try recess.validate(in: face, thickness: body.thickness, field: "rearRecess")
                rear.append(cut(recess))
            }
        }

        guard hasLabel, (geometry.arrow != nil) == hasArrow, (geometry.grip != nil) == hasGrip else {
            throw ProfileError.invalid("Include recessLabel and a matching instruction for each optional front feature.")
        }
        guard rear.count <= 64 else { throw ProfileError.invalid("Use at most 64 individual rear cuts.") }
    }
}

private struct Edge: Hashable, Comparable {
    let start: Point
    let end: Point

    init(_ a: Point, _ b: Point) {
        (start, end) = Self.precedes(a, b) ? (a, b) : (b, a)
    }

    private static func precedes(_ a: Point, _ b: Point) -> Bool {
        a.x == b.x ? a.y < b.y : a.x < b.x
    }

    static func < (a: Edge, b: Edge) -> Bool {
        a.start == b.start ? precedes(a.end, b.end) : precedes(a.start, b.start)
    }
}

private struct EdgeSide {
    let a: Point
    let b: Point
    let z: Double
}

/// Split both faces at the same Y levels and include every X boundary mark.
/// Adjacent bands then share edges even where a cut starts or reaches the rim.
private struct Scanlines {
    let rows: [Double]
    let marks: [Double: [Double]]

    init(outlines: [Outline]) {
        rows = Set(outlines.flatMap { $0.points.map(\.y) }).sorted()
        marks = Dictionary(uniqueKeysWithValues: rows.map { y in
            let spans = outlines.compactMap { $0.span(at: y) }
            return (y, Set(spans.flatMap { [$0.left, $0.right] }).sorted())
        })
    }

    func triangulate(outer: Outline, cuts: [Cut], flatZ: Double, faceHeight: Double, rear: Bool,
                     into triangles: inout [MeshTriangle]) throws -> [Edge: [EdgeSide]] {
        var edges: [Edge: [EdgeSide]] = [:]

        for (top, bottom) in zip(rows, rows.dropFirst()) {
            guard let upper = outer.span(at: top), let lower = outer.span(at: bottom) else {
                throw ProfileError.invalid("A cut extends beyond the cartridge outline.")
            }
            let middle = (top + bottom) / 2
            let active = cuts.compactMap { cut in cut.outline.span(at: middle).map { ($0.left, cut) } }
                .sorted { $0.0 < $1.0 }

            func appendCell(topSpan: Span, bottomSpan: Span, z: Double) {
                guard !topSpan.isPoint || !bottomSpan.isPoint else { return }
                let topEdge = marks[top, default: []].filter { topSpan.left <= $0 && $0 <= topSpan.right }
                    .map { Point($0, snap(faceHeight - top)) }
                let bottomEdge = marks[bottom, default: []].filter { bottomSpan.left <= $0 && $0 <= bottomSpan.right }
                    .map { Point($0, snap(faceHeight - bottom)) }
                let polygon = bottomEdge + topEdge.reversed()
                let center = polygon.reduce(.zero, +) / Double(polygon.count)

                for (a, b) in zip(polygon, Array(polygon.dropFirst()) + polygon.prefix(1)) {
                    edges[Edge(a, b), default: []].append(EdgeSide(a: a, b: b, z: z))
                    triangles.append(MeshTriangle(vertex(center, z), vertex(rear ? b : a, z), vertex(rear ? a : b, z)))
                }
            }

            var leftTop = upper.left
            var leftBottom = lower.left
            for (_, cut) in active {
                guard let a = cut.outline.span(at: top), let b = cut.outline.span(at: bottom),
                      leftTop <= a.left, a.right <= upper.right,
                      leftBottom <= b.left, b.right <= lower.right else {
                    throw ProfileError.invalid("Cuts on the same face must stay inside the outline and avoid overlap.")
                }
                appendCell(topSpan: Span(left: leftTop, right: a.left),
                           bottomSpan: Span(left: leftBottom, right: b.left), z: flatZ)
                appendCell(topSpan: a, bottomSpan: b, z: rear ? cut.depth : flatZ - cut.depth)
                leftTop = a.right
                leftBottom = b.right
            }
            appendCell(topSpan: Span(left: leftTop, right: upper.right),
                       bottomSpan: Span(left: leftBottom, right: lower.right), z: flatZ)
        }
        return edges
    }
}

private func vertex(_ point: Point, _ z: Double) -> SIMD3<Double> {
    SIMD3(point.x, point.y, z)
}

private struct Wall {
    let a: Point
    let b: Point
    let bottom: Double
    let top: Double

    static func between(front: [Edge: [EdgeSide]], rear: [Edge: [EdgeSide]]) throws -> [Wall] {
        var walls: [Wall] = []
        var rearRim: Set<Edge> = Set(rear.keys.filter { rear[$0]?.count == 1 })
        for edge in front.keys.sorted() {
            guard let sides = front[edge], let upper = sides.max(by: { $0.z < $1.z }), sides.count <= 2 else {
                throw ProfileError.invalid("Front cuts form overlapping faces.")
            }
            let bottom: Double
            if sides.count == 2 {
                bottom = min(sides[0].z, sides[1].z)
            } else {
                guard rearRim.remove(edge) != nil, let lower = rear[edge]?.first else {
                    throw ProfileError.invalid("Front and rear outlines must match at the rim.")
                }
                bottom = lower.z
            }
            if bottom < upper.z { walls.append(Wall(a: upper.a, b: upper.b, bottom: bottom, top: upper.z)) }
        }
        guard rearRim.isEmpty else { throw ProfileError.invalid("Front and rear outlines must match at the rim.") }

        for edge in rear.keys.sorted() {
            guard let sides = rear[edge], sides.count <= 2 else {
                throw ProfileError.invalid("Rear cuts form overlapping faces.")
            }
            if sides.count == 2 {
                let ordered = sides.sorted { $0.z < $1.z }
                let lower = ordered[0]
                let upper = ordered[1]
                if lower.z < upper.z { walls.append(Wall(a: lower.a, b: lower.b, bottom: lower.z, top: upper.z)) }
            }
        }
        return walls
    }

    static func triangulate(_ walls: [Wall], into triangles: inout [MeshTriangle]) {
        var levels: [Point: Set<Double>] = [:]
        for wall in walls {
            levels[wall.a, default: []].formUnion([wall.bottom, wall.top])
            levels[wall.b, default: []].formUnion([wall.bottom, wall.top])
        }

        for wall in walls {
            let (a, b, bottom, top) = (wall.a, wall.b, wall.bottom, wall.top)
            func splits(at point: Point) -> [Double] {
                levels[point, default: []].filter { bottom < $0 && $0 < top }.sorted()
            }
            let aSplits = splits(at: a)
            let bSplits = splits(at: b)
            if aSplits.isEmpty, bSplits.isEmpty {
                triangles.append(MeshTriangle(vertex(a, bottom), vertex(b, bottom), vertex(b, top)))
                triangles.append(MeshTriangle(vertex(a, bottom), vertex(b, top), vertex(a, top)))
            } else {
                // A channel can introduce a height change on just one end of a
                // wall. Use every level at that corner to avoid a T-junction.
                let polygon = [vertex(a, bottom), vertex(b, bottom)] + bSplits.map { vertex(b, $0) }
                    + [vertex(b, top), vertex(a, top)] + aSplits.reversed().map { vertex(a, $0) }
                let center = vertex((a + b) / 2, (bottom + top) / 2)
                for (first, second) in zip(polygon, Array(polygon.dropFirst()) + polygon.prefix(1)) {
                    triangles.append(MeshTriangle(center, first, second))
                }
            }
        }
    }
}
