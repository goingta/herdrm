import SwiftUI
import XCTest
import GhosttyTerminal
import HerdrKit
import HerdrSSH
@testable import HerdrMobile

@MainActor
final class AppearanceTests: XCTestCase {
    func testConnectionDefiningEditCannotReusePreviousHostsRendererWithSameRemoteIDs() async throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let device = MobileDevice(name: "Daily", host: "prior.example", username: "alice")
        store.save([device])
        let model = MobileAppModel(store: store, connector: { _ in RecoveryTransport() })
        let root = MobileWorkspaceView(model: model).environment(AppLanguagePreference.shared)
            .environmentObject(AppAppearancePreference(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let host = UIHostingController(rootView: root)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await settle()
        model.selectMode(.terminal)
        try await settle()
        let prior = try XCTUnwrap(findTerminal(in: host.view))
        guard case .inMemory(let oldBackend) = prior.configuration.backend else { return XCTFail("Actual renderer expected") }
        oldBackend.receive(Data("OLD_HOST_SENSITIVE_FRAME\r\n".utf8))
        try await settle()
        var edited = device
        edited.host = "different.example"
        try model.updateDevice(edited)
        try await settle()
        model.selectMode(.terminal)
        try await settle()
        let current = try XCTUnwrap(findTerminal(in: host.view))
        XCTAssertFalse(current === prior, "Connection-defining edit must construct a new renderer even when device/Space/Tab/pane IDs are reused")
        guard case .inMemory(let currentBackend) = current.configuration.backend else { return XCTFail("Actual renderer expected") }
        XCTAssertFalse(currentBackend.readViewportText()?.contains("OLD_HOST_SENSITIVE_FRAME") == true)
        await model.selectedSession?.disconnect()
    }

    func testObsoleteAttachFailureCannotReplaceNewTransportState() async throws {
        let first = DelayedAttachTransport()
        let replacement = RecoveryTransport()
        let session = MobileAttachSession(transport: first, target: .agent(paneID: "pane"), paneID: "pane")
        let view = UITerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 500))
        view.controller = MobileGhosttyRuntime.controller
        view.configuration = TerminalSurfaceOptions(backend: .inMemory(session.terminal))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.view = view
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; session.stop() }
        session.start()
        try await settle()
        let waiting = await first.isWaiting
        XCTAssertTrue(waiting, "The external prior attach is held while its actual terminal reports a viewport")
        session.replaceTransport(replacement)
        try await settle()
        let replacementStatus = session.status
        if case .ended = replacementStatus {} else { XCTFail("Replacement attach reached its own terminal state") }
        await first.finishObsoleteAttempt()
        try await settle()
        XCTAssertEqual(session.status, replacementStatus, "An obsolete attach callback must not overwrite the replacement status")
        XCTAssertTrue(session.transport === replacement)
    }

    func testValidationAndReplacementKeepActualTerminalFrameAndDraft() async throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let device = MobileDevice(name: "Daily", host: "host.example", username: "alice")
        store.save([device])
        let boundary = RecoveryBoundary()
        let model = MobileAppModel(store: store, connector: { _ in await boundary.open() })
        let host = UIHostingController(rootView: MobileWorkspaceView(model: model).environment(AppLanguagePreference.shared).environmentObject(AppAppearancePreference(defaults: UserDefaults(suiteName: UUID().uuidString)!)))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await settle()
        model.selectMode(.terminal)
        try await settle()
        let view = try XCTUnwrap(findTerminal(in: host.view))
        guard case .inMemory(let backend) = view.configuration.backend else { return XCTFail("Real Ghostty expected") }
        backend.receive(Data("保留已有终端画面 RECOVERY_FRAME\r\n".utf8))
        model.setAgentDraft("retained unsent prompt", paneID: "recovery-pane", deviceID: device.id)
        try await settle()
        await boundary.first.holdValidation()
        model.connectSelected()
        try await settle()
        XCTAssertTrue(findTerminal(in: host.view) === view, "Validation keeps the current actual terminal view")
        XCTAssertTrue(try XCTUnwrap(backend.readViewportText()).contains("RECOVERY_FRAME"))
        XCTAssertEqual(model.agentDraft(paneID: "recovery-pane", deviceID: device.id), "retained unsent prompt")
        await boundary.first.releaseValidation(failed: true)
        try await settle()
        try await settle()
        XCTAssertTrue(findTerminal(in: host.view) === view, "Replacement transport reuses the actual renderer")
        XCTAssertTrue(try XCTUnwrap(backend.readViewportText()).contains("RECOVERY_FRAME"))
        XCTAssertEqual(model.selectedAgentPaneID, "recovery-pane")
        await model.selectedSession?.disconnect()
    }

    func testLiveTerminalChangesModeWithoutReplacingSurfaceOrOpeningAnotherAttach() async throws {
        let preference = AppAppearancePreference(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preference.mode = .dark
        let transport = AppearanceTransport()
        let root = AppearanceHarness(preference: preference, transport: transport)
        let hosting = UIHostingController(rootView: root)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.view.layoutIfNeeded()
        defer { window.isHidden = true }
        try await settle()
        let terminal = try XCTUnwrap(findTerminal(in: hosting.view))
        guard case .inMemory(let backend) = terminal.configuration.backend else {
            return XCTFail("Expected a live in-memory terminal")
        }
        backend.receive(Data("中文终端 你好\r\n\u{1b}[32mANSI green\u{1b}[0m".utf8))
        try await settle()
        let opens = await transport.opens
        XCTAssertEqual(terminal.traitCollection.userInterfaceStyle, .dark)

        preference.mode = .light
        try await settle()
        let after = try XCTUnwrap(findTerminal(in: hosting.view))
        XCTAssertTrue(after === terminal, "Mode changes must retain the existing terminal view")
        XCTAssertEqual(after.traitCollection.userInterfaceStyle, .light)
        XCTAssertEqual(MobileGhosttyRuntime.controller.effectiveColorScheme, .light)
        XCTAssertTrue(try XCTUnwrap(backend.readViewportText()).contains("中文终端 你好"))
        let subsequentOpens = await transport.opens
        XCTAssertEqual(subsequentOpens, opens, "Appearance must never re-open the remote terminal")
        preference.mode = .dark
        try await settle()
        XCTAssertEqual(terminal.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(MobileGhosttyRuntime.controller.effectiveColorScheme, .dark)
        XCTAssertTrue(try XCTUnwrap(backend.readViewportText()).contains("ANSI green"))
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(300))
    }

    private func findTerminal(in view: UIView) -> UITerminalView? {
        if let terminal = view as? UITerminalView { return terminal }
        return view.subviews.lazy.compactMap { self.findTerminal(in: $0) }.first
    }

    func testAppearanceDefaultsToSystemAndRestoresUserSelection() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preference = AppAppearancePreference(defaults: defaults)
        XCTAssertEqual(preference.mode, .system)
        XCTAssertNil(preference.preferredColorScheme)
        preference.mode = .light
        let relaunched = AppAppearancePreference(defaults: defaults)
        XCTAssertEqual(relaunched.mode, .light)
        XCTAssertEqual(relaunched.preferredColorScheme, .light)
        relaunched.mode = .dark
        XCTAssertEqual(AppAppearancePreference(defaults: defaults).preferredColorScheme, .dark)
        relaunched.mode = .system
        XCTAssertNil(AppAppearancePreference(defaults: defaults).preferredColorScheme)
    }
}

private struct AppearanceHarness: View {
    @ObservedObject var preference: AppAppearancePreference
    let transport: AppearanceTransport
    var body: some View {
        MobileTerminalScreen(transport: transport, target: .agent(paneID: "appearance-test"), paneID: "appearance-test", title: "Terminal")
            .preferredColorScheme(preference.preferredColorScheme)
    }
}

/// External SSH boundary only. The real Ghostty surface is hosted above.
private actor AppearanceTransport: MobileTransport {
    var opens = 0
    func request(method: String, params: JSONValue) async throws -> JSONValue { .null }
    nonisolated func events(kinds: [String], statusPaneIDs: [String]) -> AsyncThrowingStream<HerdrEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func openTerminal(command: String, columns: Int, rows: Int) async throws -> SSHPTYChannel {
        opens += 1
        throw MobileTransportError.tailcatTerminalUnsupported
    }
    func close() async {}
}

private actor RecoveryBoundary {
    let first = RecoveryTransport()
    private var opened = false
    func open() -> MobileTransport {
        if !opened { opened = true; return first }
        return RecoveryTransport()
    }
}

private actor RecoveryTransport: MobileTransport {
    private var shouldHold = false
    private var pending: CheckedContinuation<JSONValue, Error>?
    func holdValidation() { shouldHold = true }
    func releaseValidation(failed: Bool) {
        shouldHold = false
        if failed { pending?.resume(throwing: CancellationError()) }
        else { pending?.resume(returning: Self.snapshot) }
        pending = nil
    }
    func request(method: String, params: JSONValue) async throws -> JSONValue {
        if method == "ping" { return .object(["version": .string("fixture"), "protocol": .number(22)]) }
        if shouldHold { return try await withCheckedThrowingContinuation { pending = $0 } }
        return Self.snapshot
    }
    nonisolated func events(kinds: [String], statusPaneIDs: [String]) -> AsyncThrowingStream<HerdrEvent, Error> { AsyncThrowingStream { _ in } }
    func openTerminal(command: String, columns: Int, rows: Int) async throws -> SSHPTYChannel { throw MobileTransportError.tailcatTerminalUnsupported }
    func close() async {}
    static var snapshot: JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data("""
    {"snapshot":{"focused_workspace_id":"recovery-space","focused_pane_id":"recovery-pane","workspaces":[{"workspace_id":"recovery-space","number":1,"label":"Daily","active_tab_id":"recovery-tab"}],"tabs":[{"tab_id":"recovery-tab","workspace_id":"recovery-space","number":1,"label":"Task"}],"agents":[{"workspace_id":"recovery-space","tab_id":"recovery-tab","pane_id":"recovery-pane","agent":"codex","agent_status":"working","name":"Task"}]}}
    """.utf8)) }
}

private actor DelayedAttachTransport: MobileTransport {
    private var pending: CheckedContinuation<SSHPTYChannel, Error>?
    var isWaiting: Bool { pending != nil }
    func finishObsoleteAttempt() {
        pending?.resume(throwing: NSError(domain: "Obsolete attach", code: 1, userInfo: [NSLocalizedDescriptionKey: "OBSOLETE_ATTACH_FAILURE"]))
        pending = nil
    }
    func request(method: String, params: JSONValue) async throws -> JSONValue { .null }
    nonisolated func events(kinds: [String], statusPaneIDs: [String]) -> AsyncThrowingStream<HerdrEvent, Error> { AsyncThrowingStream { _ in } }
    func openTerminal(command: String, columns: Int, rows: Int) async throws -> SSHPTYChannel {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func close() async {}
}
