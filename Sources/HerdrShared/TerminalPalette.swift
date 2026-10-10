import Foundation
import GhosttyTerminal

/// Identical terminal colors on both clients, including explicit cursor/selection.
enum TerminalPalette {
    static let darkBackgroundHex = "#101012"
    static let darkForegroundHex = "#D6D6D6"
    static let lightBackgroundHex = "#FFFFFF"
    static let lightForegroundHex = "#3A3A3A"

    /// The 16-color ANSI palette used by Apple's Terminal.app (formerly
    /// `SwiftTerm.Color.terminalAppColors`, inlined with the renderer switch).
    static let darkPalette: [(red: Int, green: Int, blue: Int)] = [
        (0, 0, 0), (194, 54, 33), (37, 188, 36), (173, 173, 39),
        (73, 46, 225), (211, 56, 211), (51, 187, 200), (203, 204, 205),
        (129, 131, 131), (252, 57, 31), (49, 231, 34), (234, 236, 35),
        (88, 51, 255), (249, 53, 248), (20, 240, 240), (233, 235, 235),
    ]

    /// Per entry, keep whichever of the original and luminance-flipped color reads
    /// better on the light background: the flip rescues colors designed for dark
    /// backgrounds (white, the bright variants), but ANSI red/blue/magenta/black
    /// are already dark and would wash out to pastels.
    static let lightPalette: [(red: Int, green: Int, blue: Int)] = darkPalette.map { color in
        let flipped = LightTerminalANSIAdapter.lightRGB(
            red: color.red,
            green: color.green,
            blue: color.blue
        )
        let originalContrast = LightTerminalANSIAdapter.contrastOnWhite(
            red: color.red, green: color.green, blue: color.blue
        )
        let flippedContrast = LightTerminalANSIAdapter.contrastOnWhite(
            red: flipped.red, green: flipped.green, blue: flipped.blue
        )
        return originalContrast >= flippedContrast ? color : flipped
    }


    static func makeTheme() -> TerminalTheme {
        func configuration(dark: Bool) -> TerminalConfiguration {
            TerminalConfiguration { builder in
                builder.withBackground(dark ? darkBackgroundHex : lightBackgroundHex)
                builder.withForeground(dark ? darkForegroundHex : lightForegroundHex)
                builder.withCursorColor(dark ? darkForegroundHex : lightForegroundHex)
                builder.withCursorText(dark ? darkBackgroundHex : lightBackgroundHex)
                builder.withSelectionBackground(dark ? "#42424A" : "#CDD7E5")
                builder.withSelectionForeground(dark ? "#FFFFFF" : "#242424")
                for (index, color) in (dark ? darkPalette : lightPalette).enumerated() {
                    builder.withPalette(index, color: String(format: "#%02X%02X%02X", color.red, color.green, color.blue))
                }
            }
        }
        return TerminalTheme(light: configuration(dark: false), dark: configuration(dark: true))
    }
}
