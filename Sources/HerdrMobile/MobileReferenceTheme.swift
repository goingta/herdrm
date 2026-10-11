import SwiftUI
import UIKit

/// Adapted from herdr-web-ui styles.css (MIT, © 2026 devswha).
/// iPhone-only adapter; Mac's established design tokens are unchanged.
enum MobileReferenceTheme {
    static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: native(light, dark))
    }
    static func native(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
    static let background = color(0xEEEAE2, 0x12100E)
    static let panel = color(0xFAF8F3, 0x181613)
    static let elevated = color(0xF2EEE6, 0x211E1A)
    static let input = color(0xFFFDF9, 0x1C1916)
    static let border = color(0xDCD4C6, 0x2D2924)
    static let text = color(0x2A251F, 0xD8D0C3)
    static let strong = color(0x16120D, 0xF2EBDF)
    static let dim = color(0x685E52, 0x9B9183)
    static let accent = color(0x8C5000, 0xF0A830)
    static let primary = color(0xC57D12, 0xF0A830)
}
