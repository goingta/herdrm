import SwiftUI

private struct AgentTabVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var agentTabVisible: Bool {
        get { self[AgentTabVisibleKey.self] }
        set { self[AgentTabVisibleKey.self] = newValue }
    }
}
