import SwiftUI

@main
struct CartrestApp: App {
    // The bundle contains the dimensions used by both the editor and the 3D model.
    // If they cannot be loaded, the window shows the error before opening the editor.
    private let geometry = Result { try Geometry.load() }

    var body: some Scene {
        Window("Cartrest", id: "cartrest") {
            switch geometry {
            case .success(let model):
                CartrestEditor(geometry: model)
                    .environment(\.locale, Locale(identifier: "en_US"))
            case .failure(let error):
                ContentUnavailableView("Model unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text(error.localizedDescription))
                    .frame(minWidth: 500, minHeight: 350)
            }
        }
        .defaultSize(width: 1180, height: 790)
    }
}
