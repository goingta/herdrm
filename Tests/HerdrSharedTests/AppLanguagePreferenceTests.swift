import XCTest
#if os(iOS)
@testable import HerdrMobile
#else
@testable import herdrm
#endif

@MainActor
final class AppLanguagePreferenceTests: XCTestCase {
    func testMissingSelectedLanguageEntryUsesBaseEnglishResource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        defer { try? FileManager.default.removeItem(at: directory) }
        for language in ["en", "zh-Hans"] {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(language + ".lproj"), withIntermediateDirectories: true)
        }
        try "\"fallback.label\" = \"Base English label\";".write(to: directory.appendingPathComponent("en.lproj/Localizable.strings"), atomically: true, encoding: .utf8)
        try "\"different.label\" = \"其他\";".write(to: directory.appendingPathComponent("zh-Hans.lproj/Localizable.strings"), atomically: true, encoding: .utf8)
        let bundle = try XCTUnwrap(Bundle(url: directory))
        XCTAssertEqual(AppLocalization.string("fallback.label", bundle: bundle, locale: Locale(identifier: "zh-Hans")), "Base English label")
    }

    func testChangingLanguageUpdatesResourcesImmediatelyAndSurvivesReopen() {
        let suite = "app-language-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preference = AppLanguagePreference(defaults: defaults, systemLanguages: { ["en-US"] })
        XCTAssertEqual(preference.selection, .system)
        XCTAssertEqual(preference.string("Language"), "Language")
        preference.selection = .simplifiedChinese
        XCTAssertEqual(preference.string("Language"), "语言")
        let reopened = AppLanguagePreference(defaults: defaults, systemLanguages: { ["en-US"] })
        XCTAssertEqual(reopened.selection, .simplifiedChinese)
        XCTAssertEqual(reopened.string("Language"), "语言")
        reopened.selection = .english
        XCTAssertEqual(reopened.string("Language"), "Language")
        reopened.selection = .system
        XCTAssertEqual(reopened.string("Language"), "Language")
    }

    func testSystemModeResolvesChineseAndFallsBackToEnglishForUnsupportedLanguage() {
        let suite = "app-language-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var systemLanguages = ["zh-Hans-CN"]
        let preference = AppLanguagePreference(defaults: defaults, systemLanguages: { systemLanguages })
        XCTAssertEqual(preference.string("Language"), "语言")
        preference.selection = .english
        XCTAssertEqual(preference.string("Language"), "Language")
        preference.selection = .system
        systemLanguages = ["fr-FR"]
        XCTAssertEqual(preference.string("Language"), "Language")
        XCTAssertEqual(preference.string("A missing catalog sentence"), "A missing catalog sentence")
    }

    func testTranslationPreservesInterpolatedRemoteNames() {
        let suite = "app-language-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preference = AppLanguagePreference(defaults: defaults, systemLanguages: { ["zh-Hans-CN"] })
        let remoteName = "workspace-验收 Linux"
        let localized = preference.string("Remove \(remoteName)")
        XCTAssertTrue(localized.contains(remoteName))
        XCTAssertTrue(localized.hasPrefix("移除"))
    }
}
