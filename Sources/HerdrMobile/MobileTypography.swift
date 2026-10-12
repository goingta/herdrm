import SwiftUI

/// Reference mobile reading roles (styles.css: 13/14/15/16px), with native
/// Dynamic Type. Glyph sizes change; the independent 44pt controls do not.
enum MobileTextRole {
    case body, title, secondary, metadata, keyboard, input
    var points: CGFloat {
        switch self {
        case .body: 15
        case .title, .input: 16
        case .secondary, .keyboard: 13
        case .metadata: 12
        }
    }
    var relativeTo: Font.TextStyle {
        switch self {
        case .title: .headline
        case .secondary: .subheadline
        case .metadata, .keyboard: .caption
        case .body, .input: .body
        }
    }
}

private struct MobileRoleFont: ViewModifier {
    let role: MobileTextRole
    let weight: Font.Weight
    @ScaledMetric private var size: CGFloat
    init(role: MobileTextRole, weight: Font.Weight) {
        self.role = role; self.weight = weight
        _size = ScaledMetric(wrappedValue: role.points, relativeTo: role.relativeTo)
    }
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: role == .keyboard ? .monospaced : .default))
    }
}

extension View {
    func mobileFont(_ role: MobileTextRole, weight: Font.Weight = .regular) -> some View {
        modifier(MobileRoleFont(role: role, weight: weight))
    }
}
