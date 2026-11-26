import Foundation

/// A base-down rack sized to the portion of a coaster covered by its guides.
struct CoasterHolder: Sendable {
    static let slotRange = 1...24
    static let defaultSlots = 4
    static let clearanceRange = 0.2...1.5
    static let defaultClearance = 0.5

    private static let wall = 3.2
    private static let divider = 4.0
    private static let base = 3.2

    let slotCount: Int
    let slotWidth: Double
    let slotDepth: Double
    private let guideHeight: Double
    private let finReach: Double
    private let footDepth: Double

    var width: Double { slotWidth + 2 * Self.wall }
    var depth: Double { 2 * footDepth + Double(slotCount) * (slotDepth + Self.divider) + Self.divider }
    var height: Double { Self.base + guideHeight }

    init?(profile: ConsoleProfile, coasterWidth: Double, slotCount: Int, clearance: Double) {
        guard profile.widthRange.contains(coasterWidth), Self.slotRange.contains(slotCount),
              Self.clearanceRange.contains(clearance)
        else { return nil }

        let body = profile.geometry.body
        let scale = coasterWidth / body.width
        let coasterHeight = body.height * scale
        let guideHeight = min(44, coasterHeight * 0.34)
        let contactWidth = CartridgeModel.lowerBodyWidth(body, from: body.height - guideHeight / scale) * scale
        guard contactWidth > 0 else { return nil }

        self.slotCount = slotCount
        self.guideHeight = guideHeight
        slotWidth = contactWidth + 2 * clearance
        slotDepth = body.thickness * scale + 2 * clearance
        finReach = min(8, contactWidth * 0.08)
        footDepth = max(10, coasterHeight * 0.14)
    }

    func write(to destination: URL) throws {
        // The end feet extend the base. A divider bounds each opening at both ends.
        let wall = Self.wall
        let xs = [0, wall, wall + finReach, wall + slotWidth - finReach, wall + slotWidth, width]
        var ys = [0, footDepth]
        for _ in 0..<slotCount {
            let opening = ys[ys.count - 1] + Self.divider
            ys.append(contentsOf: [opening, opening + slotDepth])
        }
        ys.append(contentsOf: [depth - footDepth, depth])

        // The last layer of cells bevels the entry by widening each opening.
        let lead = min(0.8, guideHeight / 4)
        let leadHeight = min(1.6, guideHeight / 2)
        let zs = [0, Self.base, height - leadHeight, height]
        var topXs = xs
        topXs[1] -= lead
        topXs[4] += lead
        var topYs = ys
        for y in 2..<(ys.count - 2) {
            topYs[y] += y.isMultiple(of: 2) ? -lead : lead
        }

        func vertex(_ x: Int, _ y: Int, _ z: Int) -> SIMD3<Double> {
            z == zs.count - 1 ? SIMD3(topXs[x], topYs[y], zs[z]) : SIMD3(xs[x], ys[y], zs[z])
        }

        let columns = xs.count - 1
        let rows = ys.count - 1
        let layers = zs.count - 1
        func isSolid(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            guard (0..<columns).contains(x), (0..<rows).contains(y), (0..<layers).contains(z) else {
                return false
            }
            if z == 0 { return true }
            guard y > 0, y < rows - 1 else { return false }
            return x == 0 || x == columns - 1 || (!y.isMultiple(of: 2) && x != 2)
        }

        // Emit exposed faces on a shared grid so the base, rails and fins form one mesh.
        var triangles: [MeshTriangle] = []
        func face(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>, _ d: SIMD3<Double>) {
            triangles.append(MeshTriangle(a, b, c))
            triangles.append(MeshTriangle(a, c, d))
        }

        for z in 0..<layers {
            for y in 0..<rows {
                for x in 0..<columns where isSolid(x, y, z) {
                    let a = vertex(x, y, z)
                    let b = vertex(x + 1, y, z)
                    let c = vertex(x + 1, y + 1, z)
                    let d = vertex(x, y + 1, z)
                    let e = vertex(x, y, z + 1)
                    let f = vertex(x + 1, y, z + 1)
                    let g = vertex(x + 1, y + 1, z + 1)
                    let h = vertex(x, y + 1, z + 1)
                    if !isSolid(x, y, z - 1) { face(d, c, b, a) }
                    if !isSolid(x, y, z + 1) { face(e, f, g, h) }
                    if !isSolid(x - 1, y, z) { face(a, e, h, d) }
                    if !isSolid(x + 1, y, z) { face(b, c, g, f) }
                    if !isSolid(x, y - 1, z) { face(a, b, f, e) }
                    if !isSolid(x, y + 1, z) { face(d, h, g, c) }
                }
            }
        }

        let mesh = try CartridgeSTL(triangles: triangles, header: "Cartrest | millimeters | holder base down")
        try mesh.write(to: destination)
    }
}
