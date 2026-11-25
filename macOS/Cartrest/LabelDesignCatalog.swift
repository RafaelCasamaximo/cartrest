import CoreGraphics
import Foundation
import ImageIO

/// The catalog pairs artwork assets with their sources and the layouts that use them.
struct LabelDesignCatalog: Sendable {
    let templates: [LabelTemplate]
    let ratingSystems: [LabelRatingSystem]
    let companies: [LabelMark]
    let seals: [LabelMark]
    private let images: [String: CGImage]
    private let headerLayouts: [String: LabelHeaderLayout]

    private struct Contents: Decodable {
        let schemaVersion: Int
        let templates: [LabelTemplate]
        let headers: [LabelMark]
        let headerLayouts: [String: LabelHeaderLayout]?
        let ratingSystems: [LabelRatingSystem]
        let companies: [LabelMark]
        let seals: [LabelMark]
    }

    static let bundled = Result { try load(from: .main) }

    func template(_ id: String) -> LabelTemplate? {
        templates.first { $0.id == id }
    }

    func image(_ id: String) -> CGImage? { images[id] }

    func headerLayout(for template: LabelTemplate) -> LabelHeaderLayout? {
        template.headerLayout.flatMap { headerLayouts[$0] }
    }

    private static func load(from bundle: Bundle) throws -> Self {
        guard let directory = bundle.resourceURL?.appending(path: "LabelDesigner", directoryHint: .isDirectory) else {
            throw LabelDesignError.catalog("The label designer resources are missing.")
        }
        let url = directory.appending(path: "catalog.json")
        let contents = try JSONDecoder().decode(Contents.self, from: Data(contentsOf: url))
        guard contents.schemaVersion == 1, contents.templates.contains(where: { $0.id == "custom" }),
              Set(contents.templates.map(\.id)).count == contents.templates.count,
              Set(contents.ratingSystems.map(\.id)).count == contents.ratingSystems.count else {
            throw LabelDesignError.catalog("The label designer catalog has invalid definitions.")
        }

        let marks = contents.headers + contents.ratingSystems.flatMap(\.marks) + contents.companies + contents.seals
        let assets = directory.appending(path: "Assets", directoryHint: .isDirectory)
        var images: [String: CGImage] = [:]
        for mark in marks {
            guard images[mark.id] == nil,
                  mark.file.wholeMatch(of: #/[a-z0-9]+(?:-[a-z0-9]+)*\.png/#) != nil,
                  let file = CGImageSourceCreateWithURL(assets.appending(path: mark.file) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(file, 0, nil) else {
                throw LabelDesignError.catalog("The artwork for \(mark.name) could not be loaded.")
            }
            images[mark.id] = image
        }

        let headerIDs = Set(contents.headers.map(\.id))
        let headerLayouts = contents.headerLayouts ?? [:]
        guard headerLayouts.values.allSatisfy(\.isValid) else {
            throw LabelDesignError.catalog("The label designer catalog contains an invalid header layout.")
        }
        for template in contents.templates {
            guard (0...0.35).contains(template.headerHeight), (0...0.2).contains(template.footerHeight),
                  (0.30...0.90).contains(template.markRow),
                  template.header.map(headerIDs.contains) != false,
                  template.headerOnDark.map(headerIDs.contains) != false,
                  template.headerLayout.map({ headerLayouts[$0] != nil }) != false,
                  [template.headerColor, template.footerColor, template.codeColor].allSatisfy({
                      $0.wholeMatch(of: #/#[0-9a-fA-F]{6}/#) != nil
                  }) else {
                throw LabelDesignError.catalog("The \(template.name) label template is invalid.")
            }
        }
        return Self(templates: contents.templates, ratingSystems: contents.ratingSystems,
                    companies: contents.companies, seals: contents.seals, images: images, headerLayouts: headerLayouts)
    }
}

struct LabelTemplate: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let header: String?
    let headerOnDark: String?
    let headerStyle: LabelHeaderStyle
    /// Bands are fractions of the cut height. Their backgrounds also cover the adjoining bleed.
    let headerHeight: CGFloat
    let headerColor: String
    let headerLayout: String?
    let footerHeight: CGFloat
    let footerColor: String
    let codeColor: String
    let codeAlignment: LabelCodeAlignment?
    let codeTypeface: LabelCodeTypeface?
    let codeExample: String
    let markRow: Double
}

struct LabelHeaderLayout: Decodable, Sendable {
    struct Point: Decodable, Sendable {
        let x: CGFloat
        let y: CGFloat

        var isInUnitRect: Bool { (0...1).contains(x) && (0...1).contains(y) }
    }

    struct Segment: Decodable, Sendable {
        let end: Point
        /// Two controls give a cubic segment. Omitting them gives a line.
        let controls: [Point]?
    }

    // All coordinates are relative to the trim width and the maximum band height.
    let logoCenter: Point
    let logoWidth: CGFloat
    let logoHeight: CGFloat
    let seam: [Segment]?

    var isValid: Bool {
        guard logoCenter.isInUnitRect, (0.01...1).contains(logoWidth), (0.01...1).contains(logoHeight) else {
            return false
        }
        guard let seam else { return true }
        guard let first = seam.first, first.end.x == 0, first.end.isInUnitRect, first.controls == nil,
              seam.last?.end.x == 1, seam.count <= 24 else { return false }
        var previousX = first.end.x
        for segment in seam.dropFirst() {
            guard segment.end.isInUnitRect, segment.end.x > previousX else { return false }
            if let controls = segment.controls {
                let range = previousX...segment.end.x
                guard controls.count == 2, controls[0].x <= controls[1].x,
                      controls.allSatisfy({ $0.isInUnitRect && range.contains($0.x) }) else { return false }
            }
            previousX = segment.end.x
        }
        return true
    }
}

struct LabelRatingSystem: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let marks: [LabelMark]
}

struct LabelMark: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let file: String
    let source: String
}

enum LabelHeaderStyle: String, CaseIterable, Decodable, Identifiable, Sendable {
    case shadow, flat, hidden

    var id: Self { self }
    var name: String {
        switch self {
        case .shadow: "Shadow"
        case .flat: "Flat"
        case .hidden: "Hidden"
        }
    }
}

enum LabelImageMode: String, CaseIterable, Identifiable, Sendable {
    case fill, fit

    var id: Self { self }
    var name: String { rawValue.capitalized }
}

enum LabelCodeAlignment: String, CaseIterable, Decodable, Identifiable, Sendable {
    case left, center, right

    var id: Self { self }
    var name: String { rawValue.capitalized }

    var position: CGFloat {
        switch self {
        case .left: 0
        case .center: 0.5
        case .right: 1
        }
    }
}

enum LabelCodeTypeface: String, Decodable, Sendable {
    case ocrB = "ocr-b"
    case monospaced
}

enum LabelMarkRole: String, CaseIterable, Identifiable, Sendable {
    case rating, publisher, studio, seal

    var id: Self { self }
    var name: String { rawValue.capitalized }

    fileprivate var defaultX: Double {
        switch self {
        case .rating: 0.18
        case .publisher: 0.45
        case .studio: 0.65
        case .seal: 0.83
        }
    }
}

enum LabelMarkBacking: String, CaseIterable, Identifiable, Sendable {
    case none, light, dark

    var id: Self { self }
    var name: String { rawValue.capitalized }
}

struct LabelMarkPlacement: Sendable {
    var assetID: String?
    var custom: SheetArtwork?
    var x: Double
    var y: Double
    var scale: Double = 1
    var backing: LabelMarkBacking = .none

    var isVisible: Bool { custom != nil || assetID != nil }
}

/// A draft belongs to one console editor. The sheet receives a flattened image,
/// while the draft remains editable when its designer is reopened.
struct LabelDraft: Sendable {
    var templateID: String
    var name = ""
    var title = ""
    var titleColor: UInt32 = 0xffffff
    var titlePosition = 0.49
    var titleScale = 1.0

    var background: SheetArtwork?
    var backgroundColor: UInt32 = 0x294139
    var imageMode: LabelImageMode = .fill
    var zoom: CGFloat = 1
    var panX: CGFloat = 0
    var panY: CGFloat = 0
    var effects = LabelArtworkEffects()

    var headerStyle: LabelHeaderStyle
    var headerColor: UInt32
    var headerLogo: SheetArtwork?
    var headerScale = 1.0
    var headerHeightScale = 1.0

    var code = ""
    var codeColor: UInt32
    var codeAlignment: LabelCodeAlignment
    var footerColor: UInt32
    var codeScale = 1.0

    var ratingSystemID = ""
    var marks: [LabelMarkRole: LabelMarkPlacement]

    init(template: LabelTemplate) {
        templateID = template.id
        headerStyle = template.headerStyle
        headerColor = Self.color(template.headerColor)
        footerColor = Self.color(template.footerColor)
        codeColor = Self.color(template.codeColor)
        codeAlignment = template.codeAlignment ?? .center
        marks = Dictionary(uniqueKeysWithValues: LabelMarkRole.allCases.map {
            ($0, LabelMarkPlacement(x: $0.defaultX, y: template.markRow))
        })
    }

    mutating func apply(_ template: LabelTemplate) {
        templateID = template.id
        headerStyle = template.headerStyle
        headerColor = Self.color(template.headerColor)
        footerColor = Self.color(template.footerColor)
        codeColor = Self.color(template.codeColor)
        codeAlignment = template.codeAlignment ?? .center
        headerScale = 1
        headerHeightScale = 1
        headerLogo = nil
        for role in LabelMarkRole.allCases {
            marks[role]?.y = template.markRow
        }
    }

    var outputName: String {
        let candidates = [name, title, background?.name ?? ""]
        return candidates.lazy.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Cartridge Label"
    }

    private static func color(_ value: String) -> UInt32 {
        UInt32(value.dropFirst(), radix: 16) ?? 0
    }
}

enum LabelDesignError: LocalizedError {
    case catalog(String)
    case canvas
    case effects
    case missingTemplate

    var errorDescription: String? {
        switch self {
        case .catalog(let reason): reason
        case .canvas: "The label is too large to render at this resolution. Reduce its size or resolution."
        case .effects: "The artwork effects could not be rendered."
        case .missingTemplate: "This label template is unavailable."
        }
    }
}
