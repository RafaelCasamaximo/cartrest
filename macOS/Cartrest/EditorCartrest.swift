import Accessibility
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// O alias mantém o property wrapper compatível com SDKs que oferecem uma macro de mesmo nome.
private typealias EstadoDaTela<Valor> = SwiftUI.State<Valor>

enum ModoPrevia: String {
    case peca, corte, folha, tridimensional
}

private enum FormatoArquivo: Sendable {
    case pdf, png

    var extensao: String { self == .pdf ? "pdf" : "png" }
    var tipo: UTType { self == .pdf ? .pdf : .png }
}

private enum OperacaoDoEditor {
    case importacao, exportacao
}

/// Uma projeção dos controles da janela. A prancheta, o rodapé e o salvamento
/// recebem a mesma geometria e a mesma paginação durante cada atualização.
private struct PreparacaoDaFolha {
    let geometria: Geometria
    let adesivo: Geometria.Adesivo
    let erro: String?
    let artes: [OpcoesArte]
    let folhas: [[PosicaoA4]]
    let arteEmEdicao: ArteDaFolha?
    let arteSelecionada: OpcoesArte?
    let medidas: MedidasArte?

    func permiteSalvar(_ formato: FormatoArquivo) -> Bool {
        guard medidas?.podeRasterizar == true else { return false }
        return formato == .png || !folhas.isEmpty
    }
}

struct EditorCartrest: View {
    let modelo: Geometria
    @Environment(\.colorScheme) private var esquema
    @EstadoDaTela private var artes: [ArteDaFolha]
    @EstadoDaTela private var selecao: UUID?
    @EstadoDaTela private var modo: ModoPrevia = .peca
    @EstadoDaTela private var pagina = 0
    @EstadoDaTela private var versaoDaCamera = 0
    @EstadoDaTela private var outroModelo = false
    @EstadoDaTela private var editarMedidas = false
    @EstadoDaTela private var larguraPeca: CGFloat = 100
    @EstadoDaTela private var larguraCustom: CGFloat = 81.8
    @EstadoDaTela private var alturaCustom: CGFloat = 86.4
    @EstadoDaTela private var raioCustom: CGFloat = 3.5
    @EstadoDaTela private var chanfroCustom: CGFloat = 0
    @EstadoDaTela private var sangria: CGFloat = 2
    @EstadoDaTela private var dpi = 300
    @EstadoDaTela private var operacao: OperacaoDoEditor?
    @EstadoDaTela private var estado = ""
    @EstadoDaTela private var erro: String?

    private var aparencia: AparenciaCartrest { AparenciaCartrest(esquema: esquema) }
    private var apenasAmostra: Bool { artes.count == 1 && artes.first?.exemplo == true }
    private var importando: Bool { operacao == .importacao }

    init(modelo: Geometria) {
        self.modelo = modelo
        let amostra = ArteDaFolha.amostra()
        _artes = EstadoDaTela(initialValue: amostra.map { [$0] } ?? [])
        _selecao = EstadoDaTela(initialValue: amostra?.id)
    }

    private var validacao: String? {
        if !outroModelo && !(60...180).contains(larguraPeca) {
            return "Informe uma largura de peça entre 60 e 180 mm."
        }
        if outroModelo {
            let menor = min(larguraCustom, alturaCustom)
            if !(20...160).contains(larguraCustom) || !(20...160).contains(alturaCustom) {
                return "Informe largura e altura entre 20 e 160 mm."
            }
            if !(0...(menor / 2)).contains(raioCustom) || !(0...(menor - raioCustom)).contains(chanfroCustom) {
                return "Reduza o raio ou o chanfro para caber no contorno."
            }
        }
        if !(0...5).contains(sangria) {
            return "Informe uma sangria entre 0 e 5 mm."
        }
        return nil
    }

    private var total: Int {
        artes.reduce(0) { $0 + $1.copias }
    }

    private var preparacaoDaFolha: PreparacaoDaFolha {
        let geometria = modelo.comLargura(larguraPeca)
        let adesivo = outroModelo
            ? Geometria.Adesivo(largura: larguraCustom, altura: alturaCustom,
                                raio: raioCustom, chanfro: chanfroCustom)
            : geometria.adesivo
        let erro = validacao
        let opcoes = erro == nil ? artes.map { arte in
            OpcoesArte(imagem: arte.imagem, larguraMm: adesivo.largura, alturaMm: adesivo.altura,
                       raioMm: adesivo.raio, chanfroMm: adesivo.chanfro, sangriaMm: sangria,
                       dpi: dpi, zoom: arte.zoom, x: arte.x, y: arte.y, copias: arte.copias)
        } : []
        let indiceSelecionado = artes.firstIndex { $0.id == selecao }
        let selecionada = indiceSelecionado.flatMap { indice in
            opcoes.indices.contains(indice) ? opcoes[indice] : nil
        }

        return PreparacaoDaFolha(
            geometria: geometria, adesivo: adesivo, erro: erro, artes: opcoes,
            folhas: Exportador.layout(opcoes), arteEmEdicao: indiceSelecionado.map { artes[$0] },
            arteSelecionada: selecionada,
            medidas: selecionada.map(Exportador.medir)
        )
    }

    var body: some View {
        let preparacao = preparacaoDaFolha
        return HSplitView {
            prancheta(preparacao)
                .frame(minWidth: 470, idealWidth: 820, maxWidth: .infinity, maxHeight: .infinity)
            inspetor(preparacao)
                .frame(minWidth: 320, idealWidth: 342, maxWidth: 420, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 610)
        .background(aparencia.janela)
        .tint(aparencia.destaque)
        .onChange(of: outroModelo) { _, novo in
            if novo && (modo == .peca || modo == .tridimensional) { modo = .corte }
        }
        .onChange(of: preparacao.folhas.count) { _, quantidade in
            pagina = min(pagina, max(0, quantidade - 1))
        }
        .alert("Cartrest", isPresented: Binding(
            get: { erro != nil }, set: { if !$0 { erro = nil } }
        )) {
            Button("OK", role: .cancel) { erro = nil }
        } message: {
            Text(erro ?? "")
        }
    }

    // MARK: - Prancheta

    private func prancheta(_ preparacao: PreparacaoDaFolha) -> some View {
        let folhas = preparacao.folhas
        let paginaExibida = paginaVisivel(folhas)
        let modoDaPrancheta = outroModelo && (modo == .peca || modo == .tridimensional) ? .corte : modo
        return ZStack(alignment: .bottom) {
            PranchetaCartrest(
                modo: modoDaPrancheta,
                modelo: preparacao.erro == nil ? preparacao.geometria : modelo,
                adesivo: preparacao.adesivo, opcoes: preparacao.arteSelecionada,
                artes: preparacao.artes, posicoes: folhas.indices.contains(paginaExibida) ? folhas[paginaExibida] : [],
                pagina: paginaExibida + 1, totalPaginas: folhas.count,
                reservaInferior: VisorMedidas.reservaNaPrancheta
            )
            .accessibilityHidden(modoDaPrancheta == .tridimensional)

            if modoDaPrancheta == .tridimensional {
                Cartao3D(
                    modelo: preparacao.erro == nil ? preparacao.geometria : modelo,
                    opcoes: preparacao.arteSelecionada
                )
                // Só o botão de recentrar recria a câmera enquanto esta vista está ativa.
                .id(versaoDaCamera)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, VisorMedidas.reservaNaPrancheta)
            }

            VisorMedidas(leituras: leiturasDaPrancheta(preparacao))
                .padding(.horizontal, 20)
                .padding(.bottom, VisorMedidas.margemInferior)
                .allowsHitTesting(false)
        }
    }

    private func leiturasDaPrancheta(_ preparacao: PreparacaoDaFolha) -> [VisorMedidas.Leitura] {
        let corpo = preparacao.geometria.corpo
        let adesivo = preparacao.adesivo
        let valido = preparacao.erro == nil
        var leituras: [VisorMedidas.Leitura] = []
        if !outroModelo {
            leituras.append(.init(nome: "Porta-copos", valor: valido ? medida(corpo.largura, corpo.altura) : "—"))
        }
        leituras.append(.init(nome: "Corte do adesivo", valor: valido ? medida(adesivo.largura, adesivo.altura) : "—"))
        let arte = preparacao.medidas.map { medida($0.larguraArteMm, $0.alturaArteMm) } ?? "—"
        leituras.append(.init(nome: "Arte com sangria", valor: arte))
        return leituras
    }

    private func paginaVisivel(_ folhas: [[PosicaoA4]]) -> Int {
        // Mantém o índice válido também na atualização em que o usuário encurta a folha.
        min(pagina, max(0, folhas.count - 1))
    }

    // MARK: - Inspetor

    private func inspetor(_ preparacao: PreparacaoDaFolha) -> some View {
        VStack(spacing: 0) {
            cabecalhoDoInspetor(preparacao.folhas)
            divisorDoInspetor
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    listaDeArtes
                    if let selecionada = preparacao.arteEmEdicao {
                        divisorDoInspetor
                        controlesDeRecorte(selecionada, preparacao: preparacao)
                    }
                    divisorDoInspetor
                    configuracoes(erro: preparacao.erro)
                }
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            divisorDoInspetor
            acoesDeSaida(preparacao)
                .padding(16)
                .background(aparencia.rodape)
        }
        .background(aparencia.inspetor)
    }

    private func cabecalhoDoInspetor(_ folhas: [[PosicaoA4]]) -> some View {
        let atual = paginaVisivel(folhas)
        return VStack(alignment: .leading, spacing: 12) {
            Picker("Modo da prévia", selection: $modo) {
                if !outroModelo { Text("Na peça").tag(ModoPrevia.peca) }
                Text("Corte").tag(ModoPrevia.corte)
                Text("Folha A4").tag(ModoPrevia.folha)
                if !outroModelo { Text("3D").tag(ModoPrevia.tridimensional) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .tint(aparencia.botao)
            .accessibilityLabel("Modo da prévia")

            if modo == .tridimensional {
                HStack(spacing: 8) {
                    Text("Arraste para girar. Role para aproximar.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("Recentralizar", systemImage: "viewfinder") { versaoDaCamera += 1 }
                        .controlSize(.small)
                }
            }

            if modo == .folha && folhas.count > 1 {
                HStack(spacing: 10) {
                    Button("Página anterior", systemImage: "chevron.left") { pagina = atual - 1 }
                        .labelStyle(.iconOnly).disabled(atual == 0)
                    Text("Página \(atual + 1) de \(folhas.count)").font(.subheadline).monospacedDigit()
                    Button("Próxima página", systemImage: "chevron.right") { pagina = atual + 1 }
                        .labelStyle(.iconOnly).disabled(atual + 1 >= folhas.count)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
    }

    private var divisorDoInspetor: some View {
        Rectangle().fill(aparencia.contornoSuave)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var listaDeArtes: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Artes da folha").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(total) \(total == 1 ? "adesivo" : "adesivos")")
                    .font(.caption.weight(.semibold)).foregroundStyle(aparencia.destaque)
                    .monospacedDigit()
            }
            ForEach(artes) { arte in
                HStack(spacing: 4) {
                    Button {
                        selecao = arte.id
                    } label: {
                        HStack(spacing: 9) {
                            Image(decorative: arte.imagem, scale: 1)
                                .resizable().scaledToFill().frame(width: 38, height: 38)
                                .clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(arte.nome).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(arte.exemplo ? "Arte de exemplo" : "\(arte.imagem.width) × \(arte.imagem.height) px")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text("×\(arte.copias)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(aparencia.destaque)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selecao == arte.id ? .isSelected : [])
                    Button {
                        remover(arte.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(importando)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Remover \(arte.nome) da folha")
                    .help("Remover da folha")
                }
                .padding(6)
                .background(
                    selecao == arte.id ? aparencia.selecao : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    if selecao == arte.id {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(aparencia.contornoSelecao, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
            }
            Button("Adicionar imagens…", systemImage: "plus") { importar() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(operacao != nil || (total >= Exportador.limiteCopias && !apenasAmostra))
            if artes.isEmpty {
                Button("Usar arte de exemplo") {
                    if let amostra = ArteDaFolha.amostra() {
                        artes = [amostra]
                        selecao = amostra.id
                    }
                }
                .disabled(importando)
            }
        }
    }

    private func controlesDeRecorte(_ arte: ArteDaFolha, preparacao: PreparacaoDaFolha) -> some View {
        let quadro = preparacao.arteSelecionada.map(Exportador.quadroImagem) ?? .zero
        // O deslocamento só produz efeito quando o recorte tem sobra naquele eixo.
        // A tolerância absorve diferenças submilimétricas de arredondamento em ponto flutuante.
        let ajusteX = preparacao.medidas.map { quadro.width - $0.larguraArteMm > 0.001 } ?? false
        let ajusteY = preparacao.medidas.map { quadro.height - $0.alturaArteMm > 0.001 } ?? false
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Enquadramento").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Restaurar") {
                    atualizar(arte.id) {
                        $0.zoom = 1
                        $0.x = 0
                        $0.y = 0
                    }
                }
                .disabled(arte.zoom == 1 && arte.x == 0 && arte.y == 0)
            }
            HStack(spacing: 8) {
                Text("Zoom").frame(width: 66, alignment: .leading)
                Slider(value: vinculo(arte, \.zoom), in: 1...3.5)
                    .accessibilityLabel("Zoom")
                    .accessibilityValue("\(Int((arte.zoom * 100).rounded())) por cento")
                Text("\(Int((arte.zoom * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            eixo("Horizontal", valor: vinculo(arte, \.x), habilitado: ajusteX)
            eixo("Vertical", valor: vinculo(arte, \.y), habilitado: ajusteY)
            // A arte pode usar as vagas livres mais as cópias que já ocupa.
            let limiteDaArte = max(1, Exportador.limiteCopias - total + arte.copias)
            Stepper(value: vinculo(arte, \.copias), in: 1...limiteDaArte) {
                HStack {
                    Text("Cópias desta arte")
                    Text("\(arte.copias)").monospacedDigit()
                }
            }
            .disabled(importando)
            .accessibilityLabel("Cópias desta arte")
            .accessibilityValue("\(arte.copias)")
        }
    }

    private func eixo(_ titulo: String, valor: Binding<CGFloat>, habilitado: Bool) -> some View {
        HStack(spacing: 8) {
            Text(titulo).frame(width: 66, alignment: .leading)
            Slider(value: valor, in: -1...1)
                .accessibilityLabel(titulo)
                .disabled(!habilitado)
        }
        .help(habilitado ? "Deslocar o enquadramento" : "Aumente o zoom para deslocar neste eixo")
    }

    private func configuracoes(erro: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Impressão").font(.headline).accessibilityAddTraits(.isHeader)
            Picker("Resolução", selection: $dpi) {
                Text("150 dpi").tag(150)
                Text("300 dpi").tag(300)
                Text("600 dpi").tag(600)
            }
            campo("Sangria (mm)", valor: $sangria)
            DisclosureGroup("Medidas do modelo", isExpanded: $editarMedidas) {
                VStack(alignment: .leading, spacing: 9) {
                    Picker("Modelo", selection: $outroModelo) {
                        Text("Cartrest").tag(false)
                        Text("Outro rebaixo").tag(true)
                    }
                    if outroModelo {
                        campo("Largura (mm)", valor: $larguraCustom)
                        campo("Altura (mm)", valor: $alturaCustom)
                        campo("Raio (mm)", valor: $raioCustom)
                        campo("Chanfro inferior esquerdo (mm)", valor: $chanfroCustom)
                    } else {
                        campo("Largura da peça (mm)", valor: $larguraPeca)
                        Text("No fatiador, ajuste X e Y para \(decimal(larguraPeca / modelo.corpo.largura * 100))% e deixe Z em 100%.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            }
            if let erro {
                Text(erro).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func acoesDeSaida(_ preparacao: PreparacaoDaFolha) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let medidas = preparacao.medidas {
                let n = preparacao.folhas.count
                Text("\(medidas.copiasPorPagina) por folha · \(n) \(n == 1 ? "página" : "páginas") A4")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(aparencia.destaque)
                Text("\(medidas.larguraPx) × \(medidas.alturaPx) px por arte com sangria")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                if !medidas.podeRasterizar {
                    Text("Reduza a resolução para exportar esta arte.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            HStack(spacing: 9) {
                Button("Salvar PDF A4…", systemImage: "doc") { salvar(.pdf, preparacao: preparacao) }
                    .buttonStyle(.borderedProminent)
                    .tint(aparencia.botao)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(operacao != nil || !preparacao.permiteSalvar(.pdf))
                    .help("Exporta as artes e as cópias da folha")
                Button("Salvar PNG…") { salvar(.png, preparacao: preparacao) }
                    .disabled(operacao != nil || !preparacao.permiteSalvar(.png))
                    .help("Exporta a arte selecionada com sangria")
                if operacao != nil {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel(estado)
                }
            }
            .controlSize(.large)
            Text(estado.isEmpty ? "Imprima o PDF em tamanho real (100%)." : estado)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Campos e vínculos de edição

    private func campo(_ titulo: String, valor: Binding<CGFloat>) -> some View {
        let numero = Binding<Double>(
            get: { Double(valor.wrappedValue) },
            set: { valor.wrappedValue = CGFloat($0) }
        )
        return LabeledContent(titulo) {
            TextField(titulo, value: numero,
                      format: .number.precision(.fractionLength(0...2)).locale(Locale(identifier: "pt_BR")))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 76)
        }
    }

    private func decimal(_ n: CGFloat) -> String {
        Double(n).formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "pt_BR")))
    }

    private func medida(_ largura: CGFloat, _ altura: CGFloat) -> String {
        "\(decimal(largura)) × \(decimal(altura)) mm"
    }

    // O vínculo busca a arte pelo identificador a cada acesso. O índice da lista
    // pode mudar enquanto a tela anterior ainda está sendo desmontada pelo SwiftUI.
    private func vinculo<T>(_ arte: ArteDaFolha, _ valor: WritableKeyPath<ArteDaFolha, T>) -> Binding<T> {
        Binding(
            get: { artes.first { $0.id == arte.id }?[keyPath: valor] ?? arte[keyPath: valor] },
            set: { novo in atualizar(arte.id) { $0[keyPath: valor] = novo } }
        )
    }

    private func atualizar(_ id: UUID, _ alterar: (inout ArteDaFolha) -> Void) {
        if let indice = artes.firstIndex(where: { $0.id == id }) { alterar(&artes[indice]) }
    }

    private func remover(_ id: UUID) {
        guard !importando else { return }
        guard let indice = artes.firstIndex(where: { $0.id == id }) else { return }
        artes.remove(at: indice)
        if selecao == id {
            selecao = artes.isEmpty ? nil : artes[min(indice, artes.count - 1)].id
        }
        if operacao == nil { estado = "" }
    }

    // MARK: - Importação e saída de arquivos

    private func importar() {
        guard operacao == nil else { return }
        let painel = NSOpenPanel()
        painel.title = "Adicionar imagens"
        painel.prompt = "Adicionar"
        painel.canChooseDirectories = false
        painel.allowsMultipleSelection = true
        painel.allowedContentTypes = [.image]
        guard painel.runModal() == .OK else { return }

        let urls = painel.urls
        let substituirAmostra = apenasAmostra
        let limite = Exportador.limiteCopias
        let vagas = limite - (substituirAmostra ? 0 : total)
        operacao = .importacao
        estado = "Carregando imagens…"

        // O painel roda na interface. A decodificação do lote usa apenas valores
        // capturados e devolve o resultado antes de atualizar a seleção da janela.
        Task {
            let resultado = await Task.detached(priority: .userInitiated) {
                ArteDaFolha.importar(urls, vagas: vagas, limite: limite)
            }.value
            defer {
                operacao = nil
                estado = ""
            }
            if let primeira = resultado.artes.first {
                if substituirAmostra {
                    artes = resultado.artes
                } else {
                    artes.append(contentsOf: resultado.artes)
                }
                selecao = primeira.id
                if resultado.artes.count > 1 { modo = .folha }
                pagina = 0
                if resultado.falhas.isEmpty {
                    let quantidade = resultado.artes.count
                    AccessibilityNotification.Announcement(
                        quantidade == 1 ? "Uma imagem adicionada." : "\(quantidade) imagens adicionadas."
                    ).post()
                }
            }
            if !resultado.falhas.isEmpty {
                erro = resultado.falhas.joined(separator: "\n")
            }
        }
    }

    private func salvar(_ formato: FormatoArquivo, preparacao: PreparacaoDaFolha) {
        guard operacao == nil, preparacao.permiteSalvar(formato),
              let selecionada = preparacao.arteEmEdicao,
              let opcoes = preparacao.arteSelecionada else { return }
        let painel = NSSavePanel()
        painel.allowedContentTypes = [formato.tipo]
        painel.nameFieldStringValue = formato == .pdf
            ? "cartrest-folha-a4.pdf"
            : "cartrest-\(selecionada.nome.replacingOccurrences(of: "/", with: "-")).png"
        guard painel.runModal() == .OK, let destino = painel.url else { return }

        // O trabalho usa o recorte e a lista do momento do clique, mesmo que a
        // edição continue depois. Cada formato publica o arquivo completo de uma vez.
        let lista = preparacao.artes
        operacao = .exportacao
        estado = "Gerando \(formato.extensao.uppercased())…"
        Task {
            defer { operacao = nil }
            do {
                try await Task.detached(priority: .userInitiated) {
                    switch formato {
                    case .pdf:
                        try Exportador.pdf(lista, para: destino)
                    case .png:
                        try Exportador.png(opcoes).write(to: destino, options: .atomic)
                    }
                }.value
                let sucesso = "Salvo em \(destino.lastPathComponent)"
                estado = sucesso
                AccessibilityNotification.Announcement(sucesso).post()
            } catch {
                erro = error.localizedDescription
                estado = ""
            }
        }
    }
}
