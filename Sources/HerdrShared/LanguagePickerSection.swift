import SwiftUI

struct LanguagePickerSection: View {
    @Environment(AppLanguagePreference.self) private var preference

    var body: some View {
        @Bindable var preference = preference
        Picker(AppLocalization.string("Language"), selection: $preference.selection) {
            ForEach(AppLanguage.allCases) { language in
                Text(verbatim: language.displayName).tag(language)
            }
        }
        .accessibilityIdentifier("settings.language")
    }
}
