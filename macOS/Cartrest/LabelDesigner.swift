import Accessibility
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LabelDesigner: View {
    let catalog: LabelDesignCatalog
    let profile: ConsoleProfile
    let geometry: Geometry
    let label: Geometry.Label
    let bleed: CGFloat
    let dpi: Int
    let canAddToSheet: Bool
    let addArtwork: (SheetArtwork) -> Void

    @Binding var draft: LabelDraft
    @Binding var workspace: EditorWorkspace
    @Binding var section: Section
    @Binding var isWorking: Bool
    @Environment(\.colorScheme) private var colorScheme
    @ViewState private var activeMark: LabelMarkRole = .rating
    @ViewState private var importTarget: ImportTarget = .background
    @ViewState private var showsImporter = false
    @ViewState private var showsExporter = false
    @ViewState private var pngDocument: PNGDocument?
    @ViewState private var errorMessage: String?

    enum Section: String, CaseIterable, Identifiable {
        case artwork = "Artwork"
        case effects = "Effects"
        case layout = "Header & Code"
        case marks = "Marks"

        var id: Self { self }
    }

    private enum ImportTarget {
        case background, header, mark(LabelMarkRole)
    }

    private var theme: CartrestTheme { CartrestTheme(colorScheme: colorScheme) }
    private var template: LabelTemplate? { catalog.template(draft.templateID) }

    var body: some View {
        HSplitView {
            preview
                .frame(minWidth: 470, idealWidth: 820, maxWidth: .infinity, maxHeight: .infinity)
            inspector
                .frame(minWidth: 320, idealWidth: 342, maxWidth: 420, maxHeight: .infinity)
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.image], onCompletion: importImage)
        .fileExporter(isPresented: $showsExporter, document: pngDocument, contentType: .png,
                      defaultFilename: pngDocument?.name ?? draft.outputName) { result in
            pngDocument = nil
            switch result {
            case .success:
                AccessibilityNotification.Announcement("Label PNG saved.").post()
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("Label Designer", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var preview: some View {
        let image = try? LabelDesignRenderer.render(draft, catalog: catalog, label: label,
                                                    bleed: bleed, dpi: dpi, previewLimit: 760)
        let options = image.map {
            ArtworkOptions(image: $0, widthMM: label.width, heightMM: label.height,
                           radiusMM: label.radius, chamferMM: label.chamfer, bleedMM: bleed,
                           dpi: dpi, zoom: 1, x: 0, y: 0, copies: 1)
        }
        return ZStack(alignment: .bottom) {
            PreviewCanvas(mode: .cut, geometry: geometry, palette: profile.palette, label: label,
                          artwork: options, artworks: [], placements: [], page: 1, pageCount: 0,
                          bottomInset: MeasurementDisplay.previewBottomInset)
            MeasurementDisplay(readings: [
                .init(name: "Sticker cut", value: "\(decimal(label.width)) × \(decimal(label.height)) mm"),
                .init(name: "Bleed", value: "\(decimal(bleed)) mm"),
            ])
            .padding(.horizontal, 16)
            .padding(.bottom, MeasurementDisplay.bottomMargin)
            .allowsHitTesting(false)
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkspacePicker(selection: $workspace).disabled(isWorking)
            Divider()
            Picker("Designer section", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch section {
                    case .artwork: artworkControls
                    case .effects: effectsControls
                    case .layout: layoutControls
                    case .marks: markControls
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            exportControls
        }
        .background(theme.inspectorBackground)
    }

    private var exportControls: some View {
        HStack(spacing: 10) {
            Button("Save PNG…", systemImage: "arrow.down.to.line") { finish(addToSheet: false) }
                .disabled(isWorking)
            Button("Add to Sheet", systemImage: "plus") { finish(addToSheet: true) }
                .buttonStyle(.borderedProminent)
                .tint(theme.buttonTint)
                .disabled(isWorking || !canAddToSheet)
                .help(canAddToSheet ? "Use this design as sticker artwork" : "The current sheet has reached its sticker limit")
            Spacer(minLength: 0)
            if isWorking { ProgressView().controlSize(.small).accessibilityLabel("Working with label artwork") }
        }
        .controlSize(.large)
        .padding(16)
        .background(theme.footerBackground)
    }

    private var effectsControls: some View {
        VStack(alignment: .leading, spacing: 20) {
            controlGroup("Noise") {
                valueSlider("Noise amount", value: $draft.effects.noiseAmount, range: 0...1, step: 0.01,
                             readout: percent(draft.effects.noiseAmount))
                valueSlider("Grain size", value: $draft.effects.grainSize, range: 0.15...1.2, step: 0.05,
                             readout: "\(decimal(draft.effects.grainSize)) mm")
                    .disabled(draft.effects.noiseAmount == 0)
            }

            controlGroup("Halftone") {
                valueSlider("Halftone amount", value: $draft.effects.halftoneAmount, range: 0...1, step: 0.01,
                             readout: percent(draft.effects.halftoneAmount))
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Screen", selection: $draft.effects.screen) {
                        ForEach(LabelHalftoneScreen.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    valueSlider("Dot spacing", value: $draft.effects.dotSpacing, range: 0.35...4, step: 0.05,
                                 readout: "\(decimal(draft.effects.dotSpacing)) mm")
                    valueSlider("Screen angle", value: $draft.effects.angle, range: 0...90, step: 1,
                                 readout: "\(Int(draft.effects.angle))°")
                }
                .disabled(draft.effects.halftoneAmount == 0)
            }

            Button("Reset effects") { draft.effects = LabelArtworkEffects() }
        }
    }

    private func valueSlider(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, readout: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                Text(readout).monospacedDigit().foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: value, in: range, step: step) { Text(title) }
                .labelsHidden()
                .accessibilityValue(readout)
        }
    }

    @ViewBuilder
    private var artworkControls: some View {
        controlGroup("Background") {
            ColorPicker("Backing color", selection: colorBinding($draft.backgroundColor), supportsOpacity: false)
            importButton(draft.background, title: "Import background…", replacement: "Replace background…",
                         clear: { draft.background = nil }, target: .background)
            if draft.background != nil {
                Picker("Image fit", selection: $draft.imageMode) {
                    ForEach(LabelImageMode.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                Slider(value: $draft.zoom, in: 1...3.5) { Text("Zoom") }
                Slider(value: $draft.panX, in: -1...1) { Text("Horizontal") }
                Slider(value: $draft.panY, in: -1...1) { Text("Vertical") }
                Button("Reset framing") {
                    draft.zoom = 1
                    draft.panX = 0
                    draft.panY = 0
                }
            }
        }

        controlGroup("Text") {
            TextField("Label title", text: $draft.title, prompt: Text("Optional"))
                .onChange(of: draft.title) { _, title in
                    if title.count > 120 { draft.title = String(title.prefix(120)) }
                }
            if !draft.title.isEmpty {
                ColorPicker("Title color", selection: colorBinding($draft.titleColor), supportsOpacity: false)
                Slider(value: $draft.titleScale, in: 0.5...1.5) { Text("Title size") }
                Slider(value: $draft.titlePosition, in: 0.15...0.85) { Text("Title position") }
            }
            TextField("Artwork name", text: $draft.name, prompt: Text("Automatic"))
        }
    }

    @ViewBuilder
    private var layoutControls: some View {
        controlGroup("Template") {
            Picker("Label layout", selection: Binding(
                get: { draft.templateID },
                set: { if let template = catalog.template($0) { draft.apply(template) } }
            )) {
                ForEach(catalog.templates) { Text($0.name).tag($0.id) }
            }
        }

        controlGroup("Header") {
            Picker("Header style", selection: $draft.headerStyle) {
                ForEach(LabelHeaderStyle.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            if draft.headerStyle != .hidden {
                ColorPicker("Band color", selection: colorBinding($draft.headerColor), supportsOpacity: false)
                valueSlider("Band height", value: $draft.headerHeightScale, range: 0.75...1.25, step: 0.01,
                             readout: percent(draft.headerHeightScale))
                Slider(value: $draft.headerScale, in: 0.55...1.28) { Text("Logo size") }
            }
            importButton(draft.headerLogo, title: "Import header logo…", replacement: "Replace header logo…",
                         clear: { draft.headerLogo = nil }, target: .header)
        }

        controlGroup("Cartridge code") {
            TextField("Cartridge code", text: $draft.code, prompt: Text(template?.codeExample ?? "Product code"))
                .font(.system(.body, design: .monospaced))
                .onChange(of: draft.code) { _, value in
                    if value.count > 36 { draft.code = String(value.prefix(36)) }
                }
            if !draft.code.isEmpty {
                Picker("Code alignment", selection: $draft.codeAlignment) {
                    ForEach(LabelCodeAlignment.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                ColorPicker("Footer color", selection: colorBinding($draft.footerColor), supportsOpacity: false)
                ColorPicker("Code color", selection: colorBinding($draft.codeColor), supportsOpacity: false)
                Slider(value: $draft.codeScale, in: 0.6...1.4) { Text("Code size") }
            }
        }
    }

    private var markControls: some View {
        let placement = markBinding(activeMark)
        let asset = placement.wrappedValue
        let choices = markChoices(activeMark)
        let selected = choices.first { $0.id == asset.assetID }

        return VStack(alignment: .leading, spacing: 20) {
            Picker("Mark to edit", selection: $activeMark) {
                ForEach(LabelMarkRole.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Mark to edit")

            controlGroup(activeMark.name) {
                if activeMark == .rating {
                    Picker("Rating system", selection: Binding(
                        get: { draft.ratingSystemID },
                        set: {
                            draft.ratingSystemID = $0
                            draft.marks[.rating]?.assetID = nil
                            draft.marks[.rating]?.custom = nil
                        }
                    )) {
                        Text("None").tag("")
                        ForEach(catalog.ratingSystems) { Text($0.name).tag($0.id) }
                    }
                }

                if !choices.isEmpty {
                    Picker(activeMark == .rating ? "Age mark" : "Logo", selection: Binding(
                        get: { placement.wrappedValue.assetID ?? "" },
                        set: { choice in
                            placement.wrappedValue.assetID = choice.isEmpty ? nil : choice
                            placement.wrappedValue.custom = nil
                        }
                    )) {
                        Text("None").tag("")
                        ForEach(choices) { Text($0.name).tag($0.id) }
                    }
                }

                if let selected, let image = catalog.image(selected.id) {
                    HStack(spacing: 10) {
                        Image(decorative: image, scale: 1)
                            .resizable().scaledToFit().frame(width: 48, height: 36)
                            .padding(5)
                            .background(.white, in: RoundedRectangle(cornerRadius: 5))
                        Text(selected.name).font(.subheadline)
                        Spacer(minLength: 0)
                    }
                }

                importButton(asset.custom, title: "Import mark…", replacement: "Replace imported mark…",
                             clear: { placement.wrappedValue.custom = nil }, target: .mark(activeMark))
            }

            if asset.isVisible {
                controlGroup("Placement") {
                    Slider(value: placement.x, in: 0.08...0.92) { Text("Horizontal") }
                    Slider(value: placement.y, in: 0.14...0.91) { Text("Vertical") }
                    Slider(value: placement.scale, in: 0.55...1.45) { Text("Size") }
                    Picker("Backing", selection: placement.backing) {
                        ForEach(LabelMarkBacking.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private func markChoices(_ role: LabelMarkRole) -> [LabelMark] {
        switch role {
        case .rating: catalog.ratingSystems.first { $0.id == draft.ratingSystemID }?.marks ?? []
        case .publisher, .studio: catalog.companies
        case .seal: catalog.seals
        }
    }

    private func markBinding(_ role: LabelMarkRole) -> Binding<LabelMarkPlacement> {
        Binding(
            get: { draft.marks[role] ?? LabelMarkPlacement(x: 0.5, y: 0.75) },
            set: { draft.marks[role] = $0 }
        )
    }

    private func controlGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func importButton(
        _ image: SheetArtwork?, title: String, replacement: String, clear: @escaping () -> Void, target: ImportTarget
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image {
                HStack(spacing: 6) {
                    Text(image.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Button("Clear", action: clear).controlSize(.small)
                        .accessibilityLabel("Remove imported image")
                }
            }
            Button(image == nil ? title : replacement, systemImage: "photo") {
                importTarget = target
                showsImporter = true
            }
            .disabled(isWorking)
        }
    }

    private func decimal(_ value: CGFloat) -> String {
        Double(value).formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
    }

    private func colorBinding(_ value: Binding<UInt32>) -> Binding<Color> {
        Binding(
            get: { Color(cartrestHex: value.wrappedValue) },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                func channel(_ x: CGFloat) -> UInt32 {
                    UInt32((min(1, max(0, x)) * 255).rounded())
                }
                value.wrappedValue = channel(rgb.redComponent) << 16 | channel(rgb.greenComponent) << 8
                    | channel(rgb.blueComponent)
            }
        )
    }

    private func importImage(_ result: Result<URL, Error>) {
        guard !isWorking else { return }
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            let target = importTarget
            isWorking = true
            Task {
                defer { isWorking = false }
                do {
                    let artwork = try await Task.detached(priority: .userInitiated) {
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        return try SheetArtwork.load(url)
                    }.value
                    switch target {
                    case .background:
                        draft.background = artwork
                        draft.zoom = 1
                        draft.panX = 0
                        draft.panY = 0
                    case .header:
                        draft.headerLogo = artwork
                        if draft.headerStyle == .hidden { draft.headerStyle = .flat }
                    case .mark(let role):
                        draft.marks[role]?.custom = artwork
                        draft.marks[role]?.assetID = nil
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func finish(addToSheet: Bool) {
        guard !isWorking else { return }
        isWorking = true
        let current = draft
        let catalog = catalog
        let label = label
        let bleed = bleed
        let dpi = dpi

        Task {
            defer { isWorking = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try LabelDesignRenderer.render(current, catalog: catalog, label: label, bleed: bleed, dpi: dpi)
                }.value
                if addToSheet {
                    addArtwork(SheetArtwork(name: current.outputName, image: result))
                } else {
                    let data = try await Task.detached(priority: .userInitiated) {
                        try ArtworkExporter.png(result, dpi: dpi)
                    }.value
                    pngDocument = PNGDocument(data: data, name: current.outputName)
                    showsExporter = true
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct PNGDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.png]

    let data: Data
    let name: String

    init(data: Data, name: String) {
        self.data = data
        self.name = name
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = contents
        name = "Cartridge Label"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
