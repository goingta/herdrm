import XCTest
import UIKit
import WebKit
@testable import HerdrMobile

@MainActor
final class ChatTranscriptRendererTests: XCTestCase {
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
