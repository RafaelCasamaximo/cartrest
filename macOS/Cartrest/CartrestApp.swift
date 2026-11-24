import SwiftUI

@main
struct CartrestApp: App {
    // O bundle é o ponto de encontro entre o editor e as medidas do modelo 3D.
    // Uma falha nessa leitura aparece na própria janela antes de abrir o editor.
    private let geometria = Result { try Geometria.carregar() }

    var body: some Scene {
        Window("Cartrest", id: "cartrest") {
            switch geometria {
            case .success(let modelo):
                EditorCartrest(modelo: modelo)
                    .environment(\.locale, Locale(identifier: "pt_BR"))
            case .failure(let erro):
                ContentUnavailableView("Modelo indisponível", systemImage: "exclamationmark.triangle",
                                       description: Text(erro.localizedDescription))
                    .frame(minWidth: 500, minHeight: 350)
            }
        }
        .defaultSize(width: 1180, height: 790)
    }
}
