import SwiftUI

/// Desenha a peça, o corte ou a folha em escala de tela.
/// As posições físicas vêm da geometria do modelo e do mesmo motor que gera os arquivos.
struct PranchetaCartrest: View {
    let modo: ModoPrevia
    let modelo: Geometria
    let adesivo: Geometria.Adesivo
    let opcoes: OpcoesArte?
    let artes: [OpcoesArte]
    let posicoes: [PosicaoA4]
    let pagina: Int
    let totalPaginas: Int
    let reservaInferior: CGFloat

    private let fundo = Color(red: 0.075, green: 0.20, blue: 0.16)
    private let linha = Color(red: 0.68, green: 0.82, blue: 0.74)

    var body: some View {
        Canvas { contexto, tamanho in
            let luz = Color(red: 0.105, green: 0.24, blue: 0.19)
            contexto.fill(Path(CGRect(origin: .zero, size: tamanho)), with: .linearGradient(
                Gradient(colors: [luz, fundo, Color(red: 0.049, green: 0.15, blue: 0.13)]),
                startPoint: .zero, endPoint: CGPoint(x: tamanho.width, y: tamanho.height)
            ))
            // O visor flutua sobre o tapete. A reserva mantém a peça e o papel inteiros.
            let areaLivre = CGSize(width: tamanho.width, height: max(1, tamanho.height - reservaInferior))
            switch modo {
            case .peca:
                desenharPeca(contexto, tamanho: tamanho, areaLivre: areaLivre)
            case .corte:
                if let opcoes {
                    desenharCorte(contexto, opcoes: opcoes, tamanho: tamanho, areaLivre: areaLivre)
                } else {
                    grade(contexto, tamanho: tamanho, de: .zero, escala: 4)
                }
            case .folha:
                desenharFolha(contexto, tamanho: areaLivre)
            case .tridimensional:
                // Na vista orbitável, a malha 3D ocupa o plano acima do tapete.
                let centro = CGPoint(x: tamanho.width / 2, y: areaLivre.height / 2)
                grade(contexto, tamanho: tamanho, de: centro, escala: 4.5)
            }
        }
        .accessibilityLabel(rotulo)
        .accessibilityAddTraits(.isImage)
    }

    private var rotulo: String {
        switch modo {
        case .peca: "Prévia do adesivo aplicado ao porta-copos"
        case .corte: "Prévia da linha de corte e da sangria"
        case .tridimensional: "Tapete da prévia tridimensional"
        case .folha:
            totalPaginas > 0 ? "Página \(pagina) de \(totalPaginas), com \(posicoes.count) adesivos" : "Folha A4 vazia"
        }
    }

    // Aplica uma única escala aos dois eixos. O resultado mede pontos de tela por milímetro.
    private func posicionar(_ tamanho: CGSize, na area: CGSize, margem: CGSize) -> (CGRect, CGFloat) {
        let larguraUtil = max(1, area.width - margem.width)
        let alturaUtil = max(1, area.height - margem.height)
        let escala = min(larguraUtil / tamanho.width, alturaUtil / tamanho.height)
        let largura = tamanho.width * escala
        let altura = tamanho.height * escala
        let x = (area.width - largura) / 2
        let y = (area.height - altura) / 2
        return (CGRect(x: x, y: y, width: largura, height: altura), escala)
    }

    // A origem fica no canto superior esquerdo, com Y crescente para baixo.
    // O motor fornece as posições em mm nesse mesmo referencial.
    private func mapa(_ medidas: CGRect, aPartirDe quadro: CGRect, escala: CGFloat) -> CGRect {
        CGRect(x: quadro.minX + medidas.minX * escala, y: quadro.minY + medidas.minY * escala,
               width: medidas.width * escala, height: medidas.height * escala)
    }

    // Vincula a origem da grade à peça ou à arte, para a régua de fundo acompanhar a escala.
    private func grade(_ contexto: GraphicsContext, tamanho: CGSize, de origem: CGPoint, escala: CGFloat) {
        for (passo, opacidade) in [(5.0, 0.10), (20.0, 0.17)] {
            let intervalo = passo * escala
            guard intervalo >= 3 else { continue }
            var guia = Path()
            for x in stride(from: origem.x.truncatingRemainder(dividingBy: intervalo), to: tamanho.width, by: intervalo) {
                guia.move(to: CGPoint(x: x, y: 0))
                guia.addLine(to: CGPoint(x: x, y: tamanho.height))
            }
            for y in stride(from: origem.y.truncatingRemainder(dividingBy: intervalo), to: tamanho.height, by: intervalo) {
                guia.move(to: CGPoint(x: 0, y: y))
                guia.addLine(to: CGPoint(x: tamanho.width, y: y))
            }
            contexto.stroke(guia, with: .color(linha.opacity(opacidade)), lineWidth: 0.65)
        }
    }

    private func desenharPeca(_ ctx: GraphicsContext, tamanho: CGSize, areaLivre: CGSize) {
        let corpo = modelo.corpo
        let (quadro, escala) = posicionar(
            CGSize(width: corpo.largura, height: corpo.altura), na: areaLivre,
            margem: CGSize(width: 112, height: 66)
        )
        grade(ctx, tamanho: tamanho, de: quadro.origin, escala: escala)
        let molde = Path(corpo.contorno(em: quadro))
        var sombra = ctx
        sombra.addFilter(.shadow(color: .black.opacity(0.52), radius: 12, x: 0, y: 9))
        sombra.fill(molde, with: .color(Color(red: 0.11, green: 0.13, blue: 0.14)))
        ctx.fill(molde, with: .linearGradient(
            Gradient(colors: [Color(red: 0.32, green: 0.36, blue: 0.37),
                              Color(red: 0.13, green: 0.17, blue: 0.19)]),
            startPoint: quadro.origin, endPoint: CGPoint(x: quadro.maxX, y: quadro.maxY)
        ))
        ctx.stroke(molde, with: .color(.white.opacity(0.26)), lineWidth: 1)
        let rebaixo = modelo.rebaixo
        let caixaRebaixo = mapa(CGRect(x: rebaixo.x, y: rebaixo.y, width: rebaixo.largura, height: rebaixo.altura),
                               aPartirDe: quadro, escala: escala)
        let cavidade = Path(rebaixo.contorno(em: caixaRebaixo))
        ctx.fill(cavidade, with: .color(.black.opacity(0.63)))
        ctx.stroke(cavidade, with: .color(.white.opacity(0.25)), lineWidth: 0.6)
        // A imagem ocupa a área com sangria. Na peça, a máscara recorta o vinil
        // pela medida final do adesivo dentro do rebaixo.
        if let opcoes {
            let arte = mapa(CGRect(x: adesivo.x - opcoes.sangriaMm, y: adesivo.y - opcoes.sangriaMm,
                                   width: adesivo.largura + 2 * opcoes.sangriaMm,
                                   height: adesivo.altura + 2 * opcoes.sangriaMm),
                            aPartirDe: quadro, escala: escala)
            desenharArte(opcoes, no: arte, recortar: true, ctx: ctx)
        }

        let seta = modelo.seta
        var triangulo = Path()
        triangulo.move(to: CGPoint(x: quadro.minX + (seta.centroX - seta.largura / 2) * escala,
                                  y: quadro.minY + seta.topo * escala))
        triangulo.addLine(to: CGPoint(x: quadro.minX + (seta.centroX + seta.largura / 2) * escala,
                                      y: quadro.minY + seta.topo * escala))
        triangulo.addLine(to: CGPoint(x: quadro.minX + seta.centroX * escala,
                                      y: quadro.minY + (seta.topo + seta.altura) * escala))
        triangulo.closeSubpath()
        ctx.fill(triangulo, with: .color(.black.opacity(0.25)))
        ctx.stroke(triangulo, with: .color(.white.opacity(0.28)), lineWidth: 0.65)
    }

    private func desenharCorte(_ ctx: GraphicsContext, opcoes: OpcoesArte, tamanho: CGSize, areaLivre: CGSize) {
        let saida = Exportador.medir(opcoes)
        let (quadro, escala) = posicionar(
            CGSize(width: saida.larguraArteMm, height: saida.alturaArteMm), na: areaLivre,
            margem: CGSize(width: 104, height: 74)
        )
        grade(ctx, tamanho: tamanho, de: quadro.origin, escala: escala)
        desenharArte(opcoes, no: quadro, recortar: false, ctx: ctx)
        let corte = quadro.insetBy(dx: opcoes.sangriaMm * escala, dy: opcoes.sangriaMm * escala)
        var fora = Path(quadro)
        fora.addPath(Path(adesivo.contorno(em: corte)))
        // A regra par-ímpar escurece o trecho entre a borda da sangria e a linha de corte.
        ctx.fill(fora, with: .color(fundo.opacity(0.42)), style: FillStyle(eoFill: true))
        linhaDeCorte(opcoes, corte: corte, escala: escala, contexto: ctx)
    }

    private func desenharFolha(_ ctx: GraphicsContext, tamanho: CGSize) {
        // A folha usa as mesmas dimensões, posições e régua do PDF.
        let (folha, escala) = posicionar(Exportador.tamanhoFolha, na: tamanho,
                                         margem: CGSize(width: 28, height: 30))
        var sombra = ctx
        sombra.addFilter(.shadow(color: .black.opacity(0.50), radius: 10, x: 0, y: 8))
        sombra.fill(Path(folha), with: .color(.white))
        ctx.draw(Text("Cartrest").font(.system(size: 4.7 * escala, weight: .semibold)).foregroundColor(.black),
                 at: CGPoint(x: folha.minX + 10 * escala, y: folha.minY + 9 * escala),
                 anchor: .topLeading)
        for posicao in posicoes where artes.indices.contains(posicao.indiceArte) {
            let item = artes[posicao.indiceArte]
            let quadro = mapa(posicao.quadro, aPartirDe: folha, escala: escala)
            desenharArte(item, no: quadro, recortar: false, ctx: ctx)
            let corte = quadro.insetBy(dx: item.sangriaMm * escala, dy: item.sangriaMm * escala)
            linhaDeCorte(item, corte: corte, escala: escala, contexto: ctx)
        }
        var regua = Path()
        let origem = Exportador.origemRegua
        let largura = Exportador.larguraRegua
        let inicio = CGPoint(x: folha.minX + origem.x * escala, y: folha.minY + origem.y * escala)
        regua.move(to: inicio)
        regua.addLine(to: CGPoint(x: inicio.x + largura * escala, y: inicio.y))
        for marca in [0, largura / 2, largura] {
            regua.move(to: CGPoint(x: inicio.x + marca * escala, y: inicio.y - 1.5 * escala))
            regua.addLine(to: CGPoint(x: inicio.x + marca * escala, y: inicio.y + 1.5 * escala))
        }
        ctx.stroke(regua, with: .color(.black), lineWidth: 0.55)
        let rotuloRegua = Double(largura).formatted(.number.precision(.fractionLength(0)))
        ctx.draw(Text("\(rotuloRegua) mm").font(.system(size: 2.8 * escala)).foregroundColor(.black),
                 at: CGPoint(x: inicio.x + largura * escala, y: inicio.y + 3 * escala),
                 anchor: .topTrailing)
    }

    private func desenharArte(_ item: OpcoesArte, no quadro: CGRect, recortar: Bool, ctx: GraphicsContext) {
        let escala = quadro.width / (item.larguraMm + 2 * item.sangriaMm)
        let sangria = item.sangriaMm * escala
        let area = quadro.insetBy(dx: sangria, dy: sangria)
        var recorte = ctx
        recorte.clip(to: recortar
                     ? Path(contorno(em: area, raio: item.raioMm * escala, chanfro: item.chanfroMm * escala))
                     : Path(quadro))
        // O fundo branco sob transparências tem a mesma função na prévia e na impressão.
        recorte.fill(Path(quadro), with: .color(.white))
        let desenho = mapa(Exportador.quadroImagem(item), aPartirDe: quadro, escala: escala)
        recorte.draw(Image(decorative: item.imagem, scale: 1).interpolation(.high), in: desenho)
    }

    private func linhaDeCorte(_ item: OpcoesArte, corte: CGRect, escala: CGFloat, contexto: GraphicsContext) {
        let linha = Path(contorno(em: corte, raio: item.raioMm * escala, chanfro: item.chanfroMm * escala))
        contexto.stroke(linha, with: .color(.white.opacity(0.95)), lineWidth: 1.25)
        contexto.stroke(linha, with: .color(.black.opacity(0.85)),
                        style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))
    }
}
