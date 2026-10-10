import HerdrKit
import SwiftUI

func agentStatusDescription(_ status: AgentStatus, unread: Bool = false) -> String {
    switch status {
    case .working: AppLocalization.string("Working")
    case .blocked: AppLocalization.string("Blocked")
    case .done: unread ? AppLocalization.string("Completed, unread") : AppLocalization.string("Done")
    case .idle: AppLocalization.string("Idle")
    case .unknown: AppLocalization.string("Unknown")
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
            #if os(macOS)
            SpinnerView(color: Theme.working).frame(width: 12, height: 12)
            #else
            ProgressView().tint(Theme.working).controlSize(.small).frame(width: 12, height: 12)
            #endif
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
