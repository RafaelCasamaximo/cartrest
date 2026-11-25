import Foundation
import simd

struct MeshTriangle {
    let a: SIMD3<Double>
    let b: SIMD3<Double>
    let c: SIMD3<Double>

    init(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) {
        self.a = a
        self.b = b
        self.c = c
    }
}

/// One nominal mesh serves both the SceneKit preview and proportional STL export.
struct CartridgeSTL: Sendable {
    private static let headerSize = 84
    private static let facetSize = 50
    private let data: Data
    let facetCount: Int

    init(triangles: [MeshTriangle]) throws {
        guard !triangles.isEmpty, let count = UInt32(exactly: triangles.count) else {
            throw STLError.invalidModel
        }

        var output = Data("Cartrest | millimeters | label face up".utf8)
        output.append(Data(repeating: 32, count: 80 - output.count))
        output.appendInteger(count)
        output.reserveCapacity(Self.headerSize + triangles.count * Self.facetSize)

        var edges: [MeshEdge: Incident] = [:]
        var neighbors = Array(repeating: [Int](), count: triangles.count)
        var volume = 0.0
        for (index, triangle) in triangles.enumerated() {
            // Check the coordinates at STL precision, where close vertices can coincide.
            let a = SIMD3<Float>(triangle.a)
            let b = SIMD3<Float>(triangle.b)
            let c = SIMD3<Float>(triangle.c)
            let origin = SIMD3<Double>(a)
            let cross = simd_cross(SIMD3<Double>(b) - origin, SIMD3<Double>(c) - origin)
            let length = simd_length(cross)
            guard length.isFinite, length > 0 else { throw STLError.degenerate }
            output.appendVector(SIMD3<Float>(cross / length))
            output.appendVector(a)
            output.appendVector(b)
            output.appendVector(c)
            output.appendInteger(UInt16(0))
            volume += simd_dot(origin, cross) / 6

            for (start, end) in [(a, b), (b, c), (c, a)] {
                let forward = MeshEdge.precedes(start, end)
                let edge = forward ? MeshEdge(a: start, b: end) : MeshEdge(a: end, b: start)
                if let incident = edges[edge] {
                    guard !incident.isPaired, incident.forward != forward else { throw STLError.openMesh }
                    neighbors[index].append(incident.face)
                    neighbors[incident.face].append(index)
                    edges[edge]?.isPaired = true
                } else {
                    edges[edge] = Incident(face: index, forward: forward)
                }
            }
        }

        guard edges.values.allSatisfy(\.isPaired) else { throw STLError.openMesh }
        var pending = [0]
        var visited = Set(pending)
        while let index = pending.popLast() {
            for neighbor in neighbors[index] where visited.insert(neighbor).inserted {
                pending.append(neighbor)
            }
        }
        guard visited.count == triangles.count, volume.isFinite, volume > 0 else { throw STLError.invalidModel }
        data = output
        facetCount = triangles.count
    }

    func forEachFacet(_ visit: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) -> Void) {
        data.withUnsafeBytes { buffer in
            func vector(at offset: Int) -> SIMD3<Float> {
                SIMD3(Self.float(in: buffer, at: offset), Self.float(in: buffer, at: offset + 4),
                      Self.float(in: buffer, at: offset + 8))
            }
            for index in 0..<facetCount {
                let offset = Self.headerSize + index * Self.facetSize
                visit(vector(at: offset), vector(at: offset + 12), vector(at: offset + 24), vector(at: offset + 36))
            }
        }
    }

    func write(scaledBy scale: CGFloat, to destination: URL) throws {
        guard scale.isFinite, scale > 0 else { throw STLError.invalidScale }
        if scale == 1 {
            try data.write(to: destination, options: .atomic)
            return
        }

        // Revalidate at the requested width before handing the slicer a mesh.
        var triangles: [MeshTriangle] = []
        triangles.reserveCapacity(facetCount)
        forEachFacet { _, a, b, c in
            triangles.append(MeshTriangle(SIMD3<Double>(a) * scale, SIMD3<Double>(b) * scale, SIMD3<Double>(c) * scale))
        }
        let scaled = try CartridgeSTL(triangles: triangles)
        try scaled.data.write(to: destination, options: .atomic)
    }

    private static func float(in buffer: UnsafeRawBufferPointer, at offset: Int) -> Float {
        let bits = buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        return Float(bitPattern: UInt32(littleEndian: bits))
    }
}

private struct Incident {
    let face: Int
    let forward: Bool
    var isPaired = false
}

private struct MeshEdge: Hashable {
    let a: SIMD3<Float>
    let b: SIMD3<Float>

    static func precedes(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
        if a.x != b.x { return a.x < b.x }
        if a.y != b.y { return a.y < b.y }
        return a.z < b.z
    }
}

private extension Data {
    mutating func appendInteger<T: FixedWidthInteger>(_ value: T) {
        var bits = value.littleEndian
        Swift.withUnsafeBytes(of: &bits) { append(contentsOf: $0) }
    }

    mutating func appendVector(_ vector: SIMD3<Float>) {
        appendInteger(vector.x.bitPattern)
        appendInteger(vector.y.bitPattern)
        appendInteger(vector.z.bitPattern)
    }
}

private enum STLError: LocalizedError {
    case invalidModel, invalidScale, degenerate, openMesh

    var errorDescription: String? {
        switch self {
        case .invalidModel: "The cartridge must form one solid with outward-facing triangles."
        case .invalidScale: "Enter a valid coaster width before saving the model."
        case .degenerate: "Some model features are too small to keep distinct vertices at STL precision."
        case .openMesh: "The cartridge mesh has an open edge or inconsistent face orientation."
        }
    }
}
