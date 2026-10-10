import Foundation

/// Client-local completion reminders. A successful authoritative snapshot may
/// remove panes; transport failures never call apply with an empty snapshot.
@MainActor
public final class AgentReadState {
    public private(set) var unread: Set<AgentUnreadKey>
    private var previous: [UUID: [String: AgentStatus]] = [:]
    private var terminals: [AgentUnreadKey: UUID] = [:]
    private var visible: Set<AgentUnreadKey> = []
    private let defaults: UserDefaults
    private let storageKey: String

    public init(defaults: UserDefaults = .standard, storageKey: String = "agent-unread-v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        unread = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(Set<AgentUnreadKey>.self, from: $0) } ?? []
    }

    public func apply(agents: [AgentInfo], deviceID: UUID, authoritative: Bool = true, foreground: Bool = true) {
        if !foreground { visible.removeAll() }
        if authoritative {
            let live = Set(agents.map(\.paneID))
            terminals = terminals.filter { $0.key.deviceID != deviceID || live.contains($0.key.paneID) }
            visible = visible.filter { $0.deviceID != deviceID || live.contains($0.paneID) }
        }
        let known = previous[deviceID] ?? [:]
        let retained = authoritative ? unread : unread.filter { key in
            key.deviceID != deviceID || !agents.contains { $0.paneID == key.paneID }
        }
        let updated = AgentUnread.applying(previous: known, agents: agents, unread: unread, deviceID: deviceID)
        unread = authoritative ? updated : retained.union(updated)
        var statuses = authoritative ? [:] : known
        for agent in agents { statuses[agent.paneID] = agent.status }
        previous[deviceID] = statuses
        unread.subtract(visible)
        save()
    }

    /// Called once per attach attempt, before it can produce content.
    @discardableResult
    public func beginTerminal(_ key: AgentUnreadKey) -> UUID {
        let generation = UUID()
        terminals[key] = generation
        visible.remove(key)
        return generation
    }

    /// The host calls this only after verifying current content is presented,
    /// never on selection, channel open, or creation of a terminal surface.
    @discardableResult
    public func presented(_ key: AgentUnreadKey, generation: UUID, foreground: Bool) -> Bool {
        guard terminals[key] == generation, foreground else { return false }
        visible.insert(key)
        unread.remove(key)
        save()
        return true
    }

    public func hideTerminal(_ key: AgentUnreadKey, generation: UUID) {
        guard terminals[key] == generation else { return }
        visible.remove(key)
    }

    public func endTerminal(_ key: AgentUnreadKey, generation: UUID) {
        guard terminals[key] == generation else { return }
        terminals.removeValue(forKey: key)
        visible.remove(key)
    }

    public func connectionLost(deviceID: UUID) {
        previous.removeValue(forKey: deviceID)
        terminals = terminals.filter { $0.key.deviceID != deviceID }
        visible = visible.filter { $0.deviceID != deviceID }
    }

    public func removeDevice(_ deviceID: UUID) {
        connectionLost(deviceID: deviceID)
        unread = unread.filter { $0.deviceID != deviceID }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(unread) { defaults.set(data, forKey: storageKey) }
    }
}
