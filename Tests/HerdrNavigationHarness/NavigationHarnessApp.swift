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
        var device = MobileDevice(id: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!, name: "远端开发机 · 长中文名称验证操作入口", host: "fixture.example", username: "developer")
        let chat = ProcessInfo.processInfo.environment["NAV_HARNESS_CHAT"] == "1"
        if chat { device.chatConfiguration = try! WebChatConfiguration(serviceURL: "https://chat-fixture.invalid/", machineID: "local") }
        store.save([device])
        let boundary = NavigationHarnessConnector()
        _model = State(initialValue: MobileAppModel(store: store,
            chatCredentialProvider: { _, _ in chat ? .token("controlled-fixture-only") : nil },
            chatServiceFactory: { configuration, credential in
                let sessionConfiguration = URLSessionConfiguration.ephemeral
                sessionConfiguration.protocolClasses = [NavigationChatHTTPBoundary.self]
                return WebChatService(configuration: configuration, credential: credential, session: URLSession(configuration: sessionConfiguration))
            }, chatCredentialRemover: { _, _ in }, connector: { _ in try await boundary.connect() }))
        if ProcessInfo.processInfo.environment["NAV_HARNESS_DARK"] == "1" { appearance.mode = .dark }
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
                    if phase == .active { model.resumeSelected() }
                    else { model.suspendSelected() }
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
    private var snapshots = 0
    init(removeSelectedPane: Bool) { self.removeSelectedPane = removeSelectedPane }
    func request(method: String, params: JSONValue) async throws -> JSONValue {
        if method == "ping" { return .object(["version": .string("fixture"), "protocol": .number(22)]) }
        snapshots += 1
        if snapshots > 1, ProcessInfo.processInfo.environment["NAV_HARNESS_RECONNECT_FAILURE"] == "1" {
            throw NSError(domain: "NavigationExternalFixture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Fixture held connection unavailable"])
        }
        let manyTabs = ProcessInfo.processInfo.environment["NAV_HARNESS_MANY_TABS"] == "1"
        let payload = try JSONDecoder().decode(JSONValue.self, from: Data((manyTabs ? Self.manyTabsSnapshot : Self.snapshot).utf8))
        guard (removeSelectedPane || snapshots > 1 && ProcessInfo.processInfo.environment["NAV_HARNESS_DELETED_PANE"] == "1"), case .object(var envelope) = payload,
              case .object(var snapshot) = envelope["snapshot"], case .array(let agents) = snapshot["agents"] else { return payload }
        snapshot["agents"] = .array(agents.filter { $0["pane_id"]?.stringValue != "pane-two" })
        envelope["snapshot"] = .object(snapshot)
        return .object(envelope)
    }
    nonisolated func events(kinds: [String], statusPaneIDs: [String]) -> AsyncThrowingStream<HerdrEvent, Error> { AsyncThrowingStream { _ in } }
    func openTerminal(command: String, columns: Int, rows: Int) async throws -> SSHPTYChannel { throw CancellationError() }
    func close() async {}
    static var manyTabsSnapshot: String {
        var text = snapshot.replacingOccurrences(of: "\"active_tab_id\":\"tab-two\"", with: "\"active_tab_id\":\"tab-four\"")
        text = text.replacingOccurrences(of: "\"focused_pane_id\":\"pane-two\"", with: "\"focused_pane_id\":\"pane-four\"")
        text = text.replacingOccurrences(of: "\"tabs\":[", with: "\"tabs\":[{\"tab_id\":\"tab-three\",\"workspace_id\":\"space-a\",\"number\":3,\"label\":\"第三个很长的项目工作任务\"},{\"tab_id\":\"tab-four\",\"workspace_id\":\"space-a\",\"number\":4,\"label\":\"第四个很长的当前工作任务\"},{\"tab_id\":\"tab-five\",\"workspace_id\":\"space-a\",\"number\":5,\"label\":\"第五个很长的项目工作任务\"},")
        text = text.replacingOccurrences(of: "\"agents\":[", with: "\"agents\":[{\"workspace_id\":\"space-a\",\"tab_id\":\"tab-four\",\"pane_id\":\"pane-four\",\"agent\":\"codex\",\"agent_status\":\"working\"},")
        return text
    }
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


/// Authenticated HTTP boundary fixture, never a real user's endpoint or transcript.
private final class NavigationChatHTTPBoundary: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "chat-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data: Data
        if request.url!.path.hasSuffix("machines") {
            data = Data(Self.machines.utf8)
        } else {
            let text = "## 真机原型验收\n\n已连接开发机，当前会话只展示这个 Space 的内容。\n\n1. 检查终端模式\n2. 切换聊天模式\n3. 返回后草稿保留\n\n```sh\nprintf 'HERDR_UI_OK\\n'\n```\n\n[打开项目预览](https://example.com)"
            let object: [String: Any] = ["history_id": "controlled-history", "source": "claude-transcript",
                "metadata": ["model": "fixture-model", "reasoning_effort": "High"],
                "turns": [["role": "user", "ts": "2026-10-11T01:00:00Z", "parts": [["kind": "text", "text": "请检查已有 Agent 的界面。"]]],
                    ["role": "assistant", "ts": "2026-10-11T01:01:00Z", "parts": [["kind": "thinking", "text": "受控夹具中的思考内容。"], ["kind": "text", "text": text]]]]]
            data = try! JSONSerialization.data(withJSONObject: object)
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static let machines = """
    {"machines":[{"id":"local","name":"Controlled development machine","kind":"local","state":"connected","enabled":true,"snapshot":{"protocol":22,"workspaces":[{"workspace_id":"space-a"},{"workspace_id":"space-b"}],"tabs":[{"tab_id":"tab-one","workspace_id":"space-a"},{"tab_id":"tab-two","workspace_id":"space-a"},{"tab_id":"tab-other","workspace_id":"space-b"}],"panes":[{"pane_id":"pane-one","tab_id":"tab-one","workspace_id":"space-a"},{"pane_id":"pane-two","tab_id":"tab-two","workspace_id":"space-a"},{"pane_id":"pane-other","tab_id":"tab-other","workspace_id":"space-b"}]}}]}
    """
}
