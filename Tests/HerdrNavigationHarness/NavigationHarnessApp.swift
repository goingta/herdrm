import SwiftUI
import HerdrKit
import HerdrSSH

/// Test-only app: the production workspace with an external transport fixture.
@main
struct NavigationHarnessApp: App {
    @State private var model: MobileAppModel
    @State private var language = AppLanguagePreference.shared
    @StateObject private var appearance = AppAppearancePreference()
    @Environment(\.scenePhase) private var phase
    init() {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: "herdr.navigation.fixture")!)
        store.save([MobileDevice(id: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!, name: "远端开发机 · 长中文名称验证操作入口", host: "fixture.example", username: "developer")])
        let boundary = NavigationHarnessConnector()
        _model = State(initialValue: MobileAppModel(store: store, connector: { _ in try await boundary.connect() }))
    }
    var body: some Scene {
        WindowGroup {
            MobileWorkspaceView(model: model)
                .environment(language)
                .environment(\.locale, language.locale)
                .environmentObject(appearance)
                .preferredColorScheme(appearance.preferredColorScheme)
                .tint(Theme.accent)
                .environment(\.dynamicTypeSize, ProcessInfo.processInfo.environment["NAV_HARNESS_LARGE_TEXT"] == "1" ? .accessibility3 : .large)
                .onChange(of: phase) { _, phase in
                    if phase == .active, case .connected = model.selectedConnectionState { model.connectSelected() }
                }
        }
    }
}

private actor NavigationHarnessConnector {
    private var calls = 0
    func connect() async throws -> MobileTransport {
        calls += 1
        if calls > 1, ProcessInfo.processInfo.environment["NAV_HARNESS_RECONNECT_FAILURE"] == "1" {
            try await Task.sleep(for: .seconds(4))
            throw NSError(domain: "NavigationExternalFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture connection interrupted"])
        }
        return NavigationHarnessTransport(removeSelectedPane: calls > 1 && ProcessInfo.processInfo.environment["NAV_HARNESS_DELETED_PANE"] == "1")
    }
}

private actor NavigationHarnessTransport: MobileTransport {
    let removeSelectedPane: Bool
    init(removeSelectedPane: Bool) { self.removeSelectedPane = removeSelectedPane }
    func request(method: String, params: JSONValue) async throws -> JSONValue {
        if method == "ping" { return .object(["version": .string("fixture"), "protocol": .number(22)]) }
        let payload = try JSONDecoder().decode(JSONValue.self, from: Data(Self.snapshot.utf8))
        guard removeSelectedPane, case .object(var envelope) = payload,
              case .object(var snapshot) = envelope["snapshot"], case .array(let agents) = snapshot["agents"] else { return payload }
        snapshot["agents"] = .array(agents.filter { $0["pane_id"]?.stringValue != "pane-two" })
        envelope["snapshot"] = .object(snapshot)
        return .object(envelope)
    }
    nonisolated func events(kinds: [String], statusPaneIDs: [String]) -> AsyncThrowingStream<HerdrEvent, Error> { AsyncThrowingStream { _ in } }
    func openTerminal(command: String, columns: Int, rows: Int) async throws -> SSHPTYChannel { throw CancellationError() }
    func close() async {}
    static let snapshot = """
    {"snapshot":{
      "focused_workspace_id":"space-a","focused_pane_id":"pane-two",
      "workspaces":[{"workspace_id":"space-a","number":1,"label":"移动端日常开发工作区","active_tab_id":"tab-two"},{"workspace_id":"space-b","number":2,"label":"第二个同名目标的工作区","active_tab_id":"tab-other"}],
      "tabs":[{"tab_id":"tab-one","workspace_id":"space-a","number":1,"label":"需求设计"},{"tab_id":"tab-two","workspace_id":"space-a","number":2,"label":"执行命令"},{"tab_id":"tab-other","workspace_id":"space-b","number":1,"label":"需求设计"}],
      "agents":[{"workspace_id":"space-a","tab_id":"tab-one","pane_id":"pane-one","agent":"codex","agent_status":"working","name":"same-name"},{"workspace_id":"space-a","tab_id":"tab-two","pane_id":"pane-two","agent":"claude-code","agent_status":"done","name":"same-name"},{"workspace_id":"space-b","tab_id":"tab-other","pane_id":"pane-other","agent":"codex","agent_status":"blocked","name":"same-name"}],
      "panes":[{"workspace_id":"space-a","tab_id":"tab-two","pane_id":"shell-two","terminal_id":"terminal-two","terminal_title":"构建服务 · 普通终端"}]
    }}
    """
}
