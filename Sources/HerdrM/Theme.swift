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

/// Codex-style conversation marks: spinner while running, a filled unread
/// dot after a finish you have not opened, nothing once you have looked.
struct AgentStatusGlyph: View {
    let status: AgentStatus
    var unreadDone: Bool = false

    var body: some View {
        switch status {
        case .working:
            SpinnerView(color: Theme.working)
                .frame(width: 12, height: 12)
        case .blocked:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.warning)
        case .done:
            if unreadDone {
                Circle()
                    .fill(Theme.working)
                    .frame(width: 7, height: 7)
            }
        case .idle, .unknown:
            EmptyView()
        }
    }
}

/// Space row uses the same glyph as an agent, for the strongest state inside.
struct SpaceAttentionGlyph: View {
    let attention: SpaceAttention

    var body: some View {
        switch attention {
        case .blocked:
            AgentStatusGlyph(status: .blocked)
        case .unreadDone:
            AgentStatusGlyph(status: .done, unreadDone: true)
        case .working:
            AgentStatusGlyph(status: .working)
        case .none:
            EmptyView()
        }
    }
}
