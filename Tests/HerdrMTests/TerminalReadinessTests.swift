import AppKit
import GhosttyTerminal
import HerdrKit
import XCTest
@testable import herdrm

@MainActor
final class TerminalReadinessTests: XCTestCase {
    func testMountedGhosttyShowsCurrentPaneFrame() async throws {
        let session = InMemoryTerminalSession(write: { _ in }, resize: { _ in })
        let view = LineBreakTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        view.controller = GhosttyRuntime.controller
        view.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        defer { window.close() }
        session.receive(Data("\u{1b}[2J\u{1b}[HAgent completed THE_REAL_RENDERED_RESULT".utf8))
        try await Task.sleep(for: .seconds(1))
        XCTAssertTrue(session.readViewportText()?.contains("THE_REAL_RENDERED_RESULT") == true)
        let image = try XCTUnwrap(view.snapshotImage())
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        try png?.write(to: URL(fileURLWithPath: "/private/tmp/herdr-unread-mac-presented.png"))
        XCTAssertTrue(TerminalFrameReadiness.containsRenderedContent(cg), "A real mounted Ghostty frame must clear the renderer gate")
    }
    func testCurrentRenderedPaneClearsUnread() async throws {
        try await verifyRead(output: "Agent completed THE_REAL_RENDERED_RESULT", expectRead: true)
    }

    func testBlankOrShellErrorDoesNotClearUnread() async throws {
        try await verifyRead(output: "", expectRead: false)
        try await verifyRead(output: "exec: herdr: not found", expectRead: false)
    }

    func testReplacedConnectionCannotClearUnreadWithOldFrame() async throws {
        try await verifyRead(output: "Agent completed THE_REAL_RENDERED_RESULT", expectRead: false, replaceConnection: true)
    }

    private func verifyRead(output: String, expectRead: Bool, replaceConnection: Bool = false) async throws {
        let suite = "render-read-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let readState = AgentReadState(defaults: defaults)
        let key = AgentUnreadKey(deviceID: UUID(), paneID: "p1")
        func agent(_ status: String) throws -> AgentInfo {
            try JSONDecoder().decode(AgentInfo.self, from: Data("{\"pane_id\":\"p1\",\"agent\":\"codex\",\"agent_status\":\"\(status)\",\"workspace_id\":\"w1\",\"tab_id\":\"w1:t1\"}".utf8))
        }
        readState.apply(agents: [try agent("working")], deviceID: key.deviceID)
        readState.apply(agents: [try agent("done")], deviceID: key.deviceID)
        let generation = readState.beginTerminal(key)
        let session = InMemoryTerminalSession(write: { _ in }, resize: { _ in })
        let view = LineBreakTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        view.controller = GhosttyRuntime.controller
        view.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        defer { window.close() }
        if !output.isEmpty { session.receive(Data("\u{1b}[2J\u{1b}[H\(output)".utf8)) }
        try await Task.sleep(for: .seconds(1))
        await ensureForeground(window)
        XCTAssertTrue(NSApp.isActive, "host App foreground")
        if expectRead {
            XCTAssertTrue(window.isVisible, "host window visible")
            XCTAssertTrue(session.readViewportText()?.contains("THE_REAL_RENDERED_RESULT") == true, "current parsed text")
            let image = try XCTUnwrap(view.snapshotImage()?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            XCTAssertTrue(TerminalFrameReadiness.containsRenderedContent(image), "current rendered frame")
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/herdr-unread-mac-read-success.png"))
        }
        var replaced = false
        let confirmed = await TerminalPresentation.confirmRead(
            view: view, terminal: session, readState: readState, key: key, generation: generation,
            isCurrent: { true }, readPane: {
                // The RPC boundary finishes after the old attach has been replaced.
                if replaceConnection { readState.beginTerminal(key); replaced = true }
                return "Agent completed THE_REAL_RENDERED_RESULT"
            }
        )
        if replaceConnection { XCTAssertTrue(replaced, "replacement occurred while the pane-read boundary was in flight") }
        XCTAssertEqual(confirmed, expectRead)
        XCTAssertEqual(readState.unread.contains(key), !expectRead)
    }

    private func ensureForeground(_ window: NSWindow) async {
        // Closing the previous fixture can enqueue a resign-active event after
        // the next fixture's first activation. Wait for the real application
        // state; no injected or assumed foreground signal is used.
        for _ in 0..<30 {
            window.makeKeyAndOrderFront(nil)
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            try? await Task.sleep(for: .milliseconds(100))
            if NSApp.isActive && NSRunningApplication.current.isActive && window.isKeyWindow { return }
        }
    }

}
