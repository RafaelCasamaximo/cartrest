import Foundation

struct ConsoleModel: Identifiable, Sendable {
    let profile: ConsoleProfile
    let mesh: CartridgeSTL
    let sample: SheetArtwork?

    var id: String { profile.id }

    init(profile: ConsoleProfile, bundle: Bundle = .main) throws {
        self.profile = profile
        mesh = try CartridgeModel.build(from: profile)
        sample = profile.sampleArtwork.flatMap { SheetArtwork.sample(named: $0, in: bundle) }
    }
}

/// Discovers both bundled and user profiles. Import validates the mesh before
/// installing a copy, so incomplete or invalid definitions cannot create a tab.
enum ConsoleCatalog {
    struct LoadResult: Sendable {
        var models: [ConsoleModel] = []
        var failures: [String] = []
    }

    static func load(bundle: Bundle = .main) -> LoadResult {
        var result = LoadResult()
        var knownIDs: Set<String> = []
        let builtIn = bundle.resourceURL?.appending(path: "Consoles", directoryHint: .isDirectory)
        var locations = [builtIn].compactMap { $0 }
        do {
            locations.append(try libraryDirectory())
        } catch {
            result.failures.append(error.localizedDescription)
        }

        for directory in locations where FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
            do {
                let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                                         options: [.skipsHiddenFiles])
                for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                where file.pathExtension.lowercased() == "json" && file.lastPathComponent != "profile.schema.json" {
                    do {
                        let profile = try ConsoleProfile.decode(read(file))
                        guard !knownIDs.contains(profile.id) else { throw ProfileError.duplicate(profile.id) }
                        result.models.append(try ConsoleModel(profile: profile, bundle: bundle))
                        knownIDs.insert(profile.id)
                    } catch {
                        result.failures.append("\(file.lastPathComponent) — \(error.localizedDescription)")
                    }
                }
            } catch {
                result.failures.append("\(directory.lastPathComponent) — \(error.localizedDescription)")
            }
        }
        sort(&result.models)
        return result
    }

    static func install(_ url: URL, existingIDs: Set<String>) throws -> ConsoleModel {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try read(url)
        let profile = try ConsoleProfile.decode(data)
        guard !existingIDs.contains(profile.id) else { throw ProfileError.duplicate(profile.id) }
        let model = try ConsoleModel(profile: profile)

        let directory = try libraryDirectory()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: "\(profile.id).json")
        let staging = directory.appending(path: ".\(UUID().uuidString).tmp")
        try data.write(to: staging, options: .atomic)
        defer { try? fileManager.removeItem(at: staging) }
        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            throw ProfileError.duplicate(profile.id)
        }
        return model
    }

    static func sort(_ models: inout [ConsoleModel]) {
        models.sort { ($0.profile.order, $0.profile.name, $0.id) < ($1.profile.order, $1.profile.name, $1.id) }
    }

    private static func libraryDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: false)
            .appending(path: "Cartrest/Consoles", directoryHint: .isDirectory)
    }

    private static func read(_ url: URL) throws -> Data {
        let limit = 256 * 1024
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw ProfileError.invalid("Choose a regular JSON file.")
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard let data = try file.read(upToCount: limit + 1), data.count <= limit else {
            throw ProfileError.invalid("Use a JSON profile smaller than 256 KiB.")
        }
        return data
    }
}
