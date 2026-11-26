import Accessibility
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// This alias keeps the property wrapper available on SDKs with a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

enum PreviewMode: String {
    case coaster, cut, sheet, threeD
}

enum EditorWorkspace: String, CaseIterable, Identifiable {
    case sheet = "Coaster & Sheet"
    case designer = "Label Designer"

    var id: Self { self }
}

struct WorkspacePicker: View {
    @Binding var selection: EditorWorkspace

    var body: some View {
        Picker("Workspace", selection: $selection) {
            ForEach(EditorWorkspace.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .accessibilityLabel("Workspace")
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
    }
}

private enum ExportFormat: Sendable {
    case pdf, png

    var contentType: UTType { self == .pdf ? .pdf : .png }
}

private enum EditorOperation {
    case importing, exporting
}

/// One snapshot of the window controls. The preview, footer, and export use
/// the same geometry and pagination for each update.
private struct SheetPreparation {
    let geometry: Geometry
    let label: Geometry.Label
    let errorMessage: String?
    let artworks: [ArtworkOptions]
    let pages: [[SheetPlacement]]
    let editingArtwork: SheetArtwork?
    let selectedOptions: ArtworkOptions?
    let metrics: ArtworkMetrics?

    func canSave(_ format: ExportFormat) -> Bool {
        guard metrics?.canRasterize == true else { return false }
        return format == .png || !pages.isEmpty
    }
}

struct CartrestEditor: View {
    let model: ConsoleModel
    let isActive: Bool
    @Binding var workspace: EditorWorkspace
    @Binding var designerBusy: Bool
    @Environment(\.colorScheme) private var colorScheme
    @ViewState private var artworks: [SheetArtwork]
    @ViewState private var selection: UUID?
    @ViewState private var mode: PreviewMode = .coaster
    @ViewState private var page = 0
    @ViewState private var cameraRevision = 0
    @ViewState private var usesCustomRecess = false
    @ViewState private var showsModelDimensions = true
    @ViewState private var showsHolder = false
    @ViewState private var holderSlotCount = CoasterHolder.defaultSlots
    @ViewState private var holderClearance = CGFloat(CoasterHolder.defaultClearance)
    @ViewState private var coasterWidth: CGFloat
    @ViewState private var customWidth: CGFloat
    @ViewState private var customHeight: CGFloat
    @ViewState private var customRadius: CGFloat
    @ViewState private var customChamfer: CGFloat = 0
    @ViewState private var bleed: CGFloat = 2
    @ViewState private var dpi = 300
    @ViewState private var operation: EditorOperation?
    @ViewState private var status = ""
    @ViewState private var errorMessage: String?
    @ViewState private var labelDraft: LabelDraft?
    @ViewState private var labelSection: LabelDesigner.Section = .artwork

    private var console: ConsoleProfile { model.profile }
    private var baseGeometry: Geometry { console.geometry }
    private var theme: CartrestTheme { CartrestTheme(colorScheme: colorScheme) }
    private var onlySampleArtwork: Bool { artworks.count == 1 && artworks.first?.isSample == true }
    private var isImporting: Bool { operation == .importing }
    private var hasValidCoasterWidth: Bool { console.widthRange.contains(coasterWidth) }

    init(model: ConsoleModel, isActive: Bool, workspace: Binding<EditorWorkspace>, designerBusy: Binding<Bool>) {
        self.model = model
        self.isActive = isActive
        _workspace = workspace
        _designerBusy = designerBusy
        let geometry = model.profile.geometry
        let sample = model.sample
        _artworks = ViewState(initialValue: sample.map { [$0] } ?? [])
        _selection = ViewState(initialValue: sample?.id)
        _coasterWidth = ViewState(initialValue: geometry.body.width)
        _customWidth = ViewState(initialValue: geometry.label.width)
        _customHeight = ViewState(initialValue: geometry.label.height)
        _customRadius = ViewState(initialValue: geometry.label.radius)
    }

    private var validationError: String? {
        if !usesCustomRecess && !hasValidCoasterWidth {
            let range = console.widthRange
            return "Enter a coaster width between \(decimal(range.min)) and \(decimal(range.max)) mm."
        }
        if usesCustomRecess {
            let shortSide = min(customWidth, customHeight)
            if !(20...160).contains(customWidth) || !(20...160).contains(customHeight) {
                return "Enter a width and height between 20 and 160 mm."
            }
            if !(0...(shortSide / 2)).contains(customRadius) || !(0...(shortSide - customRadius)).contains(customChamfer) {
                return "Reduce the radius or chamfer to fit the outline."
            }
        }
        if !(0...5).contains(bleed) {
            return "Enter a bleed between 0 and 5 mm."
        }
        return nil
    }

    private var totalCopies: Int {
        artworks.reduce(0) { $0 + $1.copies }
    }

    private var sheetPreparation: SheetPreparation {
        let geometry = hasValidCoasterWidth ? baseGeometry.scaled(toWidth: coasterWidth) : baseGeometry
        let label = usesCustomRecess
            ? Geometry.Label(width: customWidth, height: customHeight,
                                radius: customRadius, chamfer: customChamfer)
            : geometry.label
        let errorMessage = validationError
        let options = errorMessage == nil ? artworks.map { artwork in
            ArtworkOptions(image: artwork.image, widthMM: label.width, heightMM: label.height,
                       radiusMM: label.radius, chamferMM: label.chamfer, bleedMM: bleed,
                       dpi: dpi, zoom: artwork.zoom, x: artwork.x, y: artwork.y, copies: artwork.copies)
        } : []
        let selectedIndex = artworks.firstIndex { $0.id == selection }
        let selected = selectedIndex.flatMap { index in
            options.indices.contains(index) ? options[index] : nil
        }

        return SheetPreparation(
            geometry: geometry, label: label, errorMessage: errorMessage, artworks: options,
            pages: ArtworkExporter.layout(options), editingArtwork: selectedIndex.map { artworks[$0] },
            selectedOptions: selected,
            metrics: selected.map(ArtworkExporter.measure)
        )
    }

    var body: some View {
        if isActive { editor }
    }

    private var editor: some View {
        let preparation = sheetPreparation
        return Group {
            switch workspace {
            case .sheet:
                HSplitView {
                    preview(preparation)
                        .frame(minWidth: 470, idealWidth: 820, maxWidth: .infinity, maxHeight: .infinity)
                    inspector(preparation)
                        .frame(minWidth: 320, idealWidth: 342, maxWidth: 420, maxHeight: .infinity)
                }
            case .designer:
                labelDesigner(preparation)
            }
        }
        .frame(minWidth: 800, minHeight: 610)
        .background(theme.windowBackground)
        .tint(theme.accentText)
        .onChange(of: usesCustomRecess) { _, newValue in
            if newValue && (mode == .coaster || mode == .threeD) { mode = .cut }
        }
        .onChange(of: preparation.pages.count) { _, count in
            page = min(page, max(0, count - 1))
        }
        .alert("Cartrest", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Preview

    private func preview(_ preparation: SheetPreparation) -> some View {
        let pages = preparation.pages
        let visiblePage = visiblePageIndex(pages)
        let previewMode = usesCustomRecess && (mode == .coaster || mode == .threeD) ? .cut : mode
        return ZStack(alignment: .bottom) {
            PreviewCanvas(
                mode: previewMode,
                geometry: preparation.geometry,
                palette: console.palette,
                label: preparation.label, artwork: preparation.selectedOptions,
                artworks: preparation.artworks, placements: pages.indices.contains(visiblePage) ? pages[visiblePage] : [],
                page: visiblePage + 1, pageCount: pages.count,
                bottomInset: MeasurementDisplay.previewBottomInset
            )
            .accessibilityHidden(previewMode == .threeD)

            if previewMode == .threeD {
                Cartridge3D(
                    model: model,
                    geometry: preparation.geometry,
                    artwork: preparation.selectedOptions
                )
                // Recenter recreates the camera while this preview is open.
                .id(cameraRevision)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, MeasurementDisplay.previewBottomInset)
            }

            MeasurementDisplay(readings: measurementReadings(preparation))
                .padding(.horizontal, 20)
                .padding(.bottom, MeasurementDisplay.bottomMargin)
                .allowsHitTesting(false)
        }
    }

    private func measurementReadings(_ preparation: SheetPreparation) -> [MeasurementDisplay.Reading] {
        let body = preparation.geometry.body
        let label = preparation.label
        let isValid = preparation.errorMessage == nil
        var readings: [MeasurementDisplay.Reading] = []
        if !usesCustomRecess {
            readings.append(.init(name: "Coaster", value: isValid ? formattedSize(body.width, body.height) : "—"))
        }
        readings.append(.init(name: "Sticker cut", value: isValid ? formattedSize(label.width, label.height) : "—"))
        let artworkSize = preparation.metrics.map { formattedSize($0.artworkWidthMM, $0.artworkHeightMM) } ?? "—"
        readings.append(.init(name: "Artwork with bleed", value: artworkSize))
        return readings
    }

    private func visiblePageIndex(_ pages: [[SheetPlacement]]) -> Int {
        // Clamp the index even during the update that reduces the page count.
        min(page, max(0, pages.count - 1))
    }

    // MARK: - Inspector

    private func inspector(_ preparation: SheetPreparation) -> some View {
        VStack(spacing: 0) {
            WorkspacePicker(selection: $workspace).disabled(operation != nil)
            inspectorDivider
            inspectorHeader(preparation.pages)
            inspectorDivider
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    artworkList(preparation)
                    if let selected = preparation.editingArtwork {
                        inspectorDivider
                        framingControls(selected, preparation: preparation)
                    }
                    inspectorDivider
                    printSettings(preparation)
                }
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            inspectorDivider
            exportControls(preparation)
                .padding(16)
                .background(theme.footerBackground)
        }
        .background(theme.inspectorBackground)
    }

    private func inspectorHeader(_ pages: [[SheetPlacement]]) -> some View {
        let currentPage = visiblePageIndex(pages)
        return VStack(alignment: .leading, spacing: 12) {
            Picker("Preview mode", selection: $mode) {
                if !usesCustomRecess { Text("On the coaster").tag(PreviewMode.coaster) }
                Text("Cut").tag(PreviewMode.cut)
                Text("A4 sheet").tag(PreviewMode.sheet)
                if !usesCustomRecess { Text("3D").tag(PreviewMode.threeD) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .tint(theme.buttonTint)
            .accessibilityLabel("Preview mode")

            if mode == .threeD {
                HStack(spacing: 8) {
                    Text("Drag to rotate. Scroll to zoom.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("Recenter", systemImage: "viewfinder") { cameraRevision += 1 }
                        .controlSize(.small)
                }
            }

            if mode == .sheet && pages.count > 1 {
                HStack(spacing: 10) {
                    Button("Previous page", systemImage: "chevron.left") { page = currentPage - 1 }
                        .labelStyle(.iconOnly).disabled(currentPage == 0)
                    Text("Page \(currentPage + 1) of \(pages.count)").font(.subheadline).monospacedDigit()
                    Button("Next page", systemImage: "chevron.right") { page = currentPage + 1 }
                        .labelStyle(.iconOnly).disabled(currentPage + 1 >= pages.count)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
    }

    private var inspectorDivider: some View {
        Rectangle().fill(theme.divider)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private func artworkList(_ preparation: SheetPreparation) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Sheet artwork").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(totalCopies) \(totalCopies == 1 ? "sticker" : "stickers")")
                    .font(.caption.weight(.semibold)).foregroundStyle(theme.accentText)
                    .monospacedDigit()
            }
            ForEach(artworks) { artwork in
                HStack(spacing: 4) {
                    Button {
                        selection = artwork.id
                    } label: {
                        HStack(spacing: 9) {
                            Image(decorative: artwork.image, scale: 1)
                                .resizable().scaledToFill().frame(width: 38, height: 38)
                                .clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artwork.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(artwork.isSample ? "Sample artwork" : "\(artwork.image.width) × \(artwork.image.height) px")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text("×\(artwork.copies)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(theme.accentText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == artwork.id ? .isSelected : [])
                    Button {
                        removeArtwork(artwork.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isImporting)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Remove \(artwork.name) from the sheet")
                    .help("Remove from the sheet")
                }
                .padding(6)
                .background(
                    selection == artwork.id ? theme.selectionBackground : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    if selection == artwork.id {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(theme.selectionBorder, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
            }
            Button("Add images…", systemImage: "plus") { addImages() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(operation != nil || (totalCopies >= ArtworkExporter.maxCopies && !onlySampleArtwork))
            if artworks.isEmpty, let sample = model.sample {
                Button("Use sample artwork") {
                    artworks = [sample]
                    selection = sample.id
                }
                .disabled(isImporting)
            }
        }
    }

    private func framingControls(_ artwork: SheetArtwork, preparation: SheetPreparation) -> some View {
        let imageRect = preparation.selectedOptions.map(ArtworkExporter.imageRect) ?? .zero
        // Panning needs surplus artwork along the chosen axis. The tolerance
        // covers submillimeter floating-point rounding differences.
        let canPanX = preparation.metrics.map { imageRect.width - $0.artworkWidthMM > 0.001 } ?? false
        let canPanY = preparation.metrics.map { imageRect.height - $0.artworkHeightMM > 0.001 } ?? false
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Framing").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Reset") {
                    updateArtwork(artwork.id) {
                        $0.zoom = 1
                        $0.x = 0
                        $0.y = 0
                    }
                }
                .disabled(artwork.zoom == 1 && artwork.x == 0 && artwork.y == 0)
            }
            HStack(spacing: 8) {
                Text("Zoom").frame(width: 66, alignment: .leading)
                Slider(value: binding(artwork, \.zoom), in: 1...3.5)
                    .accessibilityLabel("Zoom")
                    .accessibilityValue("\(Int((artwork.zoom * 100).rounded())) percent")
                Text("\(Int((artwork.zoom * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            panSlider("Horizontal", value: binding(artwork, \.x), isEnabled: canPanX)
            panSlider("Vertical", value: binding(artwork, \.y), isEnabled: canPanY)
            // This artwork can use the open slots plus its existing copies.
            let maxArtworkCopies = max(1, ArtworkExporter.maxCopies - totalCopies + artwork.copies)
            Stepper(value: binding(artwork, \.copies), in: 1...maxArtworkCopies) {
                HStack {
                    Text("Copies of this artwork")
                    Text("\(artwork.copies)").monospacedDigit()
                }
            }
            .disabled(isImporting)
            .accessibilityLabel("Copies of this artwork")
            .accessibilityValue("\(artwork.copies)")
        }
    }

    private func panSlider(_ title: String, value: Binding<CGFloat>, isEnabled: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 66, alignment: .leading)
            Slider(value: value, in: -1...1)
                .accessibilityLabel(title)
                .disabled(!isEnabled)
        }
        .help(isEnabled ? "Pan the artwork" : "Zoom in to pan along this axis")
    }

    private func printSettings(_ preparation: SheetPreparation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Printing").font(.headline).accessibilityAddTraits(.isHeader)
            Picker("Resolution", selection: $dpi) {
                Text("150 dpi").tag(150)
                Text("300 dpi").tag(300)
                Text("600 dpi").tag(600)
            }
            numberField("Bleed (mm)", value: $bleed)
            DisclosureGroup("Model dimensions", isExpanded: $showsModelDimensions) {
                VStack(alignment: .leading, spacing: 9) {
                    Picker("Model", selection: $usesCustomRecess) {
                        Text("Cartrest").tag(false)
                        Text("Custom recess").tag(true)
                    }
                    if usesCustomRecess {
                        numberField("Width (mm)", value: $customWidth)
                        numberField("Height (mm)", value: $customHeight)
                        numberField("Radius (mm)", value: $customRadius)
                        numberField("Lower-left chamfer (mm)", value: $customChamfer)
                    } else {
                        numberField("Coaster width (mm)", value: $coasterWidth)
                        if hasValidCoasterWidth {
                            let body = preparation.geometry.body
                            Text("\(decimal(body.width)) × \(decimal(body.height)) × \(decimal(body.thickness)) mm")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Coaster width, height, and thickness in millimeters")
                                .accessibilityValue("\(decimal(body.width)) by \(decimal(body.height)) by \(decimal(body.thickness))")
                        }
                        Button("Save STL…", systemImage: "cube") { saveModel() }
                            .disabled(operation != nil || !hasValidCoasterWidth)
                            .help("Save the coaster with the dimensions shown above")
                    }
                }
                .padding(.top, 8)
            }
            if !usesCustomRecess {
                holderSettings
            }
            if let errorMessage = preparation.errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var holderSettings: some View {
        let holder = CoasterHolder(profile: console, coasterWidth: coasterWidth, slotCount: holderSlotCount,
                                   clearance: holderClearance)
        return DisclosureGroup("Coaster holder", isExpanded: $showsHolder) {
            VStack(alignment: .leading, spacing: 9) {
                Stepper(value: $holderSlotCount, in: CoasterHolder.slotRange) {
                    Text("\(holderSlotCount) \(holderSlotCount == 1 ? "slot" : "slots")").monospacedDigit()
                }
                .accessibilityLabel("Holder slots")
                .accessibilityValue("\(holderSlotCount)")
                numberField("Clearance per side (mm)", value: $holderClearance)
                if let holder {
                    Text("\(decimal(holder.width)) × \(decimal(holder.depth)) × \(decimal(holder.height)) mm")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Holder width, depth, and height in millimeters")
                        .accessibilityValue("\(decimal(holder.width)) by \(decimal(holder.depth)) by \(decimal(holder.height))")
                } else if !CoasterHolder.clearanceRange.contains(holderClearance) {
                    Text("Enter a clearance from 0.2 to 1.5 mm per side.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("Save Holder STL…", systemImage: "square.stack.3d.up") {
                    if let holder { saveHolder(holder) }
                }
                .disabled(operation != nil || holder == nil)
            }
            .padding(.top, 8)
        }
    }

    private func exportControls(_ preparation: SheetPreparation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let metrics = preparation.metrics {
                let n = preparation.pages.count
                Text("\(metrics.copiesPerPage) per sheet · \(n) A4 \(n == 1 ? "page" : "pages")")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(theme.accentText)
                Text("\(metrics.widthPX) × \(metrics.heightPX) px per artwork with bleed")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                if !metrics.canRasterize {
                    Text("Lower the resolution to export this artwork.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            HStack(spacing: 9) {
                Button("Save A4 PDF…", systemImage: "doc") { save(.pdf, preparation: preparation) }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.buttonTint)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(operation != nil || !preparation.canSave(.pdf))
                    .help("Export all artwork and copies on the sheet")
                Button("Save PNG…") { save(.png, preparation: preparation) }
                    .disabled(operation != nil || !preparation.canSave(.png))
                    .help("Export the selected artwork with bleed")
                if operation != nil {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel(status)
                }
            }
            .controlSize(.large)
            Text(status.isEmpty ? "Print the PDF at actual size (100%)." : status)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Fields and editing bindings

    private func numberField(_ title: String, value: Binding<CGFloat>) -> some View {
        let number = Binding<Double>(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = CGFloat($0) }
        )
        return LabeledContent(title) {
            TextField(title, value: number,
                      format: .number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 76)
        }
    }

    private func decimal(_ n: CGFloat) -> String {
        Double(n).formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
    }

    private func formattedSize(_ width: CGFloat, _ height: CGFloat) -> String {
        "\(decimal(width)) × \(decimal(height)) mm"
    }

    // Resolve the artwork by ID on every access. SwiftUI may still hold the
    // old binding after the list has changed.
    private func binding<T>(_ artwork: SheetArtwork, _ value: WritableKeyPath<SheetArtwork, T>) -> Binding<T> {
        Binding(
            get: { artworks.first { $0.id == artwork.id }?[keyPath: value] ?? artwork[keyPath: value] },
            set: { newValue in updateArtwork(artwork.id) { $0[keyPath: value] = newValue } }
        )
    }

    private func updateArtwork(_ id: UUID, _ edit: (inout SheetArtwork) -> Void) {
        if let index = artworks.firstIndex(where: { $0.id == id }) { edit(&artworks[index]) }
    }

    private func removeArtwork(_ id: UUID) {
        guard !isImporting else { return }
        guard let index = artworks.firstIndex(where: { $0.id == id }) else { return }
        artworks.remove(at: index)
        if selection == id {
            selection = artworks.isEmpty ? nil : artworks[min(index, artworks.count - 1)].id
        }
        if operation == nil { status = "" }
    }

    // MARK: - Import and export

    @ViewBuilder
    private func labelDesigner(_ preparation: SheetPreparation) -> some View {
        if let error = preparation.errorMessage {
            designerUnavailable(error)
        } else {
            switch LabelDesignCatalog.bundled {
            case .success(let catalog):
                let templateID = console.labelTemplate ?? console.id
                if let template = catalog.template(templateID) ?? catalog.template("custom") {
                    LabelDesigner(catalog: catalog, profile: console, geometry: preparation.geometry,
                                  label: preparation.label, bleed: bleed, dpi: dpi,
                                  canAddToSheet: onlySampleArtwork || totalCopies < ArtworkExporter.maxCopies,
                                  addArtwork: addDesignedArtwork,
                                  draft: Binding(get: { labelDraft ?? LabelDraft(template: template) },
                                                 set: { labelDraft = $0 }),
                                  workspace: $workspace, section: $labelSection, isWorking: $designerBusy)
                } else {
                    designerUnavailable(LabelDesignError.missingTemplate.localizedDescription)
                }
            case .failure(let error):
                designerUnavailable(error.localizedDescription)
            }
        }
    }

    private func designerUnavailable(_ reason: String) -> some View {
        HStack(spacing: 0) {
            ContentUnavailableView("Label Designer Unavailable", systemImage: "rectangle.slash",
                                   description: Text(reason))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            VStack(spacing: 0) {
                WorkspacePicker(selection: $workspace)
                inspectorDivider
                Spacer()
            }
            .frame(width: 342)
            .background(theme.inspectorBackground)
        }
    }

    private func addDesignedArtwork(_ artwork: SheetArtwork) {
        if onlySampleArtwork {
            artworks = [artwork]
        } else {
            guard totalCopies < ArtworkExporter.maxCopies else { return }
            artworks.append(artwork)
        }
        selection = artwork.id
        page = max(0, sheetPreparation.pages.count - 1)
        mode = .sheet
        workspace = .sheet
        status = "Added \(artwork.name)"
        AccessibilityNotification.Announcement(status).post()
    }

    private func addImages() {
        guard operation == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Add images"
        panel.prompt = "Add"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }

        let urls = panel.urls
        let replacesSample = onlySampleArtwork
        let maxCopies = ArtworkExporter.maxCopies
        let availableSlots = maxCopies - (replacesSample ? 0 : totalCopies)
        operation = .importing
        status = "Loading images…"

        // The panel runs on the UI thread. The worker only receives captured values
        // and completes decoding before the editor updates its selection.
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                SheetArtwork.loadBatch(urls, availableSlots: availableSlots, maxCopies: maxCopies)
            }.value
            defer {
                operation = nil
                status = ""
            }
            if let first = result.artworks.first {
                if replacesSample {
                    artworks = result.artworks
                } else {
                    artworks.append(contentsOf: result.artworks)
                }
                selection = first.id
                if result.artworks.count > 1 { mode = .sheet }
                page = 0
                if result.failures.isEmpty {
                    let count = result.artworks.count
                    AccessibilityNotification.Announcement(
                        count == 1 ? "One image added." : "\(count) images added."
                    ).post()
                }
            }
            if !result.failures.isEmpty {
                errorMessage = result.failures.joined(separator: "\n")
            }
        }
    }

    private func save(_ format: ExportFormat, preparation: SheetPreparation) {
        guard operation == nil, preparation.canSave(format),
              let selected = preparation.editingArtwork,
              let options = preparation.selectedOptions else { return }
        let filename = format == .pdf
            ? "\(console.exportPrefix)-a4-sheet.pdf"
            : "\(console.exportPrefix)-\(selected.name.replacingOccurrences(of: "/", with: "-")).png"

        // Capture the crop and artwork list before the save panel opens.
        let batch = preparation.artworks
        beginExport(filename, as: format.contentType) { destination in
            switch format {
            case .pdf:
                try ArtworkExporter.pdf(batch, to: destination)
            case .png:
                try ArtworkExporter.png(options).write(to: destination, options: .atomic)
            }
        }
    }

    private func saveModel() {
        guard !usesCustomRecess, hasValidCoasterWidth else { return }
        let scale = coasterWidth / baseGeometry.body.width
        let mesh = model.mesh
        let filename = "\(console.modelFilePrefix)-\(decimal(coasterWidth))mm.stl"
        beginExport(filename, as: UTType(filenameExtension: "stl") ?? .data) { destination in
            try mesh.write(scaledBy: scale, to: destination)
        }
    }

    private func saveHolder(_ holder: CoasterHolder) {
        let filename = "\(console.modelFilePrefix)-holder-\(holder.slotCount)slots-\(decimal(coasterWidth))mm.stl"
        beginExport(filename, as: UTType(filenameExtension: "stl") ?? .data) { destination in
            try holder.write(to: destination)
        }
    }

    private func beginExport(_ filename: String, as contentType: UTType,
                             write: @escaping @Sendable (URL) throws -> Void) {
        guard operation == nil else { return }
        let panel = NSSavePanel()
        panel.prompt = "Save"
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = filename
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        operation = .exporting
        status = "Exporting \(destination.pathExtension.uppercased())…"
        Task {
            defer { operation = nil }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try write(destination)
                }.value
                let success = "Saved as \(destination.lastPathComponent)"
                status = success
                AccessibilityNotification.Announcement(success).post()
            } catch {
                errorMessage = error.localizedDescription
                status = ""
            }
        }
    }
}
