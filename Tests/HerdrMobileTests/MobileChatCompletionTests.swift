import XCTest
import HerdrKit
import HerdrSSH
import UIKit
import SwiftUI
@testable import HerdrMobile

@MainActor
final class MobileChatCompletionTests: XCTestCase {
    func testColdPersistedUnreadClearsOnlyAfterVisibleLatestReplyMatchesCurrentPaneSuffix() async throws {
        try await checkColdCompletion(paneText: "\u{1B}[32m" + Self.reply + "\u{1B}[0m", shouldClear: true)
    }

    func testEarlierReplyInCurrentPaneCannotClearColdPersistedUnread() async throws {
        try await checkColdCompletion(paneText: Self.reply + "\nA newer completed answer follows this earlier reply.", shouldClear: false)
    }

    func testBindingChangeDiscardsPendingColdNativeVerification() async throws {
        try await checkColdCompletion(paneText: Self.reply, shouldClear: false, rebindWhileReading: true)
    }

    func testCoveredActualRootCannotAcknowledgeLateReplyUntilUncoveredFreshPresentation() async throws {
        try await checkColdCompletion(paneText: Self.reply, shouldClear: false, coverWhileReading: true)
    }

    private func checkColdCompletion(paneText: String, shouldClear: Bool, rebindWhileReading: Bool = false, coverWhileReading: Bool = false) async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let configuration = try WebChatConfiguration(serviceURL: "https://cold-chat.invalid", machineID: "local")
        let device = MobileDevice(name: "Fixture", host: "ssh-fixture.invalid", username: "developer", chatConfiguration: configuration)
        let key = AgentUnreadKey(deviceID: device.id, paneID: "pane")
        defaults.set(try JSONEncoder().encode(Set([key])), forKey: "agent-unread-v1")
        let readState = AgentReadState(defaults: defaults)
        let store = MobileDeviceStore(defaults: defaults)
        store.save([device])
        let transport = CompletionSSHBoundary(paneText: paneText, delayRead: rebindWhileReading || coverWhileReading)
        let urlConfiguration = URLSessionConfiguration.ephemeral
        urlConfiguration.protocolClasses = [CompletionHTTPBoundary.self]
        let model = MobileAppModel(store: store, readState: readState,
            publicKeyLine: { "ssh-ed25519 fixture-public-only fixture" },
            chatCredentialProvider: { _, _ in .token("fixture-only") },
            chatServiceFactory: { config, credential in
                WebChatService(configuration: config, credential: credential, session: URLSession(configuration: urlConfiguration))
            }, chatCredentialRemover: { _, _ in }, connector: { _ in transport })
        model.connectSelected()
        for _ in 0..<100 {
            if model.selectedTransportReady { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let target = try XCTUnwrap(model.currentPromptTarget)
        XCTAssertEqual(model.chatCompletionRevision(for: target), 0, "Cold completion must not invent a status transition")
        XCTAssertTrue(readState.unread.contains(key))
        let controller = try XCTUnwrap(model.chatController(for: target))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        let host: UIViewController = coverWhileReading
            ? UIHostingController(rootView: MobileRootView(model: model).environment(\.scenePhase, .active).environment(\.agentTabVisible, true))
            : UIViewController()
        window.rootViewController = host
        controller.renderer.webView.frame = window.bounds
        if !coverWhileReading { host.view.addSubview(controller.renderer.webView) }
        window.makeKeyAndVisible()
        defer { controller.invalidate(); window.isHidden = true }
        if !coverWhileReading { controller.setActivity(visible: true, foreground: true, connectionValidated: true, completionRevision: 0); await controller.refreshNow() }
        for _ in 0..<150 {
            if await transport.reads > 0, !shouldClear || !readState.unread.contains(key) { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        if coverWhileReading {
            model.showAddDevice = true
            try await Task.sleep(for: .milliseconds(500))
            XCTAssertEqual(controller.renderer.document?.freshContent, false, "Covered actual root must suspend chat polling and read proof")
            XCTAssertTrue(readState.unread.contains(key), "A modal over the actual mounted chat must suppress late read acknowledgement")
            model.showAddDevice = false
            for _ in 0..<120 {
                if !readState.unread.contains(key) { break }
                try await Task.sleep(for: .milliseconds(30))
            }
            XCTAssertFalse(readState.unread.contains(key), "Uncovering requires fresh current presentation before read")
        }
        if rebindWhileReading {
            try model.saveChatConfiguration(.init(serviceURL: "https://replacement.invalid", machineID: "local"), for: device.id)
            try await Task.sleep(for: .milliseconds(450))
        }
        let reads = await transport.reads
        XCTAssertGreaterThan(reads, 0, "Actual fresh mounted reply must request current pane verification")
        if !coverWhileReading { XCTAssertEqual(readState.unread.contains(key), !shouldClear) }
        await model.selectedSession?.disconnect()
    }

    fileprivate static let reply = "The current completed answer has a sufficiently long and distinct final reply tail. All checks finished successfully and this exact result is now ready for review."
}

private actor CompletionSSHBoundary: MobileTransport {
    let paneText: String
    var reads = 0
    let delayRead: Bool
    init(paneText: String, delayRead: Bool) { self.paneText = paneText; self.delayRead = delayRead }
    func request(method: String, params: JSONValue) async throws -> JSONValue {
        if method == "ping" { return .object(["version": .string("fixture"), "protocol": .number(22)]) }
        if method == "pane.read" {
            reads += 1
            if delayRead { try await Task.sleep(for: .milliseconds(300)) }
            guard params["pane_id"]?.stringValue == "pane", params["source"]?.stringValue == "visible" else { throw CancellationError() }
            return .object(["read": .object(["text": .string(paneText)])])
        }
        return try JSONDecoder().decode(JSONValue.self, from: Data(Self.snapshot.utf8))
    }
    nonisolated func events(kinds: [String], statusPaneIDs: [String]) -> AsyncThrowingStream<HerdrEvent, Error> { AsyncThrowingStream { _ in } }
    func openTerminal(command: String, columns: Int, rows: Int) async throws -> SSHPTYChannel { throw CancellationError() }
    func close() async {}
    static let snapshot = #"{"snapshot":{"focused_workspace_id":"space","focused_pane_id":"pane","workspaces":[{"workspace_id":"space","number":1,"label":"Space","active_tab_id":"tab"}],"tabs":[{"tab_id":"tab","workspace_id":"space","number":1,"label":"Task"}],"agents":[{"workspace_id":"space","tab_id":"tab","pane_id":"pane","agent":"claude","agent_status":"done"}]}}"#
}

private final class CompletionHTTPBoundary: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "cold-chat.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body: String
        if request.url!.path.hasSuffix("machines") {
            body = #"{"machines":[{"id":"local","name":"Fixture","kind":"local","state":"connected","enabled":true,"snapshot":{"protocol":22,"workspaces":[{"workspace_id":"space"}],"tabs":[{"tab_id":"tab","workspace_id":"space"}],"panes":[{"pane_id":"pane","tab_id":"tab","workspace_id":"space"}]}}]}"#
        } else {
            body = #"{"history_id":"current-history","source":"claude-transcript","turns":[{"role":"assistant","ts":"2026-10-10T01:01:00Z","parts":[{"kind":"text","text":"\#(MobileChatCompletionTests.reply)"}]}]}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
