import SwiftUI
import XCTest
import GhosttyTerminal
import HerdrKit
import HerdrSSH
@testable import HerdrMobile

@MainActor
final class AppearanceTests: XCTestCase {
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
