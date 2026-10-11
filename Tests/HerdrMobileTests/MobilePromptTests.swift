import XCTest
import HerdrKit
import HerdrSSH
@testable import HerdrMobile

@MainActor
final class MobilePromptTests: XCTestCase {
    func testFailedExistingAgentSubmissionKeepsDraftAndDoesNotReplay() async throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let device = MobileDevice(name: "Fixture", host: "fixture.example", username: "developer")
        store.save([device])
        let transport = PromptBoundary()
        let model = MobileAppModel(store: store, connector: { _ in transport })
        model.connectSelected()
        for _ in 0..<100 {
            if model.selectedTransportReady { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        model.setAgentDraft("Keep this prompt", paneID: "pane-a", deviceID: device.id)
        let target = try XCTUnwrap(model.currentPromptTarget)
        let result = await model.submitPrompt(target: target)
        XCTAssertEqual(result, .failed)
        XCTAssertEqual(model.agentDraft(paneID: "pane-a", deviceID: device.id), "Keep this prompt")
        let submissions = await transport.submissions
        XCTAssertEqual(submissions, 1)
        await model.selectedSession?.disconnect()
    }
    func testAcknowledgementDoesNotClearTextEditedWhileRequestIsInFlight() async throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let device = MobileDevice(name: "Fixture", host: "fixture.example", username: "developer")
        store.save([device])
        let transport = PromptBoundary(succeeds: true)
        let model = MobileAppModel(store: store, connector: { _ in transport })
        model.connectSelected()
        for _ in 0..<100 {
            if model.selectedTransportReady { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        model.setAgentDraft("Sent text", paneID: "pane-a", deviceID: device.id)
        let target = try XCTUnwrap(model.currentPromptTarget)
        let first = Task { await model.submitPrompt(target: target) }
        try await Task.sleep(for: .milliseconds(30))
        let duplicate = await model.submitPrompt(target: target)
        XCTAssertEqual(duplicate, .busy)
        model.setAgentDraft("Next draft", paneID: "pane-a", deviceID: device.id)
        let acknowledged = await first.value
        XCTAssertEqual(acknowledged, .acknowledged)
        XCTAssertEqual(model.agentDraft(paneID: "pane-a", deviceID: device.id), "Next draft")
        let submissions = await transport.submissions
        XCTAssertEqual(submissions, 1)
        await model.selectedSession?.disconnect()
    }

    func testServiceBindingEditDoesNotAcknowledgeTheNewComposerDraft() async throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let device = MobileDevice(name: "Fixture", host: "fixture.example", username: "developer")
        store.save([device])
        let transport = PromptBoundary(succeeds: true)
        let model = MobileAppModel(store: store, chatCredentialRemover: { _, _ in }, connector: { _ in transport })
        model.connectSelected()
        for _ in 0..<100 {
            if model.selectedTransportReady { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let target = try XCTUnwrap(model.currentPromptTarget)
        model.setAgentDraft("Same text in changed context", paneID: target.paneID, deviceID: device.id)
        let send = Task { await model.submitPrompt(target: target) }
        try await Task.sleep(for: .milliseconds(30))
        try model.saveChatConfiguration(.init(serviceURL: "https://new-binding.invalid", machineID: "local"), for: device.id)
        let result = await send.value
        XCTAssertEqual(result, .targetChanged)
        XCTAssertEqual(model.agentDraft(paneID: target.paneID, deviceID: device.id), "Same text in changed context")
        let count = await transport.submissions
        XCTAssertEqual(count, 1)
        await model.selectedSession?.disconnect()
    }

}

private actor PromptBoundary: MobileTransport {
    var submissions = 0
    let succeeds: Bool
    init(succeeds: Bool = false) { self.succeeds = succeeds }
    func request(method: String, params: JSONValue) async throws -> JSONValue {
        if method == "ping" { return .object(["version": .string("fixture"), "protocol": .number(22)]) }
        if method == "agent.prompt" {
            submissions += 1
            try await Task.sleep(for: .milliseconds(100))
            if succeeds { return .object([:]) }
            throw URLError(.networkConnectionLost)
        }
        return try JSONDecoder().decode(JSONValue.self, from: Data(Self.snapshot.utf8))
    }
    nonisolated func events(kinds: [String], statusPaneIDs: [String]) -> AsyncThrowingStream<HerdrEvent, Error> { AsyncThrowingStream { _ in } }
    func openTerminal(command: String, columns: Int, rows: Int) async throws -> SSHPTYChannel { throw CancellationError() }
    func close() async {}
    static let snapshot = """
    {"snapshot":{"focused_workspace_id":"space-a","focused_pane_id":"pane-a","workspaces":[{"workspace_id":"space-a","number":1,"label":"Workspace","active_tab_id":"tab-a"}],"tabs":[{"tab_id":"tab-a","workspace_id":"space-a","number":1,"label":"Task"}],"agents":[{"workspace_id":"space-a","tab_id":"tab-a","pane_id":"pane-a","agent":"codex","agent_status":"working"}]}}
    """
}
