import HerdrKit
import SwiftUI

extension Theme {
    /// Stable per-device tint; Local stays neutral.
    static func deviceTint(_ device: Device) -> Color {
        if device.isLocal { return textSecondary }
        let sum = device.id.uuidString.utf8.reduce(0) { $0 &+ Int($1) }
        return devicePalette[sum % devicePalette.count]
    }

}
