import SwiftUI

struct MobileSettingsView: View {
    var showsDoneButton = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorPreset) private var colorPreset
    var body: some View {
        NavigationStack {
            Form {
                AppearancePickerSection()
                Section { LanguagePickerSection() }
            }
            .navigationTitle(AppLocalization.string("Settings"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if showsDoneButton {
                        Button(AppLocalization.string("Done")) { dismiss() }
                    }
                }
            }
        }
        .tint(Theme.accent(for: colorPreset))
    }
}
