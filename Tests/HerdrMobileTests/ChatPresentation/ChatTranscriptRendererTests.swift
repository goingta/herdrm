import XCTest
import UIKit
import WebKit
@testable import HerdrMobile

@MainActor
final class ChatTranscriptRendererTests: XCTestCase {
    func testWorkHeaderLocalizesActualDurationAndKeepsWaitingLiveDespiteEndTimestamp() async throws {
        let renderer = ChatTranscriptRenderer()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let host = UIViewController(); window.rootViewController = host
        renderer.webView.frame = window.bounds; host.view.addSubview(renderer.webView); window.makeKeyAndVisible()
        defer { window.isHidden = true }
        var turn = ChatRenderTurn(role: "assistant", timestamp: "2026-10-10T12:00:00Z", parts: [.init(kind: "tool", name: "Read", output: "File")], endTimestamp: "2026-10-10T12:00:06Z")
        var doc = ChatRenderDocument(targetKey: "pane", historyID: "history", revision: "done", source: "codex-transcript", turns: [turn], language: "zh", labels: ["workedFor":"工作了", "waiting":"需要你回应", "working":"正在工作…"])
        renderer.present(doc)
        try await waitForPage(renderer) { ($0 as? String)?.contains("工作了") == true }
        var title = try await renderer.webView.evaluateJavaScript("document.querySelector('.work-block-head').innerText") as? String
        XCTAssertTrue(title?.contains("工作了 6 秒") == true)
        XCTAssertTrue(title?.contains("读取 1 个文件") == true)
        turn.live = true; turn.waiting = true; doc.turns = [turn]; doc.revision = "blocked"
        renderer.present(doc)
        try await waitForPage(renderer) { ($0 as? String)?.contains("需要你回应") == true }
        title = try await renderer.webView.evaluateJavaScript("document.querySelector('.work-block-title').innerText") as? String
        XCTAssertEqual(title, "需要你回应")
        turn.waiting = false; doc.turns = [turn]; doc.revision = "working"; renderer.present(doc)
        try await waitForPage(renderer) { ($0 as? String)?.contains("正在工作…") == true }
    }

    func testReferenceTurnGroupsWorkAndUsesRoleSpecificCopyControls() async throws {
        let renderer = ChatTranscriptRenderer()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let host = UIViewController()
        window.rootViewController = host
        renderer.webView.frame = window.bounds
        host.view.addSubview(renderer.webView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        renderer.present(.init(targetKey: "pane", historyID: "history", revision: "grouped", source: "codex-transcript", turns: [
            .init(role: "user", timestamp: "2026-10-10T12:00:00Z", parts: [.init(kind: "text", text: "Please inspect")]),
            .init(role: "assistant", timestamp: "2026-10-10T12:00:00Z", parts: [
                .init(kind: "thinking", text: "Inspect the source"),
                .init(kind: "tool", name: "Read", input: "fixture.swift", output: "Safe fixture"),
                .init(kind: "text", text: "Reading now", phase: "commentary"),
                .init(kind: "text", text: "Final reply", phase: "final_answer")])
        ]))
        try await waitForPage(renderer) { ($0 as? String)?.contains("Final reply") == true }
        let blocks = try await renderer.webView.evaluateJavaScript("document.querySelectorAll('.work-block').length") as? Int
        XCTAssertEqual(blocks, 1)
        let userCopies = try await renderer.webView.evaluateJavaScript("document.querySelectorAll('.chat-turn-user .chat-meta-btn').length") as? Int
        XCTAssertEqual(userCopies, 1)
        let agentCopies = try await renderer.webView.evaluateJavaScript("document.querySelectorAll('.chat-turn-agent > .chat-turn-meta .chat-meta-btn').length") as? Int
        XCTAssertEqual(agentCopies, 2)
        let folded = try await renderer.webView.evaluateJavaScript("document.querySelector('.work-block')?.classList.contains('is-folded')") as? Bool
        XCTAssertEqual(folded, true)
        _ = try await renderer.webView.evaluateJavaScript("document.querySelector('.chat-turn-agent > .chat-turn-meta .chat-meta-btn').click()")
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(UIPasteboard.general.string, "Final reply")
    }

    func testLatestReplyProofWaitsForLastFinalPartInViewport() async throws {
        let renderer = ChatTranscriptRenderer()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let host = UIViewController()
        window.rootViewController = host
        renderer.webView.frame = window.bounds
        host.view.addSubview(renderer.webView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        renderer.setVisible(true)
        var document = ChatRenderDocument(targetKey: "same-pane", historyID: "history", revision: "cached", source: "claude-transcript", turns: [
            .init(role: "assistant", timestamp: nil, parts: [
                .init(kind: "text", text: Array(repeating: "Earlier content filling the viewport.", count: 100).joined(separator: "\n\n")),
                .init(kind: "text", text: "Latest final result")
            ])
        ])
        document.readinessAllowed = false
        renderer.present(document)
        try await waitForPage(renderer) { ($0 as? String)?.contains("Latest final result") == true }
        _ = try await renderer.webView.evaluateJavaScript("document.getElementById('chat').scrollTop=0")
        let notVisible = expectation(description: "Earlier text does not prove latest result")
        notVisible.isInverted = true
        renderer.onPresented = { _ in notVisible.fulfill() }
        document.revision = "fresh"
        document.readinessAllowed = true
        renderer.present(document)
        await fulfillment(of: [notVisible], timeout: 0.5)
        let nowVisible = expectation(description: "Latest final part visible after scrolling")
        renderer.onPresented = { _ in nowVisible.fulfill() }
        _ = try await renderer.webView.evaluateJavaScript("document.getElementById('bottom').click()")
        await fulfillment(of: [nowVisible], timeout: 5)
    }

    func testOfflineReloadRetainsFoldAndViewportWithoutReportingCachedReadiness() async throws {
        let renderer = ChatTranscriptRenderer()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let host = UIViewController()
        window.rootViewController = host
        renderer.webView.frame = window.bounds
        host.view.addSubview(renderer.webView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        renderer.setVisible(true)
        var document = ChatRenderDocument(targetKey: "pane", historyID: "history", revision: "retained", source: "claude-transcript", turns: [
            .init(role: "assistant", timestamp: nil, parts: [.init(kind: "thinking", text: "Retained thinking"), .init(kind: "text", text: Array(repeating: "Long retained reply.", count: 100).joined(separator: "\n\n"))])
        ])
        document.readinessAllowed = false
        renderer.present(document)
        try await waitForPage(renderer) { ($0 as? String)?.contains("Long retained reply") == true }
        _ = try await renderer.webView.evaluateJavaScript("document.querySelector('details').open=true;document.getElementById('chat').scrollTop=240")
        try await Task.sleep(for: .milliseconds(100))
        let cached = expectation(description: "Reloaded cached document cannot prove read")
        cached.isInverted = true
        renderer.onPresented = { _ in cached.fulfill() }
        renderer.reloadRetainingContext()
        try await waitForPage(renderer) { ($0 as? String)?.contains("Long retained reply") == true }
        await fulfillment(of: [cached], timeout: 0.2)
        let open = try await renderer.webView.evaluateJavaScript("document.querySelector('details').open") as? Bool
        let top = try await renderer.webView.evaluateJavaScript("document.getElementById('chat').scrollTop") as? Double
        XCTAssertEqual(open, true)
        XCTAssertEqual(top ?? 0, 240, accuracy: 2)
    }

    func testValidatedImageSurvivesFreshRevisionButCannotCrossHistory() async throws {
        let renderer = ChatTranscriptRenderer()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let host = UIViewController()
        window.rootViewController = host
        renderer.webView.frame = window.bounds
        host.view.addSubview(renderer.webView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        var document = ChatRenderDocument(targetKey: "pane", historyID: "first", revision: "request-start", source: "claude-transcript", turns: [
            .init(role: "assistant", timestamp: nil, parts: [.init(kind: "image", ref: "opaque-image")], key: "turn")
        ])
        renderer.present(document)
        try await waitForPage(renderer) { ($0 as? String)?.contains("Load image") == true }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).pngData { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let proof = ChatRendererProof(targetKey: "pane", historyID: "first", revision: "request-start")
        document.revision = "fresh-poll"
        renderer.present(document)
        renderer.displayImage(image, contentType: "image/png", key: "turn:0:image", ref: "opaque-image", proof: proof)
        try await Task.sleep(for: .milliseconds(200))
        let before = try await renderer.webView.evaluateJavaScript("document.querySelectorAll('.chat-image').length") as? Int
        XCTAssertEqual(before, 1)
        document.historyID = "replacement"
        document.revision = "replacement"
        renderer.present(document)
        renderer.displayImage(image, contentType: "image/png", key: "turn:0:image", ref: "opaque-image", proof: proof)
        try await Task.sleep(for: .milliseconds(200))
        let after = try await renderer.webView.evaluateJavaScript("document.querySelectorAll('.chat-image').length") as? Int
        XCTAssertEqual(after, 0)
    }

    func testCopyControlsUseReferenceGlyphAndNativePlainTextWithoutExecutingHTML() async throws {
        let renderer = ChatTranscriptRenderer()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let host = UIViewController()
        window.rootViewController = host
        renderer.webView.frame = window.bounds
        host.view.addSubview(renderer.webView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        renderer.present(.init(targetKey: "pane", historyID: "history", revision: "copy", source: "claude-transcript", turns: [
            .init(role: "assistant", timestamp: nil, parts: [.init(kind: "text", text: "**Bold** and `code`.\n\n<script>window.attacked=1</script>")])
        ]))
        try await waitForPage(renderer) { ($0 as? String)?.contains("Bold") == true }
        let icon = try await renderer.webView.evaluateJavaScript("document.querySelector('.copy-icon') !== null") as? Bool
        XCTAssertEqual(icon, true)
        _ = try await renderer.webView.evaluateJavaScript("[...document.querySelectorAll('.chat-meta-btn')].find(b=>b.textContent.includes('TXT')).click()")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(UIPasteboard.general.string?.hasPrefix("Bold and code.") == true)
        let executed = try await renderer.webView.evaluateJavaScript("Boolean(window.attacked)") as? Bool
        XCTAssertEqual(executed, false)
    }

    func testLongToolOutputReportsDisplayLimitInsteadOfSilentlyTruncating() async throws {
        let renderer = ChatTranscriptRenderer()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let host = UIViewController()
        window.rootViewController = host
        renderer.webView.frame = window.bounds
        host.view.addSubview(renderer.webView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        renderer.present(.init(targetKey: "pane", historyID: "history", revision: "tool", source: "claude-transcript", turns: [
            .init(role: "assistant", timestamp: nil, parts: [.init(kind: "tool", name: "Read", ref: "opaque-tool")], key: "turn")
        ]))
        try await waitForPage(renderer) { ($0 as? String)?.contains("Read") == true }
        renderer.displayToolOutput(String(repeating: "x", count: 500_001), key: "turn:0:tool", ref: "opaque-tool", proof: .init(targetKey: "pane", historyID: "history", revision: "tool"))
        _ = try await renderer.webView.evaluateJavaScript("document.querySelector('details').open=true")
        try await Task.sleep(for: .milliseconds(100))
        let notice = try await renderer.webView.evaluateJavaScript("document.querySelector('[data-full-output]')?.textContent.includes('display limit')") as? Bool
        XCTAssertEqual(notice, true)
    }

    private func waitForPage(_ renderer: ChatTranscriptRenderer, _ condition: (Any?) -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            let text = try? await renderer.webView.evaluateJavaScript("document.body.innerText")
            if condition(text) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Actual transcript page did not load")
        throw CancellationError()
    }

    func testMountedTranscriptRendersMarkdownAndReportsVisibleLatestReply() async throws {
        let renderer = ChatTranscriptRenderer()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let host = UIViewController()
        window.rootViewController = host
        renderer.webView.frame = window.bounds
        host.view.addSubview(renderer.webView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let ready = expectation(description: "Actual latest reply displayed")
        renderer.onPresented = { proof in
            XCTAssertEqual(proof.historyID, "history-one")
            ready.fulfill()
        }
        renderer.setVisible(true)
        renderer.present(.init(targetKey: "machine-pane", historyID: "history-one", revision: "reply-one", source: "claude-transcript", turns: [
            .init(role: "assistant", timestamp: nil, parts: [.init(kind: "text", text: "## 真机原型\n\n1. **已完成**\n2. `IPHONE_POC_OK`\n\n```swift\nprint(\"ready\")\n```")])
        ]))
        await fulfillment(of: [ready], timeout: 10)
        let visible = try await renderer.webView.evaluateJavaScript("document.body.innerText") as? String
        XCTAssertTrue(visible?.contains("真机原型") == true)
        XCTAssertTrue(visible?.contains("IPHONE_POC_OK") == true)
        XCTAssertFalse(visible?.contains("## 真机原型") == true)
        let heading = try await renderer.webView.evaluateJavaScript("document.querySelector('h2')?.textContent") as? String
        XCTAssertEqual(heading, "真机原型")
    }
}
