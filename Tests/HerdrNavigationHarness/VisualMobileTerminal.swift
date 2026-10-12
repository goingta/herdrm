import SwiftUI
import GhosttyTerminal

/// Renderer evidence only: the real shared Ghostty runtime, not SSH evidence.
struct VisualMobileTerminal: UIViewRepresentable {
    let payload: String
    @Environment(\.appColorPreset) private var colorPreset
    func makeUIView(context: Context) -> UITerminalView {
        MobileGhosttyRuntime.controller.setTheme(TerminalPalette.makeTheme(preset: colorPreset))
        MobileGhosttyRuntime.controller.setColorScheme(.dark)
        let session = InMemoryTerminalSession(write: { _ in }, resize: { _ in })
        let view = UITerminalView(frame: .zero)
        view.controller = MobileGhosttyRuntime.controller
        view.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { session.receive(Data(payload.utf8)) }
        return view
    }
    func updateUIView(_ view: UITerminalView, context: Context) { MobileGhosttyRuntime.controller.setTheme(TerminalPalette.makeTheme(preset: colorPreset))
        MobileGhosttyRuntime.controller.setColorScheme(.dark) }
}
