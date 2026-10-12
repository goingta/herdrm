import XCTest
import HerdrKit

@MainActor
final class ChatReadAcknowledgementTests: XCTestCase {
    func testPresentedChatClearsOnlyCurrentCompletionWithoutSuppressingTheNextCompletion() throws {
        let state = AgentReadState(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let deviceID = UUID()
        let key = AgentUnreadKey(deviceID: deviceID, paneID: "pane-a")
        func agent(_ status: String) throws -> AgentInfo {
            try JSONDecoder().decode(AgentInfo.self, from: Data("{\"workspace_id\":\"s\",\"tab_id\":\"t\",\"pane_id\":\"pane-a\",\"agent\":\"codex\",\"agent_status\":\"\(status)\"}".utf8))
        }
        state.apply(agents: [try agent("working")], deviceID: deviceID)
        state.apply(agents: [try agent("done")], deviceID: deviceID)
        XCTAssertTrue(state.unread.contains(key))
        XCTAssertFalse(state.acknowledgeChatResult(key, foreground: false))
        XCTAssertTrue(state.acknowledgeChatResult(key, foreground: true))
        XCTAssertFalse(state.unread.contains(key))
        state.apply(agents: [try agent("working")], deviceID: deviceID)
        state.apply(agents: [try agent("done")], deviceID: deviceID)
        XCTAssertTrue(state.unread.contains(key), "A prior visible chat is not evidence for the next result")
    }
}
