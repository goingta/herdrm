import XCTest
import WebKit
import Network
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

    private func wait(_ browser: ProjectPreviewBrowser, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            if ContinuousClock.now > deadline {
                print("WK contents:", try await browser.webView.evaluateJavaScript("document.documentElement.outerHTML"))
                XCTFail("Browser state: title=\(browser.pageTitle), loading=\(browser.isLoading), url=\(browser.targetURL?.absoluteString ?? "nil"), error=\(browser.errorMessage ?? "none")")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// Real HTTP boundary: WebKit fetches these pages; no delegate callbacks are simulated.
private final class PreviewHTTPFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "herdr.preview.http-fixture")

    init() throws { listener = try NWListener(using: .tcp, on: .any) }

    func start() async throws -> URL {
        listener.newConnectionHandler = { [queue] connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let request = String(decoding: data ?? Data(), as: UTF8.self)
                print("HTTP fixture request:", request)
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
