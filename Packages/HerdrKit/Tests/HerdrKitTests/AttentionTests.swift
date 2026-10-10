import XCTest
@testable import HerdrKit

final class AttentionTests: XCTestCase {
    func testRollupPicksTheStrongestAgentState() {
        XCTAssertEqual(
            SpaceAttention.rollup([
                (status: .working, unreadDone: false),
                (status: .done, unreadDone: true),
                (status: .blocked, unreadDone: false),
            ]),
            .blocked
        )
        XCTAssertEqual(
            SpaceAttention.rollup([
                (status: .working, unreadDone: false),
                (status: .done, unreadDone: true),
                (status: .done, unreadDone: false),
            ]),
            .unreadDone
        )
        XCTAssertEqual(
            SpaceAttention.rollup([
                (status: .working, unreadDone: false),
                (status: .done, unreadDone: false),
            ]),
            .working
        )
        XCTAssertEqual(
            SpaceAttention.rollup([
                (status: .done, unreadDone: false),
                (status: .idle, unreadDone: false),
            ]),
            .none
        )
        XCTAssertEqual(
            SpaceAttention.rollup([
                (status: .idle, unreadDone: false),
            ]),
            .none
        )
    }

    func testInitialSnapshotDoesNotMarkUnread() throws {
        let agent = try decodeDone(paneID: "w1:p1")
        let device = UUID()
        let unread = AgentUnread.applying(
            previous: [:],
            agents: [agent],
            unread: [],
            deviceID: device
        )
        XCTAssertTrue(unread.isEmpty)
    }

    func testTransitionToDoneMarksUnreadEvenIfSelected() throws {
        let agent = try decodeDone(paneID: "w1:p1")
        let device = UUID()
        let unread = AgentUnread.applying(
            previous: ["w1:p1": .working],
            agents: [agent],
            unread: [],
            deviceID: device
        )
        XCTAssertEqual(unread, [AgentUnreadKey(deviceID: device, paneID: "w1:p1")])
    }

    func testLeavingDoneClearsUnreadAndGonePanesArePruned() throws {
        let device = UUID()
        let key = AgentUnreadKey(deviceID: device, paneID: "w1:p1")
        let other = AgentUnreadKey(deviceID: UUID(), paneID: "w2:p1")
        let working = try decodeAgent(paneID: "w1:p1", status: "working")
        let next = AgentUnread.applying(
            previous: ["w1:p1": .done],
            agents: [working],
            unread: [key, other],
            deviceID: device
        )
        XCTAssertEqual(next, [other])

        let pruned = AgentUnread.applying(
            previous: ["w1:p1": .done],
            agents: [],
            unread: [key, other],
            deviceID: device
        )
        XCTAssertEqual(pruned, [other])
    }

    @MainActor
    func testCompletionSurvivesRestartAndClientsRemainIndependent() throws {
        let suite = "read-state-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = UUID()
        let key = AgentUnreadKey(deviceID: device, paneID: "w1:p1")
        let client = AgentReadState(defaults: defaults)
        client.apply(agents: [try decodeAgent(paneID: key.paneID, status: "working")], deviceID: device)
        client.apply(agents: [try decodeDone(paneID: key.paneID)], deviceID: device)
        XCTAssertTrue(AgentReadState(defaults: defaults).unread.contains(key))
        let other = AgentReadState(defaults: defaults, storageKey: "other-client")
        XCTAssertFalse(other.unread.contains(key))
    }

    @MainActor
    func testOnlyCurrentForegroundPresentedContentReadsCompletion() throws {
        let suite = "read-state-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = AgentReadState(defaults: defaults)
        let device = UUID()
        let key = AgentUnreadKey(deviceID: device, paneID: "w1:p1")
        client.apply(agents: [try decodeAgent(paneID: key.paneID, status: "working")], deviceID: device)
        let old = client.beginTerminal(key)
        let current = client.beginTerminal(key)
        client.apply(agents: [try decodeDone(paneID: key.paneID)], deviceID: device)
        client.presented(key, generation: old, foreground: true)
        client.presented(key, generation: current, foreground: false)
        XCTAssertTrue(client.unread.contains(key))
        client.presented(key, generation: current, foreground: true)
        XCTAssertFalse(client.unread.contains(key))
        client.apply(agents: [try decodeAgent(paneID: key.paneID, status: "working")], deviceID: device)
        client.apply(agents: [try decodeDone(paneID: key.paneID)], deviceID: device)
        XCTAssertFalse(client.unread.contains(key))
        client.hideTerminal(key, generation: current)
        client.apply(agents: [try decodeAgent(paneID: key.paneID, status: "working")], deviceID: device)
        client.apply(agents: [try decodeDone(paneID: key.paneID)], deviceID: device)
        XCTAssertTrue(client.unread.contains(key))
    }

    private func decodeDone(paneID: String) throws -> AgentInfo {
        try decodeAgent(paneID: paneID, status: "done")
    }

    private func decodeAgent(paneID: String, status: String) throws -> AgentInfo {
        let data = Data("""
            {
              "terminal_id": "t", "agent": "codex", "name": "codex",
              "agent_status": "\(status)", "workspace_id": "w1", "tab_id": "w1:t1",
              "pane_id": "\(paneID)", "focused": false, "revision": 0
            }
            """.utf8)
        return try JSONDecoder().decode(AgentInfo.self, from: data)
    }
}
