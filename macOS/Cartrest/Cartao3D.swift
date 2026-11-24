import AppKit
import CoreGraphics
import SceneKit
import SwiftUI

/// Prévia interativa do mesmo sólido que acompanha o aplicativo.
struct Cartao3D: NSViewRepresentable {
    let modelo: Geometria
    let opcoes: OpcoesArte?

    func makeCoordinator() -> CenaCartrest { CenaCartrest() }

    func makeNSView(context: Context) -> VistaCartrest3D {
        let vista = VistaCartrest3D(frame: .zero)
        vista.backgroundColor = .clear
        vista.antialiasingMode = .multisampling4X
        context.coordinator.instalar(em: vista)
        return vista
    }

    func updateNSView(_ vista: VistaCartrest3D, context: Context) {
        context.coordinator.atualizar(modelo: modelo, opcoes: opcoes)
    }
}

final class VistaCartrest3D: SCNView {
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { allowsCameraControl }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard allowsCameraControl, let tecla = event.charactersIgnoringModifiers else {
            return super.keyDown(with: event)
        }
        switch tecla {
        case "\u{F702}": defaultCameraController.rotateBy(x: -8, y: 0) // Seta esquerda.
        case "\u{F703}": defaultCameraController.rotateBy(x: 8, y: 0)  // Seta direita.
        case "\u{F700}": defaultCameraController.rotateBy(x: 0, y: -8) // Seta para cima.
        case "\u{F701}": defaultCameraController.rotateBy(x: 0, y: 8)  // Seta para baixo.
        case "+", "=", "-":
            if let camera = pointOfView?.camera {
                let fator: CGFloat = tecla == "-" ? 1.1 : 0.9
                camera.fieldOfView = min(70, max(12, camera.fieldOfView * fator))
            }
        default:
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class CenaCartrest {
    let cena = SCNScene()
    let camera = SCNNode()
    private let corpo = SCNNode()
    private let adesivo = SCNNode()
    private let plano = SCNPlane()
    private let materialAdesivo = SCNMaterial()
    private let tamanhoOriginal: CGSize?
    private var tamanhoAtual: CGSize?
    private var texturaAtual: ChaveTextura?

    init(bundle: Bundle = .main) {
        cena.background.contents = NSColor.clear
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 36
        camera.camera?.zNear = 1
        camera.camera?.zFar = 2_000
        cena.rootNode.addChildNode(camera)

        guard let url = bundle.url(forResource: "cartrest-ds-100mm", withExtension: "stl"),
              let dados = try? Data(contentsOf: url),
              let malha = MalhaSTL(dados: dados)
        else {
            tamanhoOriginal = nil
            return
        }

        tamanhoOriginal = malha.tamanho
        let plastico = SCNMaterial()
        plastico.lightingModel = .blinn
        plastico.diffuse.contents = NSColor(srgbRed: 0.24, green: 0.29, blue: 0.30, alpha: 1)
        plastico.specular.contents = NSColor(white: 0.19, alpha: 1)
        plastico.shininess = 0.24
        malha.geometria.firstMaterial = plastico
        corpo.geometry = malha.geometria
        cena.rootNode.addChildNode(corpo)

        materialAdesivo.lightingModel = .constant
        materialAdesivo.blendMode = .alpha
        materialAdesivo.writesToDepthBuffer = false
        plano.firstMaterial = materialAdesivo
        adesivo.geometry = plano
        adesivo.isHidden = true
        cena.rootNode.addChildNode(adesivo)

        adicionarLuz(.ambient, intensidade: 500)
        adicionarLuz(.directional, intensidade: 900, posicao: SCNVector3(-80, 140, 200))
        adicionarLuz(.directional, intensidade: 380, posicao: SCNVector3(140, -100, -170))
    }

    func instalar(em vista: VistaCartrest3D) {
        guard tamanhoOriginal != nil else {
            let aviso = NSTextField(wrappingLabelWithString: "O modelo do cartucho está indisponível para a prévia 3D.")
            aviso.textColor = .white
            aviso.alignment = .center
            aviso.translatesAutoresizingMaskIntoConstraints = false
            vista.addSubview(aviso)
            NSLayoutConstraint.activate([
                aviso.centerXAnchor.constraint(equalTo: vista.centerXAnchor),
                aviso.centerYAnchor.constraint(equalTo: vista.centerYAnchor),
                aviso.leadingAnchor.constraint(greaterThanOrEqualTo: vista.leadingAnchor, constant: 16),
                aviso.trailingAnchor.constraint(lessThanOrEqualTo: vista.trailingAnchor, constant: -16),
            ])
            return
        }

        vista.scene = cena
        vista.pointOfView = camera
        vista.allowsCameraControl = true
        vista.cameraControlConfiguration.allowsTranslation = false
        vista.cameraControlConfiguration.autoSwitchToFreeCamera = false
        vista.defaultCameraController.pointOfView = camera
        vista.defaultCameraController.target = SCNVector3Zero
        vista.defaultCameraController.interactionMode = .orbitArcball
        vista.setAccessibilityElement(true)
        vista.setAccessibilityLabel("Prévia 3D do porta-copos")
        vista.setAccessibilityHelp("Arraste ou use as setas para girar. Use a rolagem ou as teclas mais e menos para aproximar.")
    }

    func atualizar(modelo: Geometria, opcoes: OpcoesArte?) {
        guard let tamanhoOriginal else { return }
        let tamanho = CGSize(width: modelo.corpo.largura, height: modelo.corpo.altura)
        let maiorLado = max(tamanho.width, tamanho.height)
        if tamanhoAtual != tamanho {
            // X e Y acompanham o tamanho escolhido. O eixo Z conserva a espessura e os rebaixos do STL.
            corpo.scale = SCNVector3(tamanho.width / tamanhoOriginal.width, tamanho.height / tamanhoOriginal.height, 1)
            corpo.position = SCNVector3(-tamanho.width / 2, -tamanho.height / 2, -modelo.corpo.espessura / 2)

            if let anterior = tamanhoAtual {
                // Redimensionar preserva o ângulo e a aproximação relativa de quem está inspecionando.
                let fator = maiorLado / max(anterior.width, anterior.height)
                let posicao = camera.position
                camera.position = SCNVector3(posicao.x * fator, posicao.y * fator, posicao.z * fator)
            } else {
                camera.position = SCNVector3(maiorLado * 0.49, -maiorLado * 0.57, maiorLado * 2.02)
                camera.look(at: SCNVector3Zero)
            }
            tamanhoAtual = tamanho
        }

        let corte = modelo.adesivo
        plano.width = corte.largura
        plano.height = corte.altura
        adesivo.position = SCNVector3(
            corte.x + corte.largura / 2 - tamanho.width / 2,
            tamanho.height / 2 - corte.y - corte.altura / 2,
            // Um pequeno afastamento do fundo do rebaixo evita sobreposição de pixels.
            modelo.corpo.espessura / 2 - modelo.rebaixo.profundidade + 0.025
        )

        guard let opcoes else {
            adesivo.isHidden = true
            materialAdesivo.diffuse.contents = nil
            texturaAtual = nil
            return
        }
        let chave = ChaveTextura(opcoes)
        guard chave != texturaAtual else { return }
        let imagem = texturaDeCorte(opcoes)
        materialAdesivo.diffuse.contents = imagem.map { NSImage(cgImage: $0, size: .zero) }
        adesivo.isHidden = imagem == nil
        texturaAtual = chave
    }

    private func adicionarLuz(_ tipo: SCNLight.LightType, intensidade: CGFloat, posicao: SCNVector3 = SCNVector3Zero) {
        let no = SCNNode()
        let luz = SCNLight()
        luz.type = tipo
        luz.intensity = intensidade
        no.light = luz
        cena.rootNode.addChildNode(no)
        if tipo == .directional {
            no.position = posicao
            no.look(at: SCNVector3Zero)
        }
    }
}

private struct ChaveTextura: Equatable {
    let imagem: ObjectIdentifier
    let recorte: [CGFloat]

    init(_ opcoes: OpcoesArte) {
        imagem = ObjectIdentifier(opcoes.imagem)
        recorte = [
            opcoes.larguraMm, opcoes.alturaMm, opcoes.raioMm, opcoes.chanfroMm,
            opcoes.sangriaMm, opcoes.zoom, opcoes.x, opcoes.y,
        ]
    }
}

private func texturaDeCorte(_ opcoes: OpcoesArte) -> CGImage? {
    let largura = opcoes.larguraMm
    let altura = opcoes.alturaMm
    let maiorLado = max(largura, altura)
    guard largura.isFinite, altura.isFinite, largura > 0, altura > 0 else { return nil }

    // A textura é só de visualização. Reaproveita o recorte da exportação em resolução própria.
    let larguraPx = max(1, Int((largura / maiorLado * 1_024).rounded()))
    let alturaPx = max(1, Int((altura / maiorLado * 1_024).rounded()))
    guard let espaco = CGColorSpace(name: CGColorSpace.sRGB),
          let contexto = CGContext(
              data: nil, width: larguraPx, height: alturaPx, bitsPerComponent: 8, bytesPerRow: 0,
              space: espaco, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { return nil }

    let escalaX = CGFloat(larguraPx) / largura
    let escalaY = CGFloat(alturaPx) / altura
    // O Canvas corta de cima para baixo. O bitmap Quartz começa no canto inferior esquerdo.
    var transformacao = CGAffineTransform(a: escalaX, b: 0, c: 0, d: -escalaY, tx: 0, ty: CGFloat(alturaPx))
    let corte = contorno(
        em: CGRect(x: 0, y: 0, width: largura, height: altura), raio: opcoes.raioMm, chanfro: opcoes.chanfroMm
    )
    guard let caminho = corte.copy(using: &transformacao) else { return nil }
    contexto.addPath(caminho)
    contexto.clip()
    contexto.setFillColor(CGColor(gray: 1, alpha: 1))
    contexto.fill(CGRect(x: 0, y: 0, width: larguraPx, height: alturaPx))

    let medidas = Exportador.medir(opcoes)
    let sangria = (medidas.larguraArteMm - largura) / 2
    let imagem = Exportador.quadroImagem(opcoes)
    contexto.interpolationQuality = .high
    contexto.draw(opcoes.imagem, in: CGRect(
        x: (imagem.minX - sangria) * escalaX, y: (altura - imagem.maxY + sangria) * escalaY,
        width: imagem.width * escalaX, height: imagem.height * escalaY
    ))
    return contexto.makeImage()
}

@MainActor
private struct MalhaSTL {
    let geometria: SCNGeometry
    let tamanho: CGSize

    init?(dados: Data) {
        let inicioFacetas = 84
        let bytesPorFaceta = 50
        guard dados.count >= inicioFacetas else { return nil }

        let facetas = dados.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self))) }
        guard facetas > 0, facetas == (dados.count - inicioFacetas) / bytesPorFaceta,
              dados.count == inicioFacetas + facetas * bytesPorFaceta else { return nil }

        // O STL binário guarda normal e três vértices por faceta. Manter os vértices
        // separados preserva as arestas entre a face, o chanfro e a parede do rebaixo.
        var vertices = [SCNVector3]()
        var normais = [SCNVector3]()
        vertices.reserveCapacity(facetas * 3)
        normais.reserveCapacity(facetas * 3)
        let completo = dados.withUnsafeBytes { buffer -> Bool in
            func vetor(no deslocamento: Int) -> SCNVector3? {
                let valores = (0..<3).map { eixo in
                    let bits = buffer.loadUnaligned(fromByteOffset: deslocamento + eixo * 4, as: UInt32.self)
                    return Float(bitPattern: UInt32(littleEndian: bits))
                }
                guard valores.allSatisfy(\.isFinite) else { return nil }
                return SCNVector3(CGFloat(valores[0]), CGFloat(valores[1]), CGFloat(valores[2]))
            }

            for faceta in 0..<facetas {
                let inicio = inicioFacetas + faceta * bytesPorFaceta
                guard let normal = vetor(no: inicio) else { return false }
                for indice in 1...3 {
                    guard let vertice = vetor(no: inicio + indice * 12) else { return false }
                    vertices.append(vertice)
                    normais.append(normal)
                }
            }
            return true
        }
        guard completo else { return nil }
        let fonteVertices = SCNGeometrySource(vertices: vertices)
        let fonteNormais = SCNGeometrySource(normals: normais)
        let triangulos = SCNGeometryElement(indices: vertices.indices.map(UInt32.init), primitiveType: .triangles)
        geometria = SCNGeometry(sources: [fonteVertices, fonteNormais], elements: [triangulos])
        let (minimo, maximo) = geometria.boundingBox
        tamanho = CGSize(width: maximo.x - minimo.x, height: maximo.y - minimo.y)
        guard tamanho.width > 0, tamanho.height > 0 else { return nil }
    }
}
