import SwiftUI

@main
struct HerdrMobileApp: App {
    @State private var model = MobileAppModel()
    @State private var navigation = MobileWorkspaceNavigation()
    @State private var languagePreference = AppLanguagePreference.shared
    @StateObject private var appearance = AppAppearancePreference()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The public half of the device key, for the pairing UI and support
        // tooling. Public by definition; the private key never leaves Keychain.
        UserDefaults.standard.set(
            DeviceKey.authorizedKeysLine(DeviceKey.ensure()),
            forKey: "deviceKey.publicLine"
        )
        // Nerd Font symbols for agent-TUI icon glyphs (Ghostty codepoint-maps
        // the PUA ranges to this family).
        MobileGhosttyRuntime.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            MobileWorkspaceView(model: model, navigation: navigation)
                .environment(languagePreference)
                .environment(\.locale, languagePreference.locale)
                .environmentObject(appearance)
                .preferredColorScheme(appearance.preferredColorScheme)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, model.selectedDeviceID != nil {
                model.resumeSelected()
            } else if phase != .active {
                model.suspendSelected()
            }
        }
    }
}
