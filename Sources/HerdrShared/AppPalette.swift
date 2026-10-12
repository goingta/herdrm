import Foundation
import Observation

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

    // One process-wide app setting, shared by every native window. Observation
    // tracks palette reads inside SwiftUI bodies; no defaults polling or view IDs.
    @Observable final class Selection { var mode = AppearancePreference.phosphor }
    private static let selected = Selection()
    static var currentPreset: AppearancePreference { selected.mode }
    @MainActor static func select(_ mode: AppearancePreference) { selected.mode = mode }

    enum Role {
        case background, panel, elevated, input, hover, border, text, strong, dim, ghost, accent, primary, primaryText, selection
    }
    static func swatch(_ role: Role, preset: AppearancePreference) -> Swatch {
        let values: (UInt32, UInt32)
        switch role {
        case .background: values = (0x000000, 0x12100E)
        case .panel: values = (0x111214, 0x181613)
        case .elevated: values = (0x1B1C1E, 0x211E1A)
        case .input: values = (0x1B1C1E, 0x1C1916)
        case .hover: values = (0x242528, 0x2A2621)
        case .border: values = (0x2B2C30, 0x2D2924)
        case .text: values = (0xF5F5F7, 0xD8D0C3)
        case .strong: values = (0xF5F5F7, 0xF2EBDF)
        case .dim: values = (0xA1A1AA, 0x9B9183)
        case .ghost: values = (0x71717A, 0x786F63)
        case .accent, .primary: values = (0x00F000, 0xF0A830)
        case .primaryText: values = (0x000000, 0x000000)
        case .selection: values = (0x153D18, 0x4A3D26)
        }
        let value = preset == .phosphor ? values.0 : values.1
        return Swatch(light: value, dark: value)
    }
    static var background: Swatch { swatch(.background, preset: currentPreset) }
    static var panel: Swatch { swatch(.panel, preset: currentPreset) }
    static var elevated: Swatch { swatch(.elevated, preset: currentPreset) }
    static var input: Swatch { swatch(.input, preset: currentPreset) }
    static var hover: Swatch { swatch(.hover, preset: currentPreset) }
    static var border: Swatch { swatch(.border, preset: currentPreset) }
    static var text: Swatch { swatch(.text, preset: currentPreset) }
    static var strong: Swatch { swatch(.strong, preset: currentPreset) }
    static var dim: Swatch { swatch(.dim, preset: currentPreset) }
    static var ghost: Swatch { swatch(.ghost, preset: currentPreset) }
    static var accent: Swatch { swatch(.accent, preset: currentPreset) }
    static var primary: Swatch { swatch(.primary, preset: currentPreset) }
    static var primaryText: Swatch { swatch(.primaryText, preset: currentPreset) }
    static var selection: Swatch { swatch(.selection, preset: currentPreset) }
}
