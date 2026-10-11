import Foundation
import HerdrKit

/// Only compiled into independent acceptance hosts, never formal app targets.
struct VisualFixture: Decodable {
    let deviceID: UUID
    let deviceName: String
    let host: String
    let username: String
    let snapshot: SessionSnapshot
    let terminal: String
    static func load() throws -> Self {
        let url = Bundle.main.url(forResource: "scene", withExtension: "json")!
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    @MainActor
    func seedUnread(_ state: AgentReadState) {
        state.apply(agents: snapshot.agents.map { $0.paneID == "done-unread" ? $0.updatingStatus(.working) : $0 }, deviceID: deviceID)
        state.apply(agents: snapshot.agents, deviceID: deviceID)
    }
}
