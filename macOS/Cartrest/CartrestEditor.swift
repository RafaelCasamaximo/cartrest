import Accessibility
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// This alias keeps the property wrapper available on SDKs with a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

enum PreviewMode: String {
    case coaster, cut, sheet, threeD
}

private enum ExportFormat: Sendable {
    case pdf, png

    var fileExtension: String { self == .pdf ? "pdf" : "png" }
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
    let baseGeometry: Geometry
    @Environment(\.colorScheme) private var colorScheme
    @ViewState private var artworks: [SheetArtwork]
    @ViewState private var selection: UUID?
    @ViewState private var mode: PreviewMode = .coaster
    @ViewState private var page = 0
    @ViewState private var cameraRevision = 0
    @ViewState private var usesCustomRecess = false
    @ViewState private var showsModelDimensions = false
    @ViewState private var coasterWidth: CGFloat = 100
    @ViewState private var customWidth: CGFloat = 81.8
    @ViewState private var customHeight: CGFloat = 86.4
    @ViewState private var customRadius: CGFloat = 3.5
    @ViewState private var customChamfer: CGFloat = 0
    @ViewState private var bleed: CGFloat = 2
    @ViewState private var dpi = 300
    @ViewState private var operation: EditorOperation?
    @ViewState private var status = ""
    @ViewState private var errorMessage: String?

    private var theme: CartrestTheme { CartrestTheme(colorScheme: colorScheme) }
    private var onlySampleArtwork: Bool { artworks.count == 1 && artworks.first?.isSample == true }
    private var isImporting: Bool { operation == .importing }

    init(geometry: Geometry) {
        baseGeometry = geometry
        let sample = SheetArtwork.sample()
        _artworks = ViewState(initialValue: sample.map { [$0] } ?? [])
        _selection = ViewState(initialValue: sample?.id)
    }

    private var validationError: String? {
        if !usesCustomRecess && !(60...180).contains(coasterWidth) {
            return "Enter a coaster width between 60 and 180 mm."
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
        let geometry = baseGeometry.scaled(toWidth: coasterWidth)
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
        let preparation = sheetPreparation
        return HSplitView {
            preview(preparation)
                .frame(minWidth: 470, idealWidth: 820, maxWidth: .infinity, maxHeight: .infinity)
            inspector(preparation)
                .frame(minWidth: 320, idealWidth: 342, maxWidth: 420, maxHeight: .infinity)
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
                geometry: preparation.errorMessage == nil ? preparation.geometry : baseGeometry,
                label: preparation.label, artwork: preparation.selectedOptions,
                artworks: preparation.artworks, placements: pages.indices.contains(visiblePage) ? pages[visiblePage] : [],
                page: visiblePage + 1, pageCount: pages.count,
                bottomInset: MeasurementDisplay.previewBottomInset
            )
            .accessibilityHidden(previewMode == .threeD)

            if previewMode == .threeD {
                Cartridge3D(
                    geometry: preparation.errorMessage == nil ? preparation.geometry : baseGeometry,
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
            inspectorHeader(preparation.pages)
            inspectorDivider
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    artworkList
                    if let selected = preparation.editingArtwork {
                        inspectorDivider
                        framingControls(selected, preparation: preparation)
                    }
                    inspectorDivider
                    printSettings(errorMessage: preparation.errorMessage)
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

    private var artworkList: some View {
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
            if artworks.isEmpty {
                Button("Use sample artwork") {
                    if let sample = SheetArtwork.sample() {
                        artworks = [sample]
                        selection = sample.id
                    }
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

    private func printSettings(errorMessage: String?) -> some View {
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
                        Text("In your slicer, set X and Y to \(decimal(coasterWidth / baseGeometry.body.width * 100))% and leave Z at 100%.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
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
        let panel = NSSavePanel()
        panel.prompt = "Save"
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = format == .pdf
            ? "cartrest-a4-sheet.pdf"
            : "cartrest-\(selected.name.replacingOccurrences(of: "/", with: "-")).png"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        // Export uses the crop and artwork list from the moment of the click.
        // Each format writes the completed file atomically while editing can continue.
        let batch = preparation.artworks
        operation = .exporting
        status = "Exporting \(format.fileExtension.uppercased())…"
        Task {
            defer { operation = nil }
            do {
                try await Task.detached(priority: .userInitiated) {
                    switch format {
                    case .pdf:
                        try ArtworkExporter.pdf(batch, to: destination)
                    case .png:
                        try ArtworkExporter.png(options).write(to: destination, options: .atomic)
                    }
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
