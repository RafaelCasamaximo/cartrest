import SwiftUI
import UniformTypeIdentifiers

@main
struct CartrestApp: App {
    @ViewState private var showsProfilePicker = false
    @ViewState private var designerBusy = false

    var body: some Scene {
        Window("Cartrest", id: "cartrest") {
            ConsoleWorkspace(showsProfilePicker: $showsProfilePicker, designerBusy: $designerBusy)
                .environment(\.locale, Locale(identifier: "en_US"))
        }
        .defaultSize(width: 1180, height: 790)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Console Profile…") { showsProfilePicker = true }
                    .disabled(designerBusy)
            }
        }
    }
}

struct ConsoleWorkspace: View {
    @Binding var showsProfilePicker: Bool
    @Binding var designerBusy: Bool
    @ViewState private var models: [ConsoleModel] = []
    @ViewState private var activeID: String?
    @ViewState private var workspace: EditorWorkspace = .sheet
    @ViewState private var loadingProfiles = true
    @ViewState private var importingProfile = false
    @ViewState private var profileError: String?

    var body: some View {
        ZStack {
            if loadingProfiles {
                ProgressView("Loading consoles…")
            } else if models.isEmpty {
                ContentUnavailableView {
                    Label("No console profiles", systemImage: "rectangle.on.rectangle")
                } actions: {
                    Button("Import Console Profile…") { showsProfilePicker = true }
                }
            }

            // Keep each editor mounted so artwork and dimensions survive tab changes.
            ForEach(models) { model in
                CartrestEditor(model: model, isActive: model.id == activeID,
                               workspace: $workspace, designerBusy: $designerBusy)
            }
        }
        .frame(minWidth: 800, minHeight: 610)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if !models.isEmpty {
                    ConsoleTabs(models: models, activeID: $activeID)
                        .disabled(designerBusy)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Import Console Profile…", systemImage: "plus") { showsProfilePicker = true }
                    .disabled(loadingProfiles || importingProfile || designerBusy)
                    .help("Import a console profile from JSON")
            }
        }
        .task {
            guard loadingProfiles else { return }
            let result = await Task.detached(priority: .userInitiated) { ConsoleCatalog.load() }.value
            models = result.models
            activeID = models.first?.id
            loadingProfiles = false
            if !result.failures.isEmpty { profileError = result.failures.joined(separator: "\n") }
        }
        .fileImporter(isPresented: $showsProfilePicker, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): importProfile(url)
            case .failure(let error): profileError = error.localizedDescription
            }
        }
        .alert("Console Profiles", isPresented: Binding(
            get: { profileError != nil }, set: { if !$0 { profileError = nil } }
        )) {
            Button("OK", role: .cancel) { profileError = nil }
        } message: {
            Text(profileError ?? "")
        }
    }

    private func importProfile(_ url: URL) {
        guard !loadingProfiles, !importingProfile, !designerBusy else { return }
        importingProfile = true
        let knownIDs = Set(models.map(\.id))
        Task {
            defer { importingProfile = false }
            do {
                let model = try await Task.detached(priority: .userInitiated) {
                    try ConsoleCatalog.install(url, existingIDs: knownIDs)
                }.value
                models.append(model)
                ConsoleCatalog.sort(&models)
                if !designerBusy { activeID = model.id }
            } catch {
                profileError = "\(url.lastPathComponent) — \(error.localizedDescription)"
            }
        }
    }
}

private struct ConsoleTabs: View {
    let models: [ConsoleModel]
    @Binding var activeID: String?
    @Environment(\.colorScheme) private var colorScheme

    private var theme: CartrestTheme { CartrestTheme(colorScheme: colorScheme) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabs.fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 8) {
                ScrollViewReader { reader in
                    ScrollView(.horizontal) { tabs }
                        .scrollIndicators(.hidden)
                        .onChange(of: activeID, initial: true) { _, id in
                            if let id { reader.scrollTo(id, anchor: .center) }
                        }
                }
                .padding(.horizontal, 8)
                Menu {
                    ForEach(models) { model in
                        Button { activeID = model.id } label: {
                            if activeID == model.id {
                                Label(model.profile.name, systemImage: "checkmark")
                            } else {
                                Text(model.profile.name)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel("All consoles")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("All consoles")
            }
        }
        .frame(maxWidth: 620)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Consoles")
    }

    private var tabs: some View {
        HStack(spacing: 3) {
            ForEach(models) { model in
                let selected = model.id == activeID
                Button { activeID = model.id } label: {
                    Text(model.profile.name)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .fixedSize()
                        .padding(.horizontal, 15)
                        .padding(.vertical, 5)
                        .background {
                            if selected { Capsule().fill(theme.selectionBackground) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .id(model.id)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.quaternary, in: Capsule())
    }
}
