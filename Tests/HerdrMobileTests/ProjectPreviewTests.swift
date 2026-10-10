import XCTest
import WebKit
import Network
import SwiftUI
import HerdrKit
import HerdrSSH
@testable import HerdrMobile

@MainActor
final class ProjectPreviewTests: XCTestCase {
    func testOnlyFullWebAddressesAreAcceptedWithoutChangingTheLastTarget() throws {
        let browser = ProjectPreviewBrowser()
        XCTAssertTrue(browser.open("  https://example.com:8443/project?q=hello#result  "))
        let original = try XCTUnwrap(browser.targetURL)
        for invalid in ["localhost:3000", "ssh://server/project", "javascript:alert(1)", "file:///etc/passwd", "https://", "https://user:secret@example.com", "http://example.com:70000"] {
            XCTAssertFalse(browser.open(invalid), invalid)
            XCTAssertEqual(browser.targetURL, original)
            XCTAssertNotNil(browser.errorMessage)
        }
        browser.webView.stopLoading()
    }

    func testRealBrowserNavigatesBackForwardAndRefreshesWithoutLosingItsTarget() async throws {
        let server = try PreviewHTTPFixture()
        let base = try await server.start()
        defer { server.stop() }
        let browser = ProjectPreviewBrowser()
        let window = UIWindow(frame: UIScreen.main.bounds)
        let controller = UIViewController()
        controller.view = browser.webView
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        XCTAssertTrue(browser.open(base.appendingPathComponent("first").absoluteString))
        try await wait(browser) { browser.pageTitle == "first" && !browser.isLoading }
        XCTAssertTrue(browser.open(base.appendingPathComponent("second").absoluteString))
        try await wait(browser) { browser.pageTitle == "second" && browser.canGoBack && !browser.isLoading }
        browser.goBack()
        try await wait(browser) { browser.pageTitle == "first" && browser.canGoForward && !browser.isLoading }
        browser.goForward()
        try await wait(browser) { browser.pageTitle == "second" && !browser.isLoading }
        browser.reload()
        try await wait(browser) { browser.pageTitle == "second" && !browser.isLoading }
        XCTAssertEqual(browser.targetURL?.path, "/second")
        XCTAssertNil(browser.errorMessage)
    }

    func testFailedPageCanBeRetriedInTheSameBrowser() async throws {
        let server = try PreviewHTTPFixture()
        server.responds = false
        let base = try await server.start()
        defer { server.stop() }
        let browser = ProjectPreviewBrowser()
        XCTAssertTrue(browser.open(base.appendingPathComponent("first").absoluteString))
        try await wait(browser) { browser.errorMessage != nil && !browser.isLoading }
        XCTAssertEqual(browser.targetURL?.path, "/first")
        server.responds = true
        browser.reload()
        try await wait(browser) { browser.pageTitle == "first" && !browser.isLoading }
        XCTAssertNil(browser.errorMessage)
    }

    func testSecureConnectionFailureIsVisibleAndDoesNotFallBackToHTTP() async throws {
        let server = try PreviewHTTPFixture()
        let base = try await server.start()
        defer { server.stop() }
        let browser = ProjectPreviewBrowser()
        let secureAddress = base.absoluteString.replacingOccurrences(of: "http://", with: "https://")
        XCTAssertTrue(browser.open(secureAddress))
        try await wait(browser) { browser.errorMessage != nil && !browser.isLoading }
        XCTAssertEqual(browser.targetURL?.scheme, "https")
        XCTAssertTrue(browser.errorMessage?.contains("HTTPS") == true)
        XCTAssertTrue(browser.pageTitle.isEmpty)
    }

    func testSwitchingToPreviewAndSettingsKeepsAgentSelectionAndTypedDraft() async throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let device = MobileDevice(name: "Daily", host: "fixture.example", username: "alice")
        store.save([device])
        let transport = PreviewAgentFixture()
        let model = MobileAppModel(store: store, connector: { _ in transport })
        model.connectSelected()
        let navigation = MobileWorkspaceNavigation()
        try await wait(navigation.browser) { model.agents.count == 1 }
        model.selectedAgentPaneID = "pane-1"
        let view = MobileWorkspaceView(model: model, navigation: navigation)
            .environment(AppLanguagePreference.shared)
            .environmentObject(AppAppearancePreference())
            .environment(\.horizontalSizeClass, .regular)
            .frame(width: 1024, height: 768)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        model.setAgentDraft("keep this Agent draft", paneID: "pane-1", deviceID: device.id)
        navigation.selectedTab = .preview
        XCTAssertFalse(navigation.browser.open("ssh://not-a-web-page"))
        navigation.selectedTab = .settings
        try await Task.sleep(for: .milliseconds(50))
        navigation.selectedTab = .agent
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.selectedDeviceID, device.id)
        XCTAssertEqual(model.selectedAgentPaneID, "pane-1")
        XCTAssertEqual(model.selectedConnectionState, .connected(version: "fixture"))
        XCTAssertEqual(model.agentDraft(paneID: "pane-1", deviceID: device.id), "keep this Agent draft")
        XCTAssertEqual(model.agentDraft(paneID: "other-pane", deviceID: device.id), "")
        XCTAssertEqual(model.agentDraft(paneID: "pane-1", deviceID: UUID()), "")
        await model.selectedSession?.disconnect()
    }

    private func wait(_ browser: ProjectPreviewBrowser, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            if ContinuousClock.now > deadline {
                XCTFail("Browser state: title=\(browser.pageTitle), loading=\(browser.isLoading), url=\(browser.targetURL?.absoluteString ?? "nil"), error=\(browser.errorMessage ?? "none")")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private actor PreviewAgentFixture: MobileTransport {
    func request(method: String, params: JSONValue) async throws -> JSONValue {
        if method == "ping" { return .object(["version": .string("fixture"), "protocol": .number(22)]) }
        return .object(["snapshot": .object([
            "agents": .array([.object([
                "workspace_id": .string("space-1"), "tab_id": .string("tab-1"),
                "pane_id": .string("pane-1"), "agent": .string("codex"),
                "agent_status": .string("working"), "name": .string("Existing Agent"),
            ])]),
            "workspaces": .array([.object([
                "workspace_id": .string("space-1"), "number": .number(1), "label": .string("workspace"),
            ])]),
        ])])
    }
    nonisolated func events(kinds: [String], statusPaneIDs: [String]) -> AsyncThrowingStream<HerdrEvent, Error> {
        AsyncThrowingStream { _ in }
    }
    func openTerminal(command: String, columns: Int, rows: Int) async throws -> SSHPTYChannel { throw CancellationError() }
    func close() async {}
}

/// Real HTTP boundary: WebKit fetches these pages; no delegate callbacks are simulated.
private final class PreviewHTTPFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "herdr.preview.http-fixture")
    private let lock = NSLock()
    private var shouldRespond = true
    var responds: Bool {
        get { lock.withLock { shouldRespond } }
        set { lock.withLock { shouldRespond = newValue } }
    }

    init() throws { listener = try NWListener(using: .tcp, on: .any) }

    func start() async throws -> URL {
        listener.newConnectionHandler = { [weak self, queue] connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
                guard self?.responds == true else { connection.cancel(); return }
                let request = String(decoding: data ?? Data(), as: UTF8.self)
                let path = request.split(separator: " ").dropFirst().first ?? "/"
                let title = path == "/second" ? "second" : "first"
                let html = "<html><head><title>\(title)</title></head><body>\(title)</body></html>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/")!)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }
}
