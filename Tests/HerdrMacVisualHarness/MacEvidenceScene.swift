import AppKit
import SwiftUI
import HerdrKit
import GhosttyTerminal

struct MacEvidenceScene: View {
    @StateObject private var model: AppModel
    private let fixture: VisualFixture
    private let scene: String
    @StateObject private var appearance: AppAppearancePreference
    init() {
        let fixture = try! VisualFixture.load()
        self.fixture = fixture
        let env = ProcessInfo.processInfo.environment
        scene = env["VISUAL_SCENE"] ?? "sidebar"
        let preference = AppAppearancePreference()
        preference.mode = AppearancePreference(rawValue: env["VISUAL_THEME"] ?? "") ?? .phosphor
        _appearance = StateObject(wrappedValue: preference)
        AppLanguagePreference.shared.selection = AppLanguage(rawValue: env["VISUAL_LANGUAGE"] ?? "en")!
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herdr-mac-ui-fixture")
        let store = DeviceStore(directory: dir)
        let device = Device(id: fixture.deviceID, name: fixture.deviceName, kind: .ssh(target: "\(fixture.username)@\(fixture.host)"), osID: "ubuntu")
        store.save([device])
        let defaults = UserDefaults(suiteName: "herdr.visual.mac.ui")!
        defaults.removePersistentDomain(forName: "herdr.visual.mac.ui")
        let readState = AgentReadState(defaults: defaults)
        fixture.seedUnread(readState)
        let model = AppModel(store: store, defaults: defaults, readState: readState)
        model.devices = scene == "empty" ? [] : [device]
        var state = DeviceSessionState()
        state.connection = scene == "failure" ? .failed("Controlled fixture: SSH unavailable") : scene == "restoring" ? .connecting : .connected(version: "fixture")
        if !["empty", "failure", "restoring"].contains(scene) {
            state.agents = fixture.snapshot.agents
            state.workspaces = fixture.snapshot.workspaces
            state.tabs = fixture.snapshot.tabs ?? []
            state.panes = fixture.snapshot.panes ?? []
        }
        model.sessions[fixture.deviceID] = state
        model.publishReadState()
        _model = StateObject(wrappedValue: model)
    }
    var body: some View {
        Group {
            switch scene {
            case "form": EditDeviceSheet(model: model, device: model.devices[0]).frame(width: 420, height: 380)
            case "settings": AppearanceSettingsView().frame(width: 480, height: 320)
            case "devices": DevicePopover(model: model, isPresented: .constant(true)).frame(width: 320, height: 260)
            case "terminal": MacEvidenceTerminal(payload: fixture.terminal).frame(width: 840, height: 500)
            default: SidebarView(model: model, collapsed: .constant(false), width: 320).frame(width: 320, height: 844)
            }
        }
        .environment(AppLanguagePreference.shared)
        .environment(\.locale, AppLanguagePreference.shared.locale)
        .appAppearance(appearance)
        .background(Theme.contentBackground)
        .tint(Theme.accent)
    }
}
private struct MacEvidenceTerminal: NSViewRepresentable {
    @Environment(\.appColorPreset) private var colorPreset
    let payload: String
    func makeNSView(context: Context) -> LineBreakTerminalView {
        GhosttyRuntime.controller.setTheme(TerminalPalette.makeTheme(preset: colorPreset))
        let session = InMemoryTerminalSession(write: { _ in }, resize: { _ in })
        let view = LineBreakTerminalView(frame: .zero)
        view.controller = GhosttyRuntime.controller
        view.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { session.receive(Data(payload.utf8)) }
        return view
    }
    func updateNSView(_ view: LineBreakTerminalView, context: Context) {
        GhosttyRuntime.controller.setTheme(TerminalPalette.makeTheme(preset: colorPreset))
    }
}
