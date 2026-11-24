import CoreGraphics
import CoreText
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Um item da folha. As dimensões são de corte, sem a sangria aplicada a cada lado.
struct OpcoesArte {
    let imagem: CGImage
    let larguraMm: CGFloat
    let alturaMm: CGFloat
    let raioMm: CGFloat
    let chanfroMm: CGFloat
    let sangriaMm: CGFloat
    let dpi: Int
    let zoom: CGFloat
    /// Deslocamentos relativos ao espaço de recorte, de -1 a 1. Y cresce para baixo.
    let x: CGFloat
    let y: CGFloat
    let copias: Int
}

struct MedidasArte {
    let larguraArteMm: CGFloat
    let alturaArteMm: CGFloat
    let larguraPx: Int
    let alturaPx: Int
    let copiasPorPagina: Int
    let paginas: Int

    var podeRasterizar: Bool {
        larguraPx > 0 && alturaPx > 0 && larguraPx <= Exportador.limitePixels / alturaPx
    }
}

/// Posição da arte com sangria. O índice referencia o lote original e se repete entre cópias.
struct PosicaoA4 {
    let indiceArte: Int
    let quadro: CGRect
}

enum Exportador {
    static let tamanhoFolha = CGSize(width: 210, height: 297)
    static let origemRegua = CGPoint(x: 10, y: 275)
    static let larguraRegua: CGFloat = 50
    static let limiteCopias = 24

    // Um raster RGB usa quatro bytes por pixel em Quartz, inclusive com o fundo opaco.
    fileprivate static let limitePixels = 16_000_000
    private static let sangriaValida: ClosedRange<CGFloat> = 0...10
    private static let margem: CGFloat = 10
    // Reserva espaço para a identificação no topo e a régua no rodapé.
    private static let inicio: CGFloat = 29
    private static let fim: CGFloat = 266
    private static let intervalo: CGFloat = 7
    private static let pontoPorMm: CGFloat = 72 / 25.4

    private enum Falha: LocalizedError {
        case imagem
        case png
        case pdf
        case tamanhoA4
        case lote

        var errorDescription: String? {
            switch self {
            case .imagem: return "A imagem ficou muito grande ou tem dimensões inválidas."
            case .png: return "Não foi possível gerar o arquivo PNG."
            case .pdf: return "Não foi possível gerar o arquivo PDF."
            case .tamanhoA4: return "A arte com sangria não cabe em uma folha A4."
            case .lote: return "Use artes com as mesmas dimensões, sangria e resolução, com até 24 adesivos no total."
            }
        }
    }

    /// Mede em pixels apenas para rasterização. A posição e o corte em PDF continuam em milímetros.
    static func medir(_ opcoes: OpcoesArte) -> MedidasArte {
        let arte = tamanhoArte(opcoes)
        let grade = gradeA4(arte)
        let pixelsPorMm = CGFloat(dpiValido(opcoes.dpi)) / 25.4
        let copiasValidas = (1...limiteCopias).contains(opcoes.copias)
        let paginas = copiasValidas && grade.capacidade > 0
            ? (opcoes.copias + grade.capacidade - 1) / grade.capacidade
            : 0

        return MedidasArte(
            larguraArteMm: arte.width, alturaArteMm: arte.height,
            larguraPx: pixels(arte.width * pixelsPorMm), alturaPx: pixels(arte.height * pixelsPorMm),
            copiasPorPagina: grade.capacidade, paginas: paginas
        )
    }

    /// Calcula o recorte que a prévia e a exportação compartilham. A origem é o topo esquerdo
    /// do quadro com sangria, em mm. A imagem mantém a proporção e cobre a área até nos extremos.
    static func quadroImagem(_ opcoes: OpcoesArte) -> CGRect {
        let arte = tamanhoArte(opcoes)
        let largura = CGFloat(opcoes.imagem.width)
        let altura = CGFloat(opcoes.imagem.height)
        let zoom = limitar(opcoes.zoom, entre: 1...3.5, padrao: 1)
        let escala = max(arte.width / largura, arte.height / altura) * zoom
        let imagemLargura = largura * escala
        let imagemAltura = altura * escala
        let x = limitar(opcoes.x, entre: -1...1)
        let y = limitar(opcoes.y, entre: -1...1)
        return CGRect(
            x: (arte.width - imagemLargura) * (1 - x) / 2,
            y: (arte.height - imagemAltura) * (1 - y) / 2,
            width: imagemLargura,
            height: imagemAltura
        )
    }

    static func png(_ opcoes: OpcoesArte) throws -> Data {
        let imagem = try arteRasterizada(opcoes)
        let dados = NSMutableData()
        guard let destino = CGImageDestinationCreateWithData(
            dados as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else { throw Falha.png }

        // O PNG registra a resolução física em pixels inteiros por metro no bloco pHYs.
        let dpi = dpiValido(opcoes.dpi)
        let pixelsPorMetro = Int((CGFloat(dpi) / 0.0254).rounded())
        let metadados: [String: Any] = [
            kCGImagePropertyDPIWidth as String: dpi,
            kCGImagePropertyDPIHeight as String: dpi,
            kCGImagePropertyPNGDictionary as String: [
                kCGImagePropertyPNGXPixelsPerMeter as String: pixelsPorMetro,
                kCGImagePropertyPNGYPixelsPerMeter as String: pixelsPorMetro,
            ],
        ]
        CGImageDestinationAddImage(destino, imagem, metadados as CFDictionary)
        guard CGImageDestinationFinalize(destino) else { throw Falha.png }
        return dados as Data
    }

    /// Distribui as cópias em ordem de entrada. Cada quadro está em mm a partir do topo
    /// esquerdo do A4 e as páginas incompletas são centralizadas na horizontal.
    static func layout(_ artes: [OpcoesArte]) -> [[PosicaoA4]] {
        guard let primeira = artes.first, artes.count <= limiteCopias else { return [] }
        let arte = tamanhoArte(primeira)
        let sangria = limitar(primeira.sangriaMm, entre: sangriaValida)
        let dpi = dpiValido(primeira.dpi)
        guard artes.allSatisfy({
            $0.larguraMm == primeira.larguraMm && $0.alturaMm == primeira.alturaMm &&
            limitar($0.sangriaMm, entre: sangriaValida) == sangria && dpiValido($0.dpi) == dpi &&
            (1...limiteCopias).contains($0.copias)
        }) else { return [] }
        let grade = gradeA4(arte)
        let total = artes.reduce(0) { $0 + $1.copias }
        guard grade.capacidade > 0, total <= limiteCopias else { return [] }

        let indices = artes.indices.flatMap { Array(repeating: $0, count: artes[$0].copias) }
        return stride(from: 0, to: indices.count, by: grade.capacidade).map { inicioDaFolha in
            let fimDaFolha = min(inicioDaFolha + grade.capacidade, indices.count)
            let folha = indices[inicioDaFolha..<fimDaFolha]
            let colunas = min(grade.colunas, folha.count)
            let larguraGrade = CGFloat(colunas) * arte.width + CGFloat(colunas - 1) * intervalo
            let esquerda = (tamanhoFolha.width - larguraGrade) / 2
            return folha.enumerated().map { indice, indiceArte in
                let x = esquerda + CGFloat(indice % colunas) * (arte.width + intervalo)
                let y = inicio + CGFloat(indice / colunas) * (arte.height + intervalo)
                return PosicaoA4(
                    indiceArte: indiceArte,
                    quadro: CGRect(origin: CGPoint(x: x, y: y), size: arte)
                )
            }
        }
    }

    static func pdf(_ opcoes: OpcoesArte) throws -> Data {
        try pdf([opcoes])
    }

    static func pdf(_ artes: [OpcoesArte]) throws -> Data {
        let dados = NSMutableData()
        guard let consumidor = CGDataConsumer(data: dados as CFMutableData) else { throw Falha.pdf }
        try escreverPDF(artes, no: consumidor)
        guard dados.length > 0 else { throw Falha.pdf }
        return dados as Data
    }

    /// Escreve lotes diretamente no disco. O destino recebe o arquivo inteiro só depois de
    /// o Quartz fechar o PDF e o leitor conferir a contagem de páginas, mesmo em uma substituição.
    static func pdf(_ artes: [OpcoesArte], para destino: URL) throws {
        guard destino.isFileURL else { throw Falha.pdf }
        let arquivos = FileManager.default
        let pastaTemporaria = try arquivos.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destino, create: true
        )
        defer { try? arquivos.removeItem(at: pastaTemporaria) }
        let temporario = pastaTemporaria.appendingPathComponent("Cartrest.pdf")
        guard let consumidor = CGDataConsumer(url: temporario as CFURL) else { throw Falha.pdf }
        let paginas = try escreverPDF(artes, no: consumidor)
        guard let documento = CGPDFDocument(temporario as CFURL),
              documento.numberOfPages == paginas else { throw Falha.pdf }

        // A pasta de substituição fica no mesmo volume, o que mantém o rename atômico.
        let codigo = temporario.withUnsafeFileSystemRepresentation { origem in
            destino.withUnsafeFileSystemRepresentation { final in
                guard let origem, let final else { return EINVAL }
                return Darwin.rename(origem, final) == 0 ? 0 : errno
            }
        }
        guard codigo == 0 else { throw POSIXError(POSIXErrorCode(rawValue: codigo) ?? .EIO) }
    }

    @discardableResult
    private static func escreverPDF(_ artes: [OpcoesArte], no consumidor: CGDataConsumer) throws -> Int {
        guard let primeira = artes.first else { throw Falha.lote }
        let medidas = medir(primeira)
        guard medidas.copiasPorPagina > 0 else { throw Falha.tamanhoA4 }
        let paginas = layout(artes)
        guard !paginas.isEmpty else { throw Falha.lote }
        guard medidas.podeRasterizar else { throw Falha.imagem }

        var pagina = CGRect(
            x: 0, y: 0, width: tamanhoFolha.width * pontoPorMm, height: tamanhoFolha.height * pontoPorMm
        )
        let metadados: [String: String] = [
            kCGPDFContextTitle as String: "Cartrest - Etiquetas para vinil",
            kCGPDFContextCreator as String: "Cartrest",
        ]
        guard let contexto = CGContext(consumer: consumidor, mediaBox: &pagina, metadados as CFDictionary)
        else { throw Falha.pdf }
        defer { contexto.closePDF() }

        // As cópias de uma arte são consecutivas. Reuse só o raster em uso, inclusive entre páginas.
        var raster: (indice: Int, imagem: CGImage)?
        for (folha, posicoes) in paginas.enumerated() {
            try autoreleasepool {
                contexto.beginPDFPage(nil)
                defer { contexto.endPDFPage() }
                cabecalho(contexto, opcoes: primeira, folha: folha, paginas: paginas.count)

                for posicao in posicoes {
                    let opcoes = artes[posicao.indiceArte]
                    let imagem: CGImage
                    if let raster, raster.indice == posicao.indiceArte {
                        imagem = raster.imagem
                    } else {
                        imagem = try arteRasterizada(opcoes)
                        raster = (posicao.indiceArte, imagem)
                    }
                    let quadro = posicao.quadro
                    let canto = ponto(quadro.minX, quadro.maxY)
                    contexto.draw(imagem, in: CGRect(
                        x: canto.x, y: canto.y, width: quadro.width * pontoPorMm, height: quadro.height * pontoPorMm
                    ))
                    let sangria = limitar(opcoes.sangriaMm, entre: sangriaValida)
                    let corte = quadro.insetBy(dx: sangria, dy: sangria)
                    try tracarCorte(contexto, quadro: corte, opcoes: opcoes)
                }
                regua(contexto)
            }
        }
        return paginas.count
    }

    private static func limitar(_ valor: CGFloat, entre limites: ClosedRange<CGFloat>, padrao: CGFloat = 0) -> CGFloat {
        min(limites.upperBound, max(limites.lowerBound, valor.isFinite ? valor : padrao))
    }

    private static func dpiValido(_ dpi: Int) -> Int {
        min(1200, max(72, dpi))
    }

    private static func pixels(_ valor: CGFloat) -> Int {
        guard valor > 0, valor < CGFloat(Int32.max) else { return 0 }
        return max(1, Int(valor.rounded()))
    }

    private static func tamanhoArte(_ opcoes: OpcoesArte) -> CGSize {
        guard opcoes.larguraMm.isFinite, opcoes.alturaMm.isFinite,
              opcoes.larguraMm > 0, opcoes.alturaMm > 0 else { return .zero }
        let sangria = limitar(opcoes.sangriaMm, entre: sangriaValida)
        return CGSize(width: opcoes.larguraMm + 2 * sangria, height: opcoes.alturaMm + 2 * sangria)
    }

    private static func gradeA4(_ arte: CGSize) -> (colunas: Int, capacidade: Int) {
        guard arte.width > 0, arte.height > 0 else { return (0, 0) }
        // Soma um intervalo ao espaço útil porque a última coluna ou linha não tem vão após ela.
        let colunas = Int((tamanhoFolha.width - 2 * margem + intervalo) / (arte.width + intervalo))
        let linhas = Int((fim - inicio + intervalo) / (arte.height + intervalo))
        return (colunas, colunas * linhas)
    }

    private static func arteRasterizada(_ opcoes: OpcoesArte) throws -> CGImage {
        let medidas = medir(opcoes)
        let largura = medidas.larguraPx
        let altura = medidas.alturaPx
        guard medidas.podeRasterizar,
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let contexto = CGContext(
                data: nil, width: largura, height: altura, bitsPerComponent: 8, bytesPerRow: 0,
                space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { throw Falha.imagem }

        // A área transparente de uma imagem assume a cor do fundo branco, igual à prévia.
        contexto.setFillColor(CGColor(gray: 1, alpha: 1))
        contexto.fill(CGRect(x: 0, y: 0, width: largura, height: altura))
        contexto.interpolationQuality = .high
        let quadro = quadroImagem(opcoes)
        let escalaX = CGFloat(largura) / medidas.larguraArteMm
        let escalaY = CGFloat(altura) / medidas.alturaArteMm
        // O recorte cresce para baixo, enquanto o contexto bitmap tem origem inferior esquerda.
        let desenho = CGRect(
            x: quadro.minX * escalaX, y: (medidas.alturaArteMm - quadro.maxY) * escalaY,
            width: quadro.width * escalaX, height: quadro.height * escalaY
        )
        guard desenho.minX.isFinite, desenho.minY.isFinite,
              desenho.width.isFinite, desenho.height.isFinite else { throw Falha.imagem }
        contexto.draw(opcoes.imagem, in: desenho)
        guard let imagem = contexto.makeImage() else { throw Falha.imagem }
        return imagem
    }

    private static func ponto(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * pontoPorMm, y: (tamanhoFolha.height - y) * pontoPorMm)
    }

    private static func tracarCorte(_ contexto: CGContext, quadro: CGRect, opcoes: OpcoesArte) throws {
        let caminhoMm = contorno(em: quadro, raio: opcoes.raioMm, chanfro: opcoes.chanfroMm)
        // Espelha Y e converte de mm para pontos após criar o mesmo vetor usado na prévia.
        var paraPDF = CGAffineTransform(
            a: pontoPorMm, b: 0, c: 0, d: -pontoPorMm, tx: 0, ty: tamanhoFolha.height * pontoPorMm
        )
        guard let caminho = caminhoMm.copy(using: &paraPDF) else { throw Falha.pdf }

        contexto.saveGState()
        defer { contexto.restoreGState() }
        // O traço claro sob o escuro preserva a leitura sobre fundos claros e escuros.
        contexto.setLineDash(phase: 0, lengths: [3, 2])
        contexto.setLineWidth(1.15)
        contexto.setStrokeColor(CGColor(gray: 1, alpha: 1))
        contexto.addPath(caminho)
        contexto.strokePath()
        contexto.setLineWidth(0.42)
        contexto.setStrokeColor(CGColor(gray: 0, alpha: 1))
        contexto.addPath(caminho)
        contexto.strokePath()
    }

    private static func texto(_ contexto: CGContext, _ texto: String, x: CGFloat, y: CGFloat, tamanho: CGFloat) {
        let fonte = CTFontCreateWithName("Helvetica" as CFString, tamanho, nil)
        let atribuida = NSAttributedString(
            string: texto,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): fonte]
        )
        contexto.textPosition = ponto(x, y)
        CTLineDraw(CTLineCreateWithAttributedString(atribuida), contexto)
    }

    private static func formatarMm(_ medida: CGFloat) -> String {
        Double(medida).formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "pt_BR")))
    }

    private static func cabecalho(_ contexto: CGContext, opcoes: OpcoesArte, folha: Int, paginas: Int) {
        let largura = formatarMm(opcoes.larguraMm)
        let altura = formatarMm(opcoes.alturaMm)
        let sangria = formatarMm(limitar(opcoes.sangriaMm, entre: sangriaValida))
        texto(contexto, "Cartrest", x: 10, y: 13, tamanho: 15)
        texto(
            contexto, "Corte \(largura) × \(altura) mm   |   Sangria \(sangria) mm   |   \(dpiValido(opcoes.dpi)) dpi",
            x: 10, y: 20, tamanho: 9
        )
        texto(contexto, "Folha \(folha + 1) de \(paginas)", x: 176, y: 20, tamanho: 9)
    }

    private static func regua(_ contexto: CGContext) {
        let x = origemRegua.x
        let y = origemRegua.y
        let meio = x + larguraRegua / 2
        let fim = x + larguraRegua
        contexto.setStrokeColor(CGColor(gray: 0, alpha: 1))
        contexto.setLineWidth(0.7)
        let segmentos: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (x, y, fim, y), (x, y - 2, x, y + 2),
            (meio, y - 1, meio, y + 1), (fim, y - 2, fim, y + 2),
        ]
        for (x1, y1, x2, y2) in segmentos {
            contexto.move(to: ponto(x1, y1))
            contexto.addLine(to: ponto(x2, y2))
        }
        contexto.strokePath()
        texto(contexto, "0", x: x, y: y + 7, tamanho: 8)
        texto(contexto, formatarMm(larguraRegua / 2), x: meio - 1.6, y: y + 7, tamanho: 8)
        texto(contexto, "\(formatarMm(larguraRegua)) mm", x: fim - 3, y: y + 7, tamanho: 8)
        texto(contexto, "Imprima em A4 a 100%, em tamanho real.", x: 87, y: y, tamanho: 9)
        texto(contexto, "Confira a régua e recorte pelo tracejado.", x: 87, y: y + 6, tamanho: 9)
    }
}
