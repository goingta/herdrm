import XCTest
import SwiftUI
import HerdrKit
import HerdrSSH
@testable import HerdrMobile

@MainActor
final class MobileNavigationTests: XCTestCase {
    func testWorkspaceShowsItsLiveBranchAndNeverInventsOneForNonRepository() async throws {
        let (model, _) = fixture()
        model.connectSelected()
        try await wait { model.selectedTransportReady }
        await model.refreshSpaceGitBranches()
        try await wait { model.spaceGitBranch("space-a") == "feature/mobile-controls" }
        XCTAssertNil(model.spaceGitBranch("space-b"))
        await model.selectedSession?.disconnect()
    }

    func testOldDevelopmentMachineBranchReplyCannotReplaceTheCurrentCheckout() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = MobileDeviceStore(defaults: defaults)
        store.save([MobileDevice(name: "Old host", host: "old.example", username: "developer")])
        let gate = GitReplyGate()
        let old = NavigationFixture(branch: "old-host-branch", gate: gate)
        let new = NavigationFixture(branch: "current-host-branch")
        let model = MobileAppModel(store: store, chatCredentialRemover: { _, _ in }, connector: { device in
            device.host == "old.example" ? old : new
        })
        model.connectSelected()
        try await wait { model.selectedTransportReady }
        let pending = Task { await model.refreshSpaceGitBranches() }
        try await gate.waitUntilStarted()
        var edited = try XCTUnwrap(model.selectedDevice)
        edited.host = "new.example"
        try model.updateDevice(edited)
        try await wait { model.selectedTransportReady }
        await model.refreshSpaceGitBranches()
        XCTAssertEqual(model.spaceGitBranch("space-a"), "current-host-branch")
        await gate.release()
        await pending.value
        XCTAssertEqual(model.spaceGitBranch("space-a"), "current-host-branch")
        await model.selectedSession?.disconnect()
    }

    func testSpaceCheckoutMetadataWinsOverPaneWorkingDirectory() async throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.save([MobileDevice(name: "Worktree", host: "fixture.example", username: "developer")])
        let transport = NavigationFixture(checkoutPath: "/actual-checkout")
        let model = MobileAppModel(store: store, connector: { _ in transport })
        model.connectSelected()
        try await wait { model.selectedTransportReady }
        await model.refreshSpaceGitBranches()
        XCTAssertEqual(model.spaceGitBranch("space-a"), "checkout-branch")
        await model.selectedSession?.disconnect()
    }

    func testChangedWorkingDirectoryRejectsItsPendingOldBranchEvenOnTheSameConnection() async throws {
        let gate = GitReplyGate()
        let transport = NavigationFixture(gate: gate)
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.save([MobileDevice(name: "Checkout", host: "fixture.example", username: "developer")])
        let model = MobileAppModel(store: store, connector: { _ in transport })
        model.connectSelected()
        try await wait { model.selectedTransportReady }
        let pending = Task { await model.refreshSpaceGitBranches() }
        try await gate.waitUntilStarted()
        await transport.changeWorkingDirectory()
        _ = await model.selectedSession?.refresh()
        await gate.release(); await pending.value
        XCTAssertNil(model.spaceGitBranch("space-a"))
        await model.refreshSpaceGitBranches()
        XCTAssertEqual(model.spaceGitBranch("space-a"), "new-checkout-branch")
        await model.selectedSession?.disconnect()
    }
    func testFirstSnapshotOpensTheFocusedSpaceAndItsActiveTabPane() async throws {
        let (model, _) = fixture()
        model.connectSelected()
        try await wait { model.spaces.count == 2 }
        XCTAssertEqual(model.selectedSpaceID, "space-a")
        XCTAssertEqual(model.selectedAgentPaneID, "pane-two")
        await model.selectedSession?.disconnect()
    }

    func testServerTabNumbersOrderTabsAndLocalChoicesSurviveRefreshAndSpaceSwitches() async throws {
        let (model, _) = fixture()
        model.connectSelected()
        try await wait { model.spaces.count == 2 }
        XCTAssertEqual(model.workspaceTabs.map(\.id), ["tab-one", "tab-two"])
        model.selectTab("tab-one")
        _ = await model.selectedSession?.refresh()
        XCTAssertEqual(model.selectedTabID, "tab-one", "Server focus must not steal a valid phone choice")
        model.selectSpace("space-b")
        XCTAssertEqual(model.selectedAgentPaneID, "pane-other")
        model.selectSpace("space-a")
        XCTAssertEqual(model.selectedTabID, "tab-one")
        model.selectTab("tab-two")
        model.selectPane("shell-two")
        model.selectTab("tab-one")
        model.selectTab("tab-two")
        XCTAssertEqual(model.selectedAgentPaneID, "shell-two", "Each actual tab restores its last viewed split pane")
        await model.selectedSession?.disconnect()
    }

    func testConnectionEditInvalidatesRememberedPaneButNameEditPreservesIt() async throws {
        let (model, _) = fixture()
        model.connectSelected()
        try await wait { model.spaces.count == 2 }
        model.selectPane("shell-two")
        var device = try XCTUnwrap(model.selectedDevice)
        device.name = "Renamed development machine"
        try model.updateDevice(device)
        XCTAssertEqual(model.selectedAgentPaneID, "shell-two")
        device.host = "different-account.example"
        try model.updateDevice(device)
        XCTAssertNil(model.selectedAgentPaneID)
        XCTAssertNil(model.selectedPaneTitle, "The previous host's title is not shown during a replacement connection")
        try await wait { model.selectedAgentPaneID != nil }
        XCTAssertEqual(model.selectedAgentPaneID, "pane-two", "Same remote IDs on a different connection do not inherit old pane memory")
        await model.selectedSession?.disconnect()
    }

    func testChatBindingEditKeepsNativeSSHAndPaneWhileHostEditRotatesItsCredentialScope() async throws {
        let (model, _) = fixture()
        model.connectSelected()
        try await wait { model.selectedTransportReady }
        let session = try XCTUnwrap(model.selectedSession)
        let pane = model.selectedAgentPaneID
        let configuration = try WebChatConfiguration(serviceURL: "https://fixture.example/", machineID: "local")
        try model.saveChatConfiguration(configuration, for: try XCTUnwrap(model.selectedDeviceID))
        XCTAssertTrue(model.selectedSession === session)
        XCTAssertEqual(model.selectedAgentPaneID, pane)
        XCTAssertTrue(model.selectedTransportReady)
        var device = try XCTUnwrap(model.selectedDevice)
        device.name = "Display rename"
        try model.updateDevice(device)
        XCTAssertEqual(model.selectedDevice?.chatConfiguration, configuration)
        device.host = "another.example"
        try model.updateDevice(device)
        XCTAssertNotEqual(model.selectedDevice?.chatConfiguration?.credentialID, configuration.credentialID)
        XCTAssertEqual(model.selectedDevice?.chatConfiguration?.serviceURL, configuration.serviceURL)
        await model.selectedSession?.disconnect()
    }

    private func fixture() -> (MobileAppModel, NavigationFixture) {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.save([MobileDevice(name: "远端开发机 · 长名称用于验证管理按钮仍可点击", host: "fixture.example", username: "developer")])
        let transport = NavigationFixture()
        return (MobileAppModel(store: store, chatCredentialRemover: { _, _ in }, connector: { _ in transport }), transport)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            if ContinuousClock.now > deadline { XCTFail("Navigation snapshot did not arrive"); throw CancellationError() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private actor NavigationFixture: MobileTransport {
    let branch: String
    let gate: GitReplyGate?
    let checkoutPath: String?
    private var changedDirectory = false
    init(branch: String = "feature/mobile-controls", gate: GitReplyGate? = nil, checkoutPath: String? = nil) {
        self.branch = branch; self.gate = gate; self.checkoutPath = checkoutPath
    }
    func changeWorkingDirectory() { changedDirectory = true }
    func gitBranch(at path: String) async throws -> String? {
        if path == checkoutPath { return "checkout-branch" }
        if path == "/different-checkout" { return "new-checkout-branch" }
        guard path == "/repo" else { return nil }
        await gate?.wait()
        return branch
    }
    func request(method: String, params: JSONValue) async throws -> JSONValue {
        if method == "ping" { return .object(["version": .string("fixture"), "protocol": .number(22)]) }
        var snapshot = Self.snapshot
        if let checkoutPath { snapshot = snapshot.replacingOccurrences(of: "\"label\":\"移动端日常开发工作区\"", with: "\"label\":\"移动端日常开发工作区\",\"worktree\":{\"checkout_path\":\"\(checkoutPath)\"}") }
        if changedDirectory { snapshot = snapshot.replacingOccurrences(of: "\"cwd\":\"/repo\"", with: "\"cwd\":\"/different-checkout\"") }
        let data = Data(snapshot.utf8)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
    nonisolated func events(kinds: [String], statusPaneIDs: [String]) -> AsyncThrowingStream<HerdrEvent, Error> {
        AsyncThrowingStream { _ in }
    }
    func openTerminal(command: String, columns: Int, rows: Int) async throws -> SSHPTYChannel { throw CancellationError() }
    func close() async {}
    static let snapshot = """
    {"snapshot":{
      "focused_workspace_id":"space-a","focused_pane_id":"pane-two",
      "workspaces":[{"workspace_id":"space-a","number":1,"label":"移动端日常开发工作区","active_tab_id":"tab-two"},{"workspace_id":"space-b","number":2,"label":"第二个同名目标的工作区","active_tab_id":"tab-other"}],
      "tabs":[{"tab_id":"tab-two","workspace_id":"space-a","number":2,"label":"执行命令"},{"tab_id":"tab-one","workspace_id":"space-a","number":1,"label":"需求设计"},{"tab_id":"tab-other","workspace_id":"space-b","number":1,"label":"需求设计"}],
      "agents":[{"workspace_id":"space-a","tab_id":"tab-one","pane_id":"pane-one","agent":"codex","agent_status":"working","name":"same-name","cwd":"/repo"},{"workspace_id":"space-a","tab_id":"tab-two","pane_id":"pane-two","agent":"claude-code","agent_status":"done","name":"same-name","cwd":"/repo"},{"workspace_id":"space-b","tab_id":"tab-other","pane_id":"pane-other","agent":"codex","agent_status":"blocked","name":"same-name","cwd":"/not-a-repository"}],
      "panes":[{"workspace_id":"space-a","tab_id":"tab-two","pane_id":"shell-two","terminal_id":"terminal-two","terminal_title":"构建服务 · 普通终端"}]
    }}
    """
}

private actor GitReplyGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    func wait() async { started = true; await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
    func waitUntilStarted() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !started {
            guard ContinuousClock.now < deadline else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
