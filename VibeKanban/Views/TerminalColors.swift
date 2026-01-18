import AppKit
import SwiftTerm

// Tomorrow Night Theme
// https://github.com/chriskempson/tomorrow-theme
enum TerminalColors {
    // Base colors (NSColor for UI)
    static let background = NSColor(hex: 0x1D1F21) // Background
    static let foreground = NSColor(hex: 0xC5C8C6) // Foreground
    static let selection = NSColor(hex: 0x373B41) // Selection
    static let line = NSColor(hex: 0x282A2E) // Current Line
    static let comment = NSColor(hex: 0x969896) // Comment

    // Accent colors (NSColor for UI)
    static let red = NSColor(hex: 0xCC6666)
    static let orange = NSColor(hex: 0xDE935F)
    static let yellow = NSColor(hex: 0xF0C674)
    static let green = NSColor(hex: 0xB5BD68)
    static let aqua = NSColor(hex: 0x8ABEB7)
    static let blue = NSColor(hex: 0x81A2BE)
    static let purple = NSColor(hex: 0xB294BB)

    // ANSI 16-color palette for SwiftTerm
    // Note: SwiftTerm Color uses UInt16 (0-65535), so we multiply 8-bit values by 257
    nonisolated(unsafe) static let ansiColors: [SwiftTerm.Color] = [
        // Normal colors (0-7)
        color(0x1D, 0x1F, 0x21), // 0: Black (background)
        color(0xCC, 0x66, 0x66), // 1: Red
        color(0xB5, 0xBD, 0x68), // 2: Green
        color(0xF0, 0xC6, 0x74), // 3: Yellow
        color(0x81, 0xA2, 0xBE), // 4: Blue
        color(0xB2, 0x94, 0xBB), // 5: Magenta (purple)
        color(0x8A, 0xBE, 0xB7), // 6: Cyan (aqua)
        color(0xC5, 0xC8, 0xC6), // 7: White (foreground)

        // Bright colors (8-15)
        color(0x96, 0x98, 0x96), // 8: Bright Black (comment)
        color(0xCC, 0x66, 0x66), // 9: Bright Red
        color(0xB5, 0xBD, 0x68), // 10: Bright Green
        color(0xF0, 0xC6, 0x74), // 11: Bright Yellow
        color(0x81, 0xA2, 0xBE), // 12: Bright Blue
        color(0xB2, 0x94, 0xBB), // 13: Bright Magenta
        color(0x8A, 0xBE, 0xB7), // 14: Bright Cyan
        color(0xFF, 0xFF, 0xFF), // 15: Bright White
    ]

    /// Convert 8-bit RGB to SwiftTerm Color (16-bit)
    private static func color(_ r: UInt16, _ g: UInt16, _ b: UInt16) -> SwiftTerm.Color {
        SwiftTerm.Color(red: r * 257, green: g * 257, blue: b * 257)
    }
}

// MARK: - NSColor Extension

extension NSColor {
    convenience init(hex: Int) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
