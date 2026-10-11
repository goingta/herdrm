import HerdrKit
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shared app sRGB colors, resolved against each platform's appearance.
enum Theme {
    private struct RGBA { let value: UInt32; let alpha: Double }
    private static func hex(_ value: UInt32, alpha: Double = 1) -> RGBA {
        RGBA(value: value, alpha: alpha)
    }
    private static func dynamic(_ light: RGBA, _ dark: RGBA) -> Color {
        #if os(macOS)
        func native(_ rgba: RGBA) -> NSColor {
            NSColor(srgbRed: CGFloat((rgba.value >> 16) & 0xFF) / 255,
                    green: CGFloat((rgba.value >> 8) & 0xFF) / 255,
                    blue: CGFloat(rgba.value & 0xFF) / 255, alpha: rgba.alpha)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            native(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
        #else
        return Color(uiColor: UIColor { traits in
            let rgba = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((rgba.value >> 16) & 0xFF) / 255,
                           green: CGFloat((rgba.value >> 8) & 0xFF) / 255,
                           blue: CGFloat(rgba.value & 0xFF) / 255, alpha: rgba.alpha)
        })
        #endif
    }

    private static func dynamic(_ swatch: AppPalette.Swatch, alpha: Double = 1) -> Color {
        dynamic(hex(swatch.light, alpha: alpha), hex(swatch.dark, alpha: alpha))
    }

    static let text = dynamic(AppPalette.text)
    static let strong = dynamic(AppPalette.strong)
    static let textSecondary = dynamic(AppPalette.dim)
    static let textTertiary = textSecondary
    static let textGhost = dynamic(AppPalette.ghost)
    static let accent = dynamic(AppPalette.accent)
    static let accentWash = dynamic(AppPalette.accent, alpha: 0.12)
    static let primary = dynamic(AppPalette.primary)
    static let primaryText = dynamic(AppPalette.primaryText)
    static let panel = dynamic(AppPalette.panel)
    static let elevated = dynamic(AppPalette.elevated)
    static let input = dynamic(AppPalette.input)
    static let itemWash = dynamic(AppPalette.elevated)
    static let itemWashSelected = dynamic(AppPalette.elevated)
    static let contentBackground = dynamic(AppPalette.background)
    static let terminalBackground = contentBackground
    static let statusBarBackground = panel
    static let sidebarBorder = dynamic(AppPalette.border)
    static let hairline = sidebarBorder

    #if os(iOS)
    // Preserve established semantic status colors independently of the app accent.
    static let working = dynamic(hex(0x155A72), hex(0x6CB8D6))
    static let success = dynamic(hex(0x2F6317), hex(0x93C36B))
    static let warning = dynamic(hex(0xA82323), hex(0xFF7B70))
    static let statsAccount = dynamic(hex(0x3F9A7A), hex(0xB5EAD7))
    static let danger = warning
    #else
    static let working = dynamic(hex(0x2563EB), hex(0x3B82F6))
    static let success = dynamic(hex(0x2FA35F), hex(0x62C987))
    static let warning = dynamic(hex(0xB8862E), hex(0xE0B36A))
    /// grazr's account line, matching the mint the Herdr TUI row uses (#b5ead7).
    static let statsAccount = dynamic(hex(0x3F9A7A), hex(0xB5EAD7))
    static let danger = dynamic(hex(0xC94F44), hex(0xE2726A))

    #endif

    #if os(macOS)
    static let unread = working
    #else
    static let unread = dynamic(hex(0x2563EB), hex(0x3B82F6))
    #endif

    /// Distinct tints for device chips (deliberately avoids the status colors).
    static let devicePalette: [Color] = [
        dynamic(hex(0x7C3AED), hex(0x8B5CF6)),  // violet
        dynamic(hex(0x0D9488), hex(0x14B8A6)),  // teal
        dynamic(hex(0xBE185D), hex(0xEC4899)),  // magenta
        dynamic(hex(0x4338CA), hex(0x818CF8)),  // indigo
        dynamic(hex(0x92640C), hex(0xC9964A)),  // bronze
    ]

    static func statusColor(_ status: AgentStatus) -> Color {
        switch status {
        case .working: return working
        case .blocked: return warning
        case .done: return success
        case .idle, .unknown: return textGhost
        }
    }
}

/// Common component proportions; touch sizes belong to the platform view.
enum VisualMetrics {
    static let controlRadius: CGFloat = 7
    static let panelRadius: CGFloat = 10
    static let minimumTouchTarget: CGFloat = 44
}
