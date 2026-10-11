import HerdrKit
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shared sRGB values from the Mac design canvas; native resolution lives here.
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

    #if os(iOS)
    // Mobile-only reference palette, herdr-web-ui styles.css (MIT © 2026 devswha).
    static let text = dynamic(hex(0x2A251F), hex(0xD8D0C3))
    static let textSecondary = dynamic(hex(0x685E52), hex(0x9B9183))
    static let textTertiary = textSecondary
    static let textGhost = dynamic(hex(0x9B9183), hex(0x685E52))
    static let accent = dynamic(hex(0x8C5000), hex(0xF0A830))
    static let accentWash = dynamic(hex(0x8C5000, alpha: 0.10), hex(0xF0A830, alpha: 0.13))
    static let working = dynamic(hex(0x155A72), hex(0x6CB8D6))
    static let success = dynamic(hex(0x2F6317), hex(0x93C36B))
    static let warning = dynamic(hex(0xA82323), hex(0xFF7B70))
    static let statsAccount = dynamic(hex(0x3F9A7A), hex(0xB5EAD7))
    static let danger = warning
    static let itemWash = dynamic(hex(0xE8E2D6), hex(0x2A2621))
    static let itemWashSelected = dynamic(hex(0xF2EEE6), hex(0x211E1A))
    static let contentBackground = dynamic(hex(0xEEEAE2), hex(0x12100E))
    static let terminalBackground = dynamic(hex(0xFAF8F3), hex(0x181613))
    static let statusBarBackground = terminalBackground
    static let sidebarBorder = dynamic(hex(0xDCD4C6), hex(0x2D2924))
    static let hairline = sidebarBorder
    #else
    // text ramp
    static let text = dynamic(hex(0x242424), hex(0xE2E2E2))
    static let textSecondary = dynamic(hex(0x666666), hex(0xA3A3A3))
    static let textTertiary = dynamic(hex(0x858585), hex(0x7D7D7D))
    static let textGhost = dynamic(hex(0xA4A4A4), hex(0x575757))

    // accent + status
    static let accent = dynamic(hex(0xC85F44), hex(0xE2795B))
    static let accentWash = dynamic(hex(0xC85F44, alpha: 0.12), hex(0xE2795B, alpha: 0.14))
    static let working = dynamic(hex(0x2563EB), hex(0x3B82F6))
    static let success = dynamic(hex(0x2FA35F), hex(0x62C987))
    static let warning = dynamic(hex(0xB8862E), hex(0xE0B36A))
    /// grazr's account line, matching the mint the Herdr TUI row uses (#b5ead7).
    static let statsAccount = dynamic(hex(0x3F9A7A), hex(0xB5EAD7))
    static let danger = dynamic(hex(0xC94F44), hex(0xE2726A))

    // surfaces
    static let itemWash = dynamic(hex(0x141414, alpha: 0.06), hex(0xF0F0F0, alpha: 0.06))
    static let itemWashSelected = dynamic(hex(0x141414, alpha: 0.07), hex(0xF0F0F0, alpha: 0.07))
    static let contentBackground = dynamic(hex(0xF6F6F6), hex(0x181818))
    static let terminalBackground = dynamic(hex(0xFFFFFF), hex(0x101012))
    static let statusBarBackground = dynamic(hex(0xF1F1F2), hex(0x141416))
    static let sidebarBorder = dynamic(hex(0xD9D9D9), hex(0x292929))
    static let hairline = dynamic(hex(0x000000, alpha: 0.08), hex(0xFFFFFF, alpha: 0.06))

    #endif

    static let unread = dynamic(hex(0x2563EB), hex(0x3B82F6))

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
