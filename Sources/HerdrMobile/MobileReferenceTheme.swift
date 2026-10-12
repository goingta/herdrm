import SwiftUI

/// Keeps the reference layout on the app's shared green/black/white palette.
enum MobileReferenceTheme {
    static var background: Color { Theme.contentBackground }
    static var panel: Color { Theme.panel }
    static var elevated: Color { Theme.elevated }
    static var input: Color { Theme.input }
    static var border: Color { Theme.sidebarBorder }
    static var text: Color { Theme.text }
    static var strong: Color { Theme.strong }
    static var dim: Color { Theme.textSecondary }
    static var accent: Color { Theme.accent }
    static var primary: Color { Theme.primary }
    static var primaryText: Color { Theme.primaryText }
}
