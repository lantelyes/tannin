import AppKit
import SwiftUI

/// Iron-gall ink and amber. Every colour has a light and a dark value; status colours are kept apart from the accent.
enum Theme {
    static let window = Color(light: 0xEEF0F4, dark: 0x141925)
    static let card = Color(light: 0xFFFFFF, dark: 0x1C2230)
    static let line = Color(light: 0xD3D8E2, dark: 0x2F384C)
    static let text = Color(light: 0x1C2230, dark: 0xE6E8EE)
    static let secondary = Color(light: 0x535D72, dark: 0x9BA5B8)
    static let chip = Color(light: 0xE6E9F0, dark: 0x262E40)

    /// Amber, for the primary action and switches.
    static let accent = Color(light: 0xE0A552, dark: 0xD9963F)
    static let onAccent = Color(light: 0x1C2230, dark: 0x141925)
    /// Amber dark enough to read as text.
    static let accentText = Color(light: 0x8A5516, dark: 0xE7AE62)

    static let ok = Color(light: 0x1F5FBF, dark: 0x74B3FF)
    static let attention = Color(light: 0xA84B00, dark: 0xFF9F45)
    static let broken = Color(light: 0xA8321F, dark: 0xF08A76)
}

extension Color {
    /// A colour that follows the window's light or dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
