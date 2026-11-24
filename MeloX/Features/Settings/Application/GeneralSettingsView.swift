import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker(
                    "ui.settings.language.picker",
                    selection: Binding(
                        get: { settings.appLanguage },
                        set: settings.setAppLanguage
                    )
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title)
                            .tag(language)
                    }
                }
            } header: {
                Text("ui.settings.language.section")
            } footer: {
                Text("ui.settings.language.footer")
            }

            Section {
                Picker(
                    "ui.settings.general.theme.picker",
                    selection: $settings.appearance
                ) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Label(
                            appearance.title,
                            systemImage: appearance.systemImage
                        )
                        .tag(appearance)
                    }
                }
            } header: {
                Text("ui.settings.general.appearance.section")
            } footer: {
                Text("ui.settings.general.appearance.footer")
            }

            Section {
                Toggle(
                    "ui.settings.general.clipboard_recognition",
                    isOn: $settings.recognizesClipboardLinksOnLaunch
                )
            } header: {
                Text("ui.settings.general.clipboard.section")
            } footer: {
                Text(
                    "ui.settings.general.clipboard.footer"
                )
            }

            Section("ui.navigation.search") {
                Toggle("ui.settings.general.search_suggestions", isOn: $settings.searchSuggestionsEnabled)
            }

            Section {
                Toggle(
                    "ui.settings.general.cache_page_content",
                    isOn: $settings.automaticallyCachesPageContent
                )
            } footer: {
                Text("ui.settings.general.cache_page_content.footer")
            }
        }
        .navigationTitle("ui.settings.catalog.general.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
