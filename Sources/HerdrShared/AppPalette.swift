import Foundation

/// App colors chosen from the user's green/black/white screenshot direction.
/// These are herdrm values, not claimed to be Moshi's official design tokens.
enum AppPalette {
    struct Swatch {
        let light: UInt32
        let dark: UInt32
        func hex(dark appearance: Bool) -> String {
            String(format: "#%06X", appearance ? dark : light)
        }
    }

    static let background = Swatch(light: 0xFFFFFF, dark: 0x000000)
    static let panel = Swatch(light: 0xF5F5F7, dark: 0x111214)
    static let elevated = Swatch(light: 0xF0F0F2, dark: 0x1B1C1E)
    static let input = Swatch(light: 0xF5F5F7, dark: 0x1B1C1E)
    static let hover = Swatch(light: 0xE4E4E7, dark: 0x242528)
    static let border = Swatch(light: 0xD4D4D8, dark: 0x2B2C30)
    static let text = Swatch(light: 0x171719, dark: 0xF5F5F7)
    static let strong = Swatch(light: 0x000000, dark: 0xF5F5F7)
    static let dim = Swatch(light: 0x52525B, dark: 0xA1A1AA)
    static let ghost = Swatch(light: 0x71717A, dark: 0x71717A)
    static let accent = Swatch(light: 0x006B12, dark: 0x00F000)
    static let primary = Swatch(light: 0x00F000, dark: 0x00F000)
    static let primaryText = Swatch(light: 0x000000, dark: 0x000000)
    static let selection = Swatch(light: 0xD0F4D0, dark: 0x153D18)
}
