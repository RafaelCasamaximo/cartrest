import Foundation

/// The entire configuration for one workspace, including its printable construction.
struct ConsoleProfile: Decodable, Identifiable, Sendable {
    static let supportedVersion = 1

    let schemaVersion: Int
    let id: String
    let name: String
    let order: Int
    let widthRange: WidthRange
    let palette: CartridgePalette
    let sampleArtwork: String?
    let artworkFilePrefix: String?
    let geometry: Geometry
    let instructions: [CartridgeInstruction]

    var modelFilePrefix: String { "cartrest-\(id)" }
    var exportPrefix: String { artworkFilePrefix ?? modelFilePrefix }

    struct WidthRange: Decodable, Sendable {
        let min: CGFloat
        let max: CGFloat

        func contains(_ width: CGFloat) -> Bool { min <= width && width <= max }
    }

    static func decode(_ data: Data) throws -> ConsoleProfile {
        struct Header: Decodable { let schemaVersion: Int }

        let decoder = JSONDecoder()
        do {
            let version = try decoder.decode(Header.self, from: data).schemaVersion
            guard version == Self.supportedVersion else { throw ProfileError.unsupportedVersion(version) }
            let profile = try decoder.decode(Self.self, from: data)
            try profile.validate()
            return profile
        } catch let error as DecodingError {
            let context: DecodingError.Context
            let path: [CodingKey]
            switch error {
            case .keyNotFound(let key, let details):
                context = details
                path = details.codingPath + [key]
            case .dataCorrupted(let details), .typeMismatch(_, let details), .valueNotFound(_, let details):
                context = details
                path = details.codingPath
            @unknown default:
                throw ProfileError.invalid("Check the JSON syntax and field types.")
            }
            let field = path.map(\.stringValue).joined(separator: ".")
            let location = field.isEmpty ? "JSON" : field
            throw ProfileError.invalid("\(location): \(context.debugDescription)")
        }
    }

    private func validate() throws {
        guard Self.isIdentifier(id), artworkFilePrefix.map(Self.isIdentifier) != false else {
            throw ProfileError.invalid("Use 1–64 lowercase letters, digits, or single hyphens for the ID and file prefix.")
        }
        guard !name.isEmpty, name.count <= 64, name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw ProfileError.invalid("Use a single-line console name of 1–64 characters.")
        }
        guard (10...500).contains(widthRange.min), (widthRange.min...500).contains(widthRange.max),
              widthRange.contains(geometry.body.width) else {
            throw ProfileError.invalid("The width range must be within 10–500 mm and include the nominal body width.")
        }
        if let sampleArtwork {
            guard !sampleArtwork.isEmpty, sampleArtwork.count <= 128, !sampleArtwork.hasPrefix("."),
                  !sampleArtwork.contains("/"), !sampleArtwork.contains("\\"),
                  sampleArtwork.rangeOfCharacter(from: .controlCharacters) == nil else {
                throw ProfileError.invalid("Use a bundled image filename for sampleArtwork.")
            }
        }
        try geometry.validateDimensions()
    }

    private static func isIdentifier(_ value: String) -> Bool {
        value.count <= 64 && value.wholeMatch(of: #/[a-z0-9]+(?:-[a-z0-9]+)*/#) != nil
    }
}

/// RGB tokens for the cutting mat and for the molded cartridge.
struct CartridgePalette: Decodable, Sendable {
    let mat: Mat
    let grid: UInt32
    let shell: Shell
    let plastic: UInt32
    let recess: UInt32

    struct Mat: Decodable, Sendable {
        let highlight: UInt32
        let center: UInt32
        let shadow: UInt32
        let direction: Direction
        let gridOpacity: Double

        enum Direction: String, Decodable, Sendable {
            case diagonal, reverseDiagonal, horizontal, vertical
        }

        private enum CodingKeys: CodingKey { case highlight, center, shadow, tint, direction, gridOpacity }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let tint = try values.decodeIfPresent(Tint.self, forKey: .tint)
            func stop(_ key: CodingKeys) throws -> UInt32 {
                let color = try values.rgb(for: key)
                return tint?.apply(to: color) ?? color
            }
            highlight = try stop(.highlight)
            center = try stop(.center)
            shadow = try stop(.shadow)
            direction = try values.decodeIfPresent(Direction.self, forKey: .direction) ?? .diagonal
            gridOpacity = try values.fraction(for: .gridOpacity, default: 1)
        }
    }

    private struct Tint: Decodable, Sendable {
        let color: UInt32
        let strength: Double

        private enum CodingKeys: CodingKey { case color, strength }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            color = try values.rgb(for: .color)
            strength = try values.fraction(for: .strength)
        }

        /// Mix the tint into each sRGB stop before interpolating the mat gradient.
        func apply(to base: UInt32) -> UInt32 {
            func channel(at shift: UInt32) -> UInt32 {
                let original = Double((base >> shift) & 255)
                let tinted = Double((color >> shift) & 255)
                return UInt32((original + (tinted - original) * strength).rounded()) << shift
            }
            return channel(at: 16) | channel(at: 8) | channel(at: 0)
        }
    }

    struct Shell: Decodable, Sendable {
        let highlight: UInt32
        let shadow: UInt32

        private enum CodingKeys: CodingKey { case highlight, shadow }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            highlight = try values.rgb(for: .highlight)
            shadow = try values.rgb(for: .shadow)
        }
    }

    private enum CodingKeys: CodingKey { case mat, grid, shell, plastic, recess }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mat = try values.decode(Mat.self, forKey: .mat)
        grid = try values.rgb(for: .grid)
        shell = try values.decode(Shell.self, forKey: .shell)
        plastic = try values.rgb(for: .plastic)
        recess = try values.rgb(for: .recess)
    }
}

private extension KeyedDecodingContainer {
    func fraction(for key: Key, default fallback: Double? = nil) throws -> Double {
        let value: Double
        if let fallback {
            value = try decodeIfPresent(Double.self, forKey: key) ?? fallback
        } else {
            value = try decode(Double.self, forKey: key)
        }
        guard (0...1).contains(value) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Use a number from 0 to 1.")
        }
        return value
    }

    func rgb(for key: Key) throws -> UInt32 {
        let text = try decode(String.self, forKey: key)
        guard text.wholeMatch(of: #/#[0-9a-fA-F]{6}/#) != nil,
              let value = UInt32(text.dropFirst(), radix: 16) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Use an RGB color such as #1E4738.")
        }
        return value
    }
}

enum CartridgeInstruction: Decodable, Sendable {
    case extrudeBody
    case recessLabel
    case engraveArrow
    case recessGrip
    case rearChannels(Channels)
    case rearSlot(Slot)
    case rearRecess(Geometry.Recess)

    private enum Operation: String, Decodable {
        case extrudeBody, recessLabel, engraveArrow, recessGrip, rearChannels, rearSlot, rearRecess
    }

    private enum CodingKeys: CodingKey { case op }

    struct Channels: Decodable, Sendable {
        let x: Double
        let y: Double
        let count: Int
        let width: Double
        let pitch: Double
        let depth: Double
    }

    struct Slot: Decodable, Sendable {
        let x: Double
        let y: Double
        let width: Double
        let radius: Double
        let depth: Double
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Operation.self, forKey: .op) {
        case .extrudeBody: self = .extrudeBody
        case .recessLabel: self = .recessLabel
        case .engraveArrow: self = .engraveArrow
        case .recessGrip: self = .recessGrip
        case .rearChannels: self = .rearChannels(try Channels(from: decoder))
        case .rearSlot: self = .rearSlot(try Slot(from: decoder))
        case .rearRecess: self = .rearRecess(try Geometry.Recess(from: decoder))
        }
    }
}

enum ProfileError: LocalizedError {
    case unsupportedVersion(Int)
    case invalid(String)
    case duplicate(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "Profile version \(version) is unavailable. Use schemaVersion 1."
        case .invalid(let reason): reason
        case .duplicate(let id): "A profile with the ID “\(id)” already exists. Choose a unique ID for this variation."
        }
    }
}
