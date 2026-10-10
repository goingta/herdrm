import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// A client-owned setting; changing it never changes the identity of an App model.
@MainActor
final class AppAppearancePreference: ObservableObject {
    static let defaultsKey = "app.theme"
    @Published var mode: AppearancePreference {
        didSet { defaults.set(mode.rawValue, forKey: Self.defaultsKey) }
    }
    private let defaults: UserDefaults
    var preferredColorScheme: ColorScheme? { mode.colorScheme }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = AppearancePreference(rawValue: defaults.string(forKey: Self.defaultsKey) ?? "") ?? .system
    }
}

struct AppearancePickerSection: View {
    @EnvironmentObject private var appearance: AppAppearancePreference

    var body: some View {
        Section {
            Picker("Theme", selection: $appearance.mode) {
                Text(String(localized: "theme.system", defaultValue: "System")).tag(AppearancePreference.system)
                Text(String(localized: "theme.light", defaultValue: "Light")).tag(AppearancePreference.light)
                Text(String(localized: "theme.dark", defaultValue: "Dark")).tag(AppearancePreference.dark)
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
