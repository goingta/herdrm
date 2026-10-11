import XCTest
import HerdrKit
import HerdrSSH
@testable import HerdrMobile

@MainActor
final class MobilePromptTests: XCTestCase {
    func testShellInputWritesExactTextAndEnterOnceWithoutAgentPrompt() async throws {
        let transport = PromptBoundary()
        let input = ShellInputBoundary()
        let session = MobileAttachSession(transport: transport, target: .terminal(terminalID: "shell"), paneID: "shell", terminalInputWriter: { data in try await input.write(data) })
        try await session.submitShellInput("  echo fixture\n")
        let writes = await input.writes
        XCTAssertEqual(writes, [Data("  echo fixture\n\r".utf8)])
        let prompts = await transport.submissions
        XCTAssertEqual(prompts, 0)
        session.presentationVisible = false
        do { try await session.submitShellInput("covered"); XCTFail("Covered input must fail") } catch {}
        let count = await input.writes.count
        XCTAssertEqual(count, 1)
    }

    func testShellFailedWriteNeverReplaysAndOldAttachCannotConfirmNewTarget() async throws {
        let transport = PromptBoundary()
        let failed = ShellInputBoundary(fails: true)
        let session = MobileAttachSession(transport: transport, target: .terminal(terminalID: "shell"), paneID: "shell", terminalInputWriter: { data in try await failed.write(data) })
        do { try await session.submitShellInput("uncertain"); XCTFail("Write must fail") } catch {}
        let failedCount = await failed.writes.count
        XCTAssertEqual(failedCount, 1)
        let delayed = ShellInputBoundary(delay: true)
        let prior = MobileAttachSession(transport: transport, target: .terminal(terminalID: "shell"), paneID: "shell", terminalInputWriter: { data in try await delayed.write(data) })
        let send = Task { () -> Bool in do { try await prior.submitShellInput("old host"); return true } catch { return false } }
        try await Task.sleep(for: .milliseconds(20)); prior.stop()
        let acknowledged = await send.value
        XCTAssertFalse(acknowledged)
        let count = await delayed.writes.count
        XCTAssertEqual(count, 1, "Uncertain old delivery is never replayed")
    }

    func testShellDraftsAreIsolatedByPresentationAndSurviveTargetReturn() {
        let model = MobileAppModel(store: MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let device = UUID(); let first = MobileShellDraftTarget(deviceID: device, presentationID: UUID(), spaceID: "space", tabID: "tab", paneID: "same")
        let replacement = MobileShellDraftTarget(deviceID: device, presentationID: UUID(), spaceID: "space", tabID: "tab", paneID: "same")
        model.setShellDraft("first host draft", for: first); model.setShellDraft("new host draft", for: replacement)
        model.setShellDraft("", for: first)
        XCTAssertEqual(model.shellDraft(for: replacement), "new host draft")
        XCTAssertEqual(model.shellDraft(for: first), "")
    }

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

    func testHostEditCannotClearSameTextDraftAfterOldHostAcknowledges() async throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let device = MobileDevice(name: "Fixture", host: "old.fixture", username: "developer")
        store.save([device]); let transport = PromptBoundary(succeeds: true)
        let model = MobileAppModel(store: store, connector: { _ in transport })
        model.connectSelected()
        for _ in 0..<100 { if model.selectedTransportReady { break }; try await Task.sleep(for: .milliseconds(20)) }
        let target = try XCTUnwrap(model.currentPromptTarget)
        model.setAgentDraft("Same text", paneID: target.paneID, deviceID: device.id)
        let oldSend = Task { await model.submitPrompt(target: target) }
        try await Task.sleep(for: .milliseconds(30))
        var replacement = device; replacement.host = "new.fixture"; try model.updateDevice(replacement)
        model.setAgentDraft("Same text", paneID: target.paneID, deviceID: device.id)
        let result = await oldSend.value
        XCTAssertEqual(result, .targetChanged)
        XCTAssertEqual(model.agentDraft(paneID: target.paneID, deviceID: device.id), "Same text")
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

private actor ShellInputBoundary {
    var writes: [Data] = []
    let fails: Bool
    let delay: Bool
    init(fails: Bool = false, delay: Bool = false) { self.fails = fails; self.delay = delay }
    func write(_ data: Data) async throws {
        writes.append(data)
        if delay { try await Task.sleep(for: .milliseconds(80)) }
        if fails { throw URLError(.networkConnectionLost) }
    }
}
