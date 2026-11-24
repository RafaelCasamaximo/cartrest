import SwiftUI

/// Mostra as cotas físicas do projeto em um visor independente da escala da prancheta.
struct VisorMedidas: View {
    struct Leitura {
        let nome: String
        let valor: String
    }

    static let margemInferior: CGFloat = 24
    static let altura: CGFloat = 72
    static let reservaNaPrancheta = altura + margemInferior + 14

    let leituras: [Leitura]

    private let tinta = Color(red: 0.11, green: 0.19, blue: 0.10)
    private let divisao = Color(red: 0.32, green: 0.40, blue: 0.25)
    private let gabinete = RoundedRectangle(cornerRadius: 17)
    private let visor = RoundedRectangle(cornerRadius: 9)

    var body: some View {
        HStack(spacing: 9) {
            parafuso(giro: -28)
            HStack(spacing: 0) {
                ForEach(leituras.indices, id: \.self) { indice in
                    if indice > 0 {
                        Rectangle().fill(divisao.opacity(0.52))
                            .frame(width: 1, height: 30)
                            .accessibilityHidden(true)
                    }
                    leitura(leituras[indice])
                }
            }
            .padding(.horizontal, 4)
            .frame(maxHeight: .infinity)
            .background(
                visor.fill(LinearGradient(
                    colors: [Color(red: 0.83, green: 0.88, blue: 0.70), Color(red: 0.64, green: 0.73, blue: 0.50)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            )
            .overlay {
                // A luz na borda inferior e a sombra no topo dão profundidade ao rebaixo.
                visor.strokeBorder(.black.opacity(0.58), lineWidth: 1)
                visor.inset(by: 1).strokeBorder(
                    LinearGradient(colors: [.black.opacity(0.24), .white.opacity(0.33)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            }
            parafuso(giro: 31)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 496)
        .frame(height: Self.altura)
        .background(
            gabinete.fill(LinearGradient(
                stops: [
                    .init(color: Color(red: 0.28, green: 0.32, blue: 0.30), location: 0),
                    .init(color: Color(red: 0.16, green: 0.20, blue: 0.18), location: 0.16),
                    .init(color: Color(red: 0.09, green: 0.12, blue: 0.11), location: 0.93),
                    .init(color: Color(red: 0.17, green: 0.20, blue: 0.18), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            ))
        )
        .overlay {
            gabinete.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.26), .black.opacity(0.65)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
        }
        .shadow(color: .black.opacity(0.42), radius: 14, x: 0, y: 9)
    }

    private func leitura(_ leitura: Leitura) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(leitura.nome)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tinta.opacity(0.89))
            Text(leitura.valor)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(tinta)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func parafuso(giro: Double) -> some View {
        Circle()
            .fill(LinearGradient(colors: [Color(white: 0.60), Color(white: 0.20)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { Circle().strokeBorder(.black.opacity(0.68), lineWidth: 1) }
            .overlay {
                Capsule().fill(.black.opacity(0.65))
                    .frame(width: 5, height: 1.1)
                    .rotationEffect(.degrees(giro))
            }
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}
