import Observation
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let defaultsKey = "app.language"
    static let bundledLocalizations = ["en", "zh-Hans"]
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return AppLocalization.string("Follow System")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    static func current(defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .system
    }

    static func apply(_ language: Self, defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: defaultsKey)
        // Previous releases wrote a process-wide AppleLanguages override.
        // Resolve our own resources instead, allowing live changes without exit.
        defaults.removeObject(forKey: "AppleLanguages")
    }

    static func effectiveCode(for language: Self, systemLanguages: [String]) -> String {
        let preferences = language == .system ? systemLanguages : [language.rawValue]
        return Bundle.preferredLocalizations(from: bundledLocalizations, forPreferences: preferences).first ?? "en"
    }

    static func systemPreferredLanguages() -> [String] {
        if let languages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String], !languages.isEmpty {
            return languages
        }
        return Locale.preferredLanguages
    }
}

/// View identity and network sessions remain untouched when only this object changes.
@Observable
final class AppLanguagePreference {
    static let shared = AppLanguagePreference()
    var selection: AppLanguage {
        didSet { AppLanguage.apply(selection, defaults: defaults) }
    }
    private let defaults: UserDefaults
    private let systemLanguages: () -> [String]

    init(defaults: UserDefaults = .standard, systemLanguages: @escaping () -> [String] = AppLanguage.systemPreferredLanguages) {
        self.defaults = defaults
        self.systemLanguages = systemLanguages
        selection = AppLanguage.current(defaults: defaults)
        AppLanguage.apply(selection, defaults: defaults)
    }

    var locale: Locale {
        Locale(identifier: AppLanguage.effectiveCode(for: selection, systemLanguages: systemLanguages()))
    }

    func string(_ key: String.LocalizationValue, bundle: Bundle = .main) -> String {
        AppLocalization.string(key, bundle: bundle, locale: locale)
    }
}

enum AppLocalization {
    static func string(_ key: String.LocalizationValue, bundle: Bundle = .main, locale: Locale? = nil) -> String {
        let locale = locale ?? Locale(identifier: AppLanguage.effectiveCode(for: AppLanguagePreference.shared.selection, systemLanguages: AppLanguage.systemPreferredLanguages()))
        return String(localized: key, bundle: localizedBundle(bundle, locale: locale, key: LocalizedStringResource(key).key), locale: locale)
    }

    static func string(_ key: StaticString, defaultValue: String.LocalizationValue, bundle: Bundle = .main) -> String {
        let locale = Locale(identifier: AppLanguage.effectiveCode(for: AppLanguagePreference.shared.selection, systemLanguages: AppLanguage.systemPreferredLanguages()))
        return String(localized: key, defaultValue: defaultValue, bundle: localizedBundle(bundle, locale: locale, key: key.description), locale: locale)
    }

    private static func localizedBundle(_ bundle: Bundle, locale: Locale, key: String) -> Bundle {
        let code = AppLanguage.effectiveCode(for: .system, systemLanguages: [locale.identifier])
        let missing = "__herdr_missing_localization__"
        if let path = bundle.path(forResource: code, ofType: "lproj"), let selected = Bundle(path: path),
           selected.localizedString(forKey: key, value: missing, table: nil) != missing {
            return selected
        }
        // Missing individual translations use the shipped English resource,
        // including semantic keys whose English value differs from the key.
        if let path = bundle.path(forResource: "en", ofType: "lproj"), let base = Bundle(path: path) {
            return base
        }
        return bundle
    }
}
