import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case phosphor, amber
    var id: String { rawValue }
    var colorScheme: ColorScheme { .dark }
}

private struct AppColorPresetKey: EnvironmentKey {
    static let defaultValue = AppearancePreference.phosphor
}
extension EnvironmentValues {
    var appColorPreset: AppearancePreference {
        get { self[AppColorPresetKey.self] }
        set { self[AppColorPresetKey.self] = newValue }
    }
}

/// A client-owned setting; changing it never changes the identity of an App model.
@MainActor
final class AppAppearancePreference: ObservableObject {
    static let defaultsKey = "app.theme"
    @Published var mode: AppearancePreference {
        didSet {
            defaults.set(mode.rawValue, forKey: Self.defaultsKey)
            AppPalette.select(mode)
        }
    }
    private let defaults: UserDefaults
    var preferredColorScheme: ColorScheme? { mode.colorScheme }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = AppearancePreference(rawValue: defaults.string(forKey: Self.defaultsKey) ?? "") ?? .phosphor
        // Old system/light/dark values safely adopt the new default, without
        // touching development-machine profiles or credential storage.
        defaults.set(mode.rawValue, forKey: Self.defaultsKey)
        AppPalette.select(mode)
    }
}

struct AppearancePickerSection: View {
    @EnvironmentObject private var appearance: AppAppearancePreference

    var body: some View {
        Section {
            Picker("Theme", selection: $appearance.mode) {
                Text(AppLocalization.string("theme.phosphor", defaultValue: "Phosphor")).tag(AppearancePreference.phosphor)
                Text(AppLocalization.string("theme.amber", defaultValue: "Amber")).tag(AppearancePreference.amber)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("appearance.mode")
        } header: {
            Text("Appearance")
        } footer: {
            Text("The terminal follows the app theme.")
        }
    }
}

/// Shared presentation policy: observe the client-owned choice and supply
/// concrete native tints plus typed renderer presets to retained content.
/// This changes no App model, terminal session, or document identity.
private struct AppAppearanceModifier: ViewModifier {
    @ObservedObject var preference: AppAppearancePreference
    func body(content: Content) -> some View {
        content
            .environmentObject(preference)
            .environment(\.appColorPreset, preference.mode)
            .preferredColorScheme(.dark)
            .tint(Theme.accent(for: preference.mode))
    }
}
extension View {
    func appAppearance(_ preference: AppAppearancePreference) -> some View {
        modifier(AppAppearanceModifier(preference: preference))
    }
}
