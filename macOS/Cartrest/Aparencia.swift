import SwiftUI

/// Cores por função no editor, pareadas para o modo claro e o escuro do macOS.
struct AparenciaCartrest {
    let esquema: ColorScheme

    var janela: Color { cores(escura: 0x18211f, clara: 0xf4f5f0) }
    var inspetor: Color { cores(escura: 0x202b27, clara: 0xeaf0e9) }
    var rodape: Color { cores(escura: 0x26332e, clara: 0xe3ebe3) }
    var selecao: Color { cores(escura: 0x31493e, clara: 0xd4e8d9) }
    var contornoSelecao: Color { cores(escura: 0x5b856e, clara: 0x82a995) }
    var contornoSuave: Color { cores(escura: 0x3b4d45, clara: 0xc4d3c9) }
    // O botão primário e o realce de texto têm papéis de contraste distintos.
    var botao: Color { cores(escura: 0x29734f, clara: 0x24664b) }
    var destaque: Color { cores(escura: 0xbbdbbf, clara: 0x2a593f) }

    private func cores(escura: UInt32, clara: UInt32) -> Color {
        let hex = esquema == .dark ? escura : clara
        return Color(
            red: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255
        )
    }
}
