import SwiftUI

/// Editor colors grouped by role, with a light and dark variant for each.
struct CartrestTheme {
    let colorScheme: ColorScheme

    var windowBackground: Color { color(dark: 0x18211f, light: 0xf4f5f0) }
    var inspectorBackground: Color { color(dark: 0x202b27, light: 0xeaf0e9) }
    var footerBackground: Color { color(dark: 0x26332e, light: 0xe3ebe3) }
    var selectionBackground: Color { color(dark: 0x31493e, light: 0xd4e8d9) }
    var selectionBorder: Color { color(dark: 0x5b856e, light: 0x82a995) }
    var divider: Color { color(dark: 0x3b4d45, light: 0xc4d3c9) }
    // Button fills and highlighted text need different contrast on the same surface.
    var buttonTint: Color { color(dark: 0x29734f, light: 0x24664b) }
    var accentText: Color { color(dark: 0xbbdbbf, light: 0x2a593f) }

    private func color(dark: UInt32, light: UInt32) -> Color {
        let hex = colorScheme == .dark ? dark : light
        return Color(
            red: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255
        )
    }
}
