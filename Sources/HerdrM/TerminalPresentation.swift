import AppKit
import GhosttyTerminal
import HerdrKit

/// The actual hosted terminal/read-state seam. Text parsed offscreen is not
/// sufficient: the visible renderer must show content belonging to this pane.
@MainActor
enum TerminalPresentation {
    static func confirmRead(
        view: LineBreakTerminalView, terminal: InMemoryTerminalSession,
        readState: AgentReadState, key: AgentUnreadKey, generation: UUID,
        isCurrent: () -> Bool,
        readPane: () async throws -> String
    ) async -> Bool {
        guard isCurrent(), NSApp.isActive, view.window?.isVisible == true, view.window?.isKeyWindow == true, !view.isHidden,
              let text = terminal.readViewportText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let image = view.snapshotImage(),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              TerminalFrameReadiness.containsRenderedContent(cgImage),
              let pane = try? await readPane(),
              isCurrent(), NSApp.isActive, view.window?.isVisible == true, view.window?.isKeyWindow == true, !view.isHidden,
              AttachContentReadiness.matchesPane(visibleText: text, paneANSIText: pane) else { return false }
        return readState.presented(key, generation: generation, foreground: true)
    }
}
