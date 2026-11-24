import CoreGraphics
import Foundation
import ImageIO

/// Uma arte tem identidade estável e mantém o recorte ao trocar de seleção.
/// Zoom e deslocamentos são os controles normalizados que o motor também usa na exportação.
struct ArteDaFolha: Identifiable, Sendable {
    let id = UUID()
    let nome: String
    let imagem: CGImage
    var exemplo = false
    var zoom: CGFloat = 1
    var x: CGFloat = 0
    var y: CGFloat = 0
    var copias = 1

    static func amostra() -> ArteDaFolha? {
        guard let url = Bundle.main.url(forResource: "mare-alta", withExtension: "png") else { return nil }
        return try? abrir(url, exemplo: true)
    }

    /// Mantém a ordem da seleção e coleta falhas individuais para o editor.
    /// Arquivos inválidos deixam a vaga disponível para o próximo arquivo.
    static func importar(_ urls: [URL], vagas: Int, limite: Int) -> ResultadoDaImportacao {
        var artes: [ArteDaFolha] = []
        var falhas: [String] = []
        for url in urls {
            if artes.count >= vagas {
                falhas.append("A folha aceita até \(limite) adesivos por exportação.")
                break
            }
            do {
                artes.append(try abrir(url))
            } catch {
                falhas.append(error.localizedDescription)
            }
        }
        return ResultadoDaImportacao(artes: artes, falhas: falhas)
    }

    private static func abrir(_ url: URL, exemplo: Bool = false) throws -> ArteDaFolha {
        guard let fonte = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ErroDeImportacao.arquivoInvalido(url.lastPathComponent)
        }

        // ImageIO aplica a orientação do arquivo uma vez, antes de o recorte ser calculado.
        // A primeira imagem fica limitada a 4600 px no maior lado para conter o custo do lote.
        let opcoes: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4600
        ]
        guard let imagem = CGImageSourceCreateThumbnailAtIndex(fonte, 0, opcoes as CFDictionary) else {
            throw ErroDeImportacao.arquivoInvalido(url.lastPathComponent)
        }
        return ArteDaFolha(nome: exemplo ? "Maré Alta" : url.deletingPathExtension().lastPathComponent,
                           imagem: imagem, exemplo: exemplo)
    }
}

struct ResultadoDaImportacao: Sendable {
    let artes: [ArteDaFolha]
    let falhas: [String]
}

private enum ErroDeImportacao: LocalizedError {
    case arquivoInvalido(String)

    var errorDescription: String? {
        switch self {
        case .arquivoInvalido(let nome):
            "Não foi possível abrir \(nome). Tente salvar a imagem como PNG ou JPG."
        }
    }
}
