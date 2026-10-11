import XCTest
import Foundation
import UIKit
import WebKit
@testable import HerdrMobile

@MainActor
final class ChatTranscriptControllerTests: XCTestCase {
    func testCompletionDoesNotAcknowledgeOldReplyAfterFreshRequest() async throws {
        let fixture = TranscriptHTTPFixture()
        let service = try fixture.service()
        let target = WebChatTarget(nativeDeviceID: UUID(), presentationID: UUID(), spaceID: "space", tabID: "tab", paneID: "pane")
        let controller = ChatTranscriptController(target: target, service: service)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let host = UIViewController()
        window.rootViewController = host
        controller.renderer.webView.frame = window.bounds
        host.view.addSubview(controller.renderer.webView)
        window.makeKeyAndVisible()
        defer { controller.invalidate(); window.isHidden = true }
        let initial = expectation(description: "Initial actual reply presented")
        controller.onPresented = { _ in initial.fulfill() }
        controller.setActivity(visible: true, foreground: true, connectionValidated: true, completionRevision: 0)
        await controller.refreshNow()
        await fulfillment(of: [initial], timeout: 10)
        let stale = expectation(description: "Old content cannot prove new completion")
        stale.isInverted = true
        controller.onPresented = { _ in stale.fulfill() }
        controller.setActivity(visible: true, foreground: true, connectionValidated: true, completionRevision: 1)
        await controller.refreshNow()
        await fulfillment(of: [stale], timeout: 0.5)
        let latest = expectation(description: "Current completion actually visible")
        controller.onPresented = { proof in
            XCTAssertEqual(proof.completionRevision, 1)
            latest.fulfill()
        }
        fixture.setReply("new completed result")
        await controller.refreshNow()
        await fulfillment(of: [latest], timeout: 10)
    }

    func testReplyArrivingWhileWorkingRemainsProvableAfterCompletionEdge() async throws {
        let fixture = TranscriptHTTPFixture()
        let controller = ChatTranscriptController(target: .init(nativeDeviceID: UUID(), presentationID: UUID(), spaceID: "space", tabID: "tab", paneID: "pane"), service: try fixture.service())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let host = UIViewController()
        window.rootViewController = host
        controller.renderer.webView.frame = window.bounds
        host.view.addSubview(controller.renderer.webView)
        window.makeKeyAndVisible()
        defer { controller.invalidate(); window.isHidden = true }
        controller.setActivity(visible: true, foreground: true, connectionValidated: true, completionRevision: 0)
        await controller.refreshNow()
        controller.observeAgentWorking(true)
        fixture.setReply("final result arrived before native done event")
        await controller.refreshNow()
        controller.observeAgentWorking(false)
        let ready = expectation(description: "Reply belongs to the completed working cycle")
        controller.onPresented = { proof in
            if proof.completionRevision == 1 { ready.fulfill() }
        }
        controller.setActivity(visible: true, foreground: true, connectionValidated: true, completionRevision: 1)
        await controller.refreshNow()
        await fulfillment(of: [ready], timeout: 5)
    }

    func testVerifiedColdReplyIsAcceptedOnlyForStillCurrentVisibleDocument() async throws {
        let fixture = TranscriptHTTPFixture()
        let controller = ChatTranscriptController(target: .init(nativeDeviceID: UUID(), presentationID: UUID(), spaceID: "space", tabID: "tab", paneID: "pane"), service: try fixture.service())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let host = UIViewController()
        window.rootViewController = host
        controller.renderer.webView.frame = window.bounds
        host.view.addSubview(controller.renderer.webView)
        window.makeKeyAndVisible()
        defer { controller.invalidate(); window.isHidden = true }
        var candidate: ChatVisibleReplyCandidate?
        let visible = expectation(description: "Cold reply actually mounted")
        controller.onVisibleLatestReply = { value in candidate = value; visible.fulfill() }
        controller.setActivity(visible: true, foreground: true, connectionValidated: true, completionRevision: 0)
        await controller.refreshNow()
        await fulfillment(of: [visible], timeout: 5)
        let verified = expectation(description: "Fresh current pane verification accepted")
        controller.onPresented = { proof in if proof.verifiedByCurrentPane { verified.fulfill() } }
        controller.acceptVerifiedCompletion(candidate: try XCTUnwrap(candidate))
        await fulfillment(of: [verified], timeout: 5)
        let stale = try XCTUnwrap(candidate)
        controller.onVisibleLatestReply = nil
        fixture.replaceHistory()
        await controller.refreshNow()
        let rejected = expectation(description: "Old history verification rejected")
        rejected.isInverted = true
        controller.onPresented = { proof in if proof.verifiedByCurrentPane { rejected.fulfill() } }
        controller.acceptVerifiedCompletion(candidate: stale)
        await fulfillment(of: [rejected], timeout: 0.3)
    }

    func testDistinctTurnsWithSameProviderTimestampSurviveRefresh() async throws {
        let fixture = TranscriptHTTPFixture()
        fixture.useRepeatedTimestamp()
        let controller = ChatTranscriptController(target: .init(nativeDeviceID: UUID(), presentationID: UUID(), spaceID: "space", tabID: "tab", paneID: "pane"), service: try fixture.service())
        controller.setActivity(visible: true, foreground: true, connectionValidated: true, completionRevision: 0)
        defer { controller.invalidate() }
        await controller.refreshNow()
        await controller.refreshNow()
        let texts = controller.renderer.document?.turns.compactMap { $0.parts.first?.text }
        XCTAssertEqual(texts, ["first distinct reply", "second distinct reply"])
    }

    func testMovingLatestWindowFillsCursorGapWithoutSkippingTurns() async throws {
        let fixture = TranscriptHTTPFixture()
        let controller = ChatTranscriptController(target: .init(nativeDeviceID: UUID(), presentationID: UUID(), spaceID: "space", tabID: "tab", paneID: "pane"), service: try fixture.service())
        controller.setActivity(visible: true, foreground: true, connectionValidated: true, completionRevision: 0)
        defer { controller.invalidate() }
        await controller.refreshNow()
        await controller.loadOlderNow()
        fixture.advanceWindow()
        await controller.refreshNow()
        XCTAssertEqual(controller.renderer.document?.turns.compactMap { $0.parts.first?.text }, ["older prompt", "latest answer", "middle appended answer", "newest answer"])
    }

    func testPagingAndHistoryReplacementKeepOnlyCurrentConversation() async throws {
        let fixture = TranscriptHTTPFixture()
        let service = try fixture.service()
        let target = WebChatTarget(nativeDeviceID: UUID(), presentationID: UUID(), spaceID: "space", tabID: "tab", paneID: "pane")
        let controller = ChatTranscriptController(target: target, service: service)
        controller.setActivity(visible: true, foreground: true, connectionValidated: true, completionRevision: 0)
        defer { controller.invalidate() }
        await controller.refreshNow()
        XCTAssertEqual(controller.conversation?.historyID, "first")
        await controller.loadOlderNow()
        XCTAssertEqual(controller.conversation?.turns.count, 2)
        fixture.replaceHistory()
        await controller.refreshNow()
        XCTAssertEqual(controller.conversation?.historyID, "second")
        XCTAssertEqual(controller.conversation?.turns.count, 1)
        XCTAssertEqual(controller.renderer.document?.turns.first?.parts.first?.text, "replacement answer")
    }
}

private final class TranscriptHTTPFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var replaced = false
    private var advanced = false
    func advanceWindow() { lock.withLock { advanced = true } }
    private var repeatedTimestamp = false
    func useRepeatedTimestamp() { lock.withLock { repeatedTimestamp = true } }
    private var reply = "latest answer"
    func setReply(_ text: String) { lock.withLock { reply = text } }
    func replaceHistory() { lock.withLock { replaced = true } }
    func service() throws -> WebChatService {
        TranscriptURLProtocol.handler = { [self] request in
            if request.url!.path.hasSuffix("machines") {
                return #"{"machines":[{"id":"local","name":"Fixture","kind":"local","state":"connected","enabled":true,"snapshot":{"protocol":22,"workspaces":[{"workspace_id":"space"}],"tabs":[{"tab_id":"tab","workspace_id":"space"}],"panes":[{"pane_id":"pane","tab_id":"tab","workspace_id":"space"}]}}]}"#
            }
            if lock.withLock({ repeatedTimestamp }) {
                return #"{"history_id":"repeated","source":"claude-transcript","cursor":null,"turns":[{"role":"assistant","ts":"2026-10-10T01:01:00Z","parts":[{"kind":"text","text":"first distinct reply"}]},{"role":"assistant","ts":"2026-10-10T01:01:00Z","parts":[{"kind":"text","text":"second distinct reply"}]}]}"#
            }
            if lock.withLock({ advanced }) {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
                if query.contains(where: { $0.name == "since" }) {
                    return #"{"history_id":"first","source":"claude-transcript","cursor":"page-two","turns":[{"role":"assistant","ts":"2026-10-10T01:01:00Z","parts":[{"kind":"text","text":"latest answer"}]},{"role":"assistant","ts":"2026-10-10T01:02:00Z","parts":[{"kind":"text","text":"middle appended answer"}]}]}"#
                }
                return #"{"history_id":"first","source":"claude-transcript","cursor":"page-four","turns":[{"role":"assistant","ts":"2026-10-10T01:04:00Z","parts":[{"kind":"text","text":"newest answer"}]}]}"#
            }
            let second = lock.withLock { replaced }
            let older = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "before" } == true
            let text = second ? "replacement answer" : older ? "older prompt" : lock.withLock { reply }
            let role = older && !second ? "user" : "assistant"
            let stamp = older && !second ? "2026-10-10T01:00:00Z" : "2026-10-10T01:01:00Z"
            let history = second ? "second" : "first"
            let cursor = older || second ? "null" : "\"page-two\""
            return #"{"history_id":"\#(history)","source":"claude-transcript","cursor":\#(cursor),"turns":[{"role":"\#(role)","ts":"\#(stamp)","parts":[{"kind":"text","text":"\#(text)"}]}]}"#
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranscriptURLProtocol.self]
        return WebChatService(configuration: try .init(serviceURL: "https://fixture.invalid/", machineID: "local"), credential: .token("fixture-only"), session: URLSession(configuration: configuration))
    }
}

private final class TranscriptURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) -> String)?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = Self.handler?(request) ?? "{}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
