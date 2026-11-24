import CoreGraphics
import Foundation

/// Cotas nominais do arquivo gerado junto aos STLs. A face tem origem no topo esquerdo,
/// com X para a direita, Y para baixo e todas as medidas em milímetros.
struct Geometria: Decodable {
    let unidade: String
    let corpo: Corpo
    let rebaixo: Rebaixo
    let adesivo: Adesivo
    let seta: Seta

    struct Raios: Decodable {
        let superiorEsquerdo: CGFloat
        let superiorDireito: CGFloat
        let inferiorDireito: CGFloat
        let inferiorEsquerdo: CGFloat

        fileprivate func escalados(por fator: CGFloat) -> Raios {
            Raios(
                superiorEsquerdo: superiorEsquerdo * fator,
                superiorDireito: superiorDireito * fator,
                inferiorDireito: inferiorDireito * fator,
                inferiorEsquerdo: inferiorEsquerdo * fator
            )
        }
    }

    struct Corpo: Decodable {
        let largura: CGFloat
        let altura: CGFloat
        let espessura: CGFloat
        let raios: Raios

        func contorno(em retangulo: CGRect) -> CGPath {
            let escala = min(retangulo.width / largura, retangulo.height / altura)
            return caminhoArredondado(em: retangulo, raios: raios.escalados(por: escala), chanfro: 0)
        }
    }

    /// Contorno do adesivo já com a folga de encaixe em relação ao rebaixo.
    struct Adesivo: Decodable {
        let x: CGFloat
        let y: CGFloat
        let largura: CGFloat
        let altura: CGFloat
        let raio: CGFloat
        let chanfro: CGFloat

        init(x: CGFloat = 0, y: CGFloat = 0, largura: CGFloat, altura: CGFloat, raio: CGFloat, chanfro: CGFloat) {
            self.x = x
            self.y = y
            self.largura = largura
            self.altura = altura
            self.raio = raio
            self.chanfro = chanfro
        }

        func contorno(em retangulo: CGRect) -> CGPath {
            let escala = min(retangulo.width / largura, retangulo.height / altura)
            return caminhoArredondado(em: retangulo, raio: raio * escala, chanfro: chanfro * escala)
        }
    }

    struct Rebaixo: Decodable {
        let x: CGFloat
        let y: CGFloat
        let largura: CGFloat
        let altura: CGFloat
        let raio: CGFloat
        let chanfro: CGFloat
        let profundidade: CGFloat

        func contorno(em retangulo: CGRect) -> CGPath {
            let escala = min(retangulo.width / largura, retangulo.height / altura)
            return caminhoArredondado(em: retangulo, raio: raio * escala, chanfro: chanfro * escala)
        }
    }

    struct Seta: Decodable {
        let centroX: CGFloat
        let topo: CGFloat
        let largura: CGFloat
        let altura: CGFloat
        let profundidade: CGFloat
    }

    static func carregar(bundle: Bundle = .main) throws -> Geometria {
        guard let url = bundle.url(forResource: "dimensoes", withExtension: "json") else {
            throw ErroGeometria.arquivoAusente
        }
        let geometria = try JSONDecoder().decode(Geometria.self, from: Data(contentsOf: url))
        try geometria.validarCotas()
        return geometria
    }

    /// A escala acompanha o STL no plano XY. As cotas Z mantêm a espessura da peça e o
    /// rebaixo adequado à película vinílica, independentemente da largura escolhida.
    func comLargura(_ largura: CGFloat) -> Geometria {
        let fator = largura / corpo.largura
        guard fator.isFinite, fator > 0, (corpo.altura * fator).isFinite else { return self }
        return Geometria(
            unidade: unidade,
            corpo: Corpo(
                largura: largura, altura: corpo.altura * fator,
                espessura: corpo.espessura, raios: corpo.raios.escalados(por: fator)
            ),
            rebaixo: Rebaixo(
                x: rebaixo.x * fator, y: rebaixo.y * fator,
                largura: rebaixo.largura * fator, altura: rebaixo.altura * fator,
                raio: rebaixo.raio * fator, chanfro: rebaixo.chanfro * fator,
                profundidade: rebaixo.profundidade
            ),
            adesivo: Adesivo(
                x: adesivo.x * fator, y: adesivo.y * fator,
                largura: adesivo.largura * fator, altura: adesivo.altura * fator,
                raio: adesivo.raio * fator, chanfro: adesivo.chanfro * fator
            ),
            seta: Seta(
                centroX: seta.centroX * fator, topo: seta.topo * fator,
                largura: seta.largura * fator, altura: seta.altura * fator,
                profundidade: seta.profundidade
            )
        )
    }

    private func validarCotas() throws {
        let comprimentos = [
            corpo.largura, corpo.altura, corpo.espessura,
            rebaixo.largura, rebaixo.altura, rebaixo.profundidade,
            adesivo.largura, adesivo.altura,
            seta.largura, seta.altura, seta.profundidade,
        ]
        guard unidade == "mm", comprimentos.allSatisfy({ $0.isFinite && $0 > 0 }),
              rebaixo.profundidade < corpo.espessura,
              seta.profundidade < corpo.espessura else { throw ErroGeometria.cotasInvalidas }

        let posicoes = [rebaixo.x, rebaixo.y, adesivo.x, adesivo.y, seta.centroX, seta.topo]
        guard posicoes.allSatisfy(\.isFinite) else { throw ErroGeometria.cotasInvalidas }

        let face = CGRect(x: 0, y: 0, width: corpo.largura, height: corpo.altura)
        let caixaRebaixo = CGRect(x: rebaixo.x, y: rebaixo.y, width: rebaixo.largura, height: rebaixo.altura)
        let caixaAdesivo = CGRect(x: adesivo.x, y: adesivo.y, width: adesivo.largura, height: adesivo.altura)
        let caixaSeta = CGRect(
            x: seta.centroX - seta.largura / 2, y: seta.topo, width: seta.largura, height: seta.altura
        )
        guard face.contains(caixaRebaixo), caixaRebaixo.contains(caixaAdesivo),
              face.contains(caixaSeta) else { throw ErroGeometria.cotasInvalidas }

        // Os cantos precisam caber no retângulo. Assim a prévia nunca corrige em silêncio
        // um raio ou chanfro que deveria corresponder à geometria do STL.
        let limite = min(corpo.largura, corpo.altura) / 2
        let raios = [
            corpo.raios.superiorEsquerdo, corpo.raios.superiorDireito,
            corpo.raios.inferiorDireito, corpo.raios.inferiorEsquerdo,
        ]
        guard raios.allSatisfy({ (0...limite).contains($0) }),
              cantoValido(raio: rebaixo.raio, chanfro: rebaixo.chanfro, menorLado: min(rebaixo.largura, rebaixo.altura)),
              cantoValido(raio: adesivo.raio, chanfro: adesivo.chanfro, menorLado: min(adesivo.largura, adesivo.altura))
        else { throw ErroGeometria.cotasInvalidas }
    }

    private func cantoValido(raio: CGFloat, chanfro: CGFloat, menorLado: CGFloat) -> Bool {
        (0...(menorLado / 2)).contains(raio) && (0...(menorLado - raio)).contains(chanfro)
    }
}

private enum ErroGeometria: LocalizedError {
    case arquivoAusente
    case cotasInvalidas

    var errorDescription: String? {
        switch self {
        case .arquivoAusente: return "O arquivo de dimensões do Cartrest não foi encontrado."
        case .cotasInvalidas: return "O arquivo de dimensões do Cartrest contém cotas inválidas."
        }
    }
}

/// Contorno de corte compartilhado pela tela e pelo PDF. A origem fica no topo esquerdo
/// e o chanfro positivo substitui o arredondamento no canto inferior esquerdo.
func contorno(em retangulo: CGRect, raio: CGFloat, chanfro: CGFloat) -> CGPath {
    caminhoArredondado(em: retangulo, raio: raio, chanfro: chanfro)
}

private func caminhoArredondado(em retangulo: CGRect, raio: CGFloat, chanfro: CGFloat) -> CGPath {
    let raios = Geometria.Raios(
        superiorEsquerdo: raio, superiorDireito: raio,
        inferiorDireito: raio, inferiorEsquerdo: raio
    )
    return caminhoArredondado(em: retangulo, raios: raios, chanfro: chanfro)
}

private func caminhoArredondado(em retangulo: CGRect, raios: Geometria.Raios, chanfro: CGFloat) -> CGPath {
    let caminho = CGMutablePath()
    guard !retangulo.isEmpty, !retangulo.isInfinite,
          retangulo.minX.isFinite, retangulo.minY.isFinite,
          retangulo.maxX.isFinite, retangulo.maxY.isFinite else { return caminho }

    let esquerda = retangulo.minX
    let direita = retangulo.maxX
    let topo = retangulo.minY
    let base = retangulo.maxY
    let raioMaximo = min(retangulo.width, retangulo.height) / 2
    func limitar(_ valor: CGFloat, a teto: CGFloat) -> CGFloat {
        valor.isFinite ? min(max(valor, 0), teto) : 0
    }
    let superiorEsquerdo = limitar(raios.superiorEsquerdo, a: raioMaximo)
    let superiorDireito = limitar(raios.superiorDireito, a: raioMaximo)
    let inferiorDireito = limitar(raios.inferiorDireito, a: raioMaximo)
    let inferiorEsquerdo = limitar(raios.inferiorEsquerdo, a: raioMaximo)
    let chanfroMaximo = min(retangulo.width - inferiorDireito, retangulo.height - superiorEsquerdo)
    let chanfroValido = limitar(chanfro, a: chanfroMaximo)

    func virar(em canto: CGPoint, rumo: CGPoint, raio: CGFloat) {
        if raio > 0 {
            caminho.addArc(tangent1End: canto, tangent2End: rumo, radius: raio)
        } else {
            caminho.addLine(to: canto)
        }
    }

    caminho.move(to: CGPoint(x: esquerda + superiorEsquerdo, y: topo))
    virar(em: CGPoint(x: direita, y: topo), rumo: CGPoint(x: direita, y: base), raio: superiorDireito)
    virar(em: CGPoint(x: direita, y: base), rumo: CGPoint(x: esquerda, y: base), raio: inferiorDireito)
    if chanfroValido > 0 {
        caminho.addLine(to: CGPoint(x: esquerda + chanfroValido, y: base))
        caminho.addLine(to: CGPoint(x: esquerda, y: base - chanfroValido))
    } else {
        virar(em: CGPoint(x: esquerda, y: base), rumo: CGPoint(x: esquerda, y: topo), raio: inferiorEsquerdo)
    }
    virar(em: CGPoint(x: esquerda, y: topo), rumo: CGPoint(x: direita, y: topo), raio: superiorEsquerdo)
    caminho.closeSubpath()
    return caminho
}
