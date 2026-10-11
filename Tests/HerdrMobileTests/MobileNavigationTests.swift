import XCTest
import SwiftUI
import HerdrKit
import HerdrSSH
@testable import HerdrMobile

@MainActor
final class MobileNavigationTests: XCTestCase {
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
    func request(method: String, params: JSONValue) async throws -> JSONValue {
        if method == "ping" { return .object(["version": .string("fixture"), "protocol": .number(22)]) }
        let data = Data(Self.snapshot.utf8)
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
      "agents":[{"workspace_id":"space-a","tab_id":"tab-one","pane_id":"pane-one","agent":"codex","agent_status":"working","name":"same-name"},{"workspace_id":"space-a","tab_id":"tab-two","pane_id":"pane-two","agent":"claude-code","agent_status":"done","name":"same-name"},{"workspace_id":"space-b","tab_id":"tab-other","pane_id":"pane-other","agent":"codex","agent_status":"blocked","name":"same-name"}],
      "panes":[{"workspace_id":"space-a","tab_id":"tab-two","pane_id":"shell-two","terminal_id":"terminal-two","terminal_title":"构建服务 · 普通终端"}]
    }}
    """
}
