import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let largura = 640
private let altura = 400
private let tamanho = CGSize(width: largura, height: altura)
private let centro = CGFloat(largura) / 2
private let rgb = CGColorSpace(name: CGColorSpace.sRGB)!

private func cor(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 255) / 255,
        green: CGFloat((hex >> 8) & 255) / 255,
        blue: CGFloat(hex & 255) / 255,
        alpha: alpha
    )
}

private func texto(_ titulo: String, base: CGFloat, tamanhoFonte: CGFloat, peso: NSFont.Weight, tinta: UInt32, em contexto: CGContext) {
    let atributos: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: tamanhoFonte, weight: peso),
        .foregroundColor: NSColor(cgColor: cor(tinta))!
    ]
    let linha = CTLineCreateWithAttributedString(NSAttributedString(string: titulo, attributes: atributos))
    let larguraTexto = CTLineGetTypographicBounds(linha, nil, nil, nil)
    contexto.textPosition = CGPoint(x: centro - larguraTexto / 2, y: base)
    CTLineDraw(linha, contexto)
}

private func desenhar(em contexto: CGContext) {
    let luz = CGGradient(colorsSpace: rgb, colors: [cor(0x28443a), cor(0x132823)] as CFArray, locations: [0, 1])!
    contexto.drawLinearGradient(luz, start: CGPoint(x: 70, y: altura), end: CGPoint(x: 580, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // A grade mantém o ritmo visual do tapete de corte do editor.
    for x in stride(from: 0, through: largura, by: 20) {
        contexto.setStrokeColor(cor(0x84af99, alpha: x.isMultiple(of: 100) ? 0.19 : 0.09))
        contexto.setLineWidth(0.5)
        contexto.move(to: CGPoint(x: x, y: 0))
        contexto.addLine(to: CGPoint(x: x, y: altura))
        contexto.strokePath()
    }
    for y in stride(from: 0, through: altura, by: 20) {
        contexto.setStrokeColor(cor(0x84af99, alpha: y.isMultiple(of: 100) ? 0.19 : 0.09))
        contexto.move(to: CGPoint(x: 0, y: y))
        contexto.addLine(to: CGPoint(x: largura, y: y))
        contexto.strokePath()
    }

    // O Finder posiciona os ícones a partir do topo. A arte usa a mesma cota invertida.
    let meioDosIcones: CGFloat = CGFloat(altura) - 229
    for x: CGFloat in [174, 466] {
        let area = CGRect(x: x - 73, y: meioDosIcones - 68, width: 146, height: 133)
        let contorno = CGPath(roundedRect: area, cornerWidth: 17, cornerHeight: 17, transform: nil)
        contexto.setFillColor(cor(0x9cbea5, alpha: 0.10))
        contexto.addPath(contorno)
        contexto.fillPath()
        contexto.setStrokeColor(cor(0xb0d9b7, alpha: 0.24))
        contexto.setLineWidth(1)
        contexto.addPath(contorno)
        contexto.strokePath()
    }

    // O gesto de instalação é de um ícone para o outro; a seta fica fora das áreas de arraste.
    contexto.setStrokeColor(cor(0xa9d5af))
    contexto.setLineWidth(2.4)
    contexto.setLineCap(.round)
    contexto.setLineJoin(.round)
    contexto.move(to: CGPoint(x: centro - 24, y: meioDosIcones))
    contexto.addLine(to: CGPoint(x: centro + 24, y: meioDosIcones))
    contexto.move(to: CGPoint(x: centro + 15, y: meioDosIcones + 9))
    contexto.addLine(to: CGPoint(x: centro + 24, y: meioDosIcones))
    contexto.addLine(to: CGPoint(x: centro + 15, y: meioDosIcones - 9))
    contexto.strokePath()

    texto("Cartrest", base: 325, tamanhoFonte: 43, peso: .semibold, tinta: 0xf0f5e9, em: contexto)
    texto("Arraste o Cartrest para Aplicativos.", base: 291, tamanhoFonte: 16, peso: .medium, tinta: 0xc7ddcb, em: contexto)
}

enum ErroDeRender: LocalizedError {
    case imagem

    var errorDescription: String? { "Não foi possível gravar o fundo do instalador." }
}

private func gravar(escala: Int, em arquivo: URL) throws {
    guard let contexto = CGContext(data: nil, width: largura * escala, height: altura * escala, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: rgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw ErroDeRender.imagem
    }
    contexto.scaleBy(x: CGFloat(escala), y: CGFloat(escala))
    contexto.clip(to: CGRect(origin: .zero, size: tamanho))
    desenhar(em: contexto)
    guard let imagem = contexto.makeImage(),
          let destino = CGImageDestinationCreateWithURL(arquivo as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw ErroDeRender.imagem
    }
    let metadados = [kCGImagePropertyDPIWidth: 72 * escala, kCGImagePropertyDPIHeight: 72 * escala]
    CGImageDestinationAddImage(destino, imagem, metadados as CFDictionary)
    guard CGImageDestinationFinalize(destino) else { throw ErroDeRender.imagem }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Informe a pasta de saída do fundo.\n".utf8))
    exit(2)
}
let pasta = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
do {
    try gravar(escala: 1, em: pasta.appendingPathComponent("fundo.png"))
    try gravar(escala: 2, em: pasta.appendingPathComponent("fundo@2x.png"))
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
