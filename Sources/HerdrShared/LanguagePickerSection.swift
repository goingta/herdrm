import SwiftUI

struct LanguagePickerSection: View {
    @Environment(AppLanguagePreference.self) private var preference
    @Environment(\.appColorPreset) private var colorPreset

    var body: some View {
        @Bindable var preference = preference
        Picker(AppLocalization.string("Language"), selection: $preference.selection) {
            ForEach(AppLanguage.allCases) { language in
                Text(verbatim: language.displayName).tag(language)
            }
        }
        // Native menu pickers retain their initial title tint even after the
        // environment changes. Replace only this stateless control; language
        // selection is owned by the retained preference, never by the picker.
        .id(colorPreset)
        .tint(Theme.accent(for: colorPreset))
        .accessibilityIdentifier("settings.language")
    }
}
