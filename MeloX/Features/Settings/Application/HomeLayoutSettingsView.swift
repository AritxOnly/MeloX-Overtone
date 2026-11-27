import SwiftUI

struct HomeLayoutSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            Section {
                ForEach(settings.homeSectionOrder) { section in
                    Text(section.title)
                }
                .onMove { source, destination in
                    settings.homeSectionOrder.move(fromOffsets: source, toOffset: destination)
                }
            } header: {
                Text("ui.settings.home_layout.sections")
            } footer: {
                Text("ui.settings.home_layout.sections.footer")
            }

            Section("ui.settings.home_layout.quick_actions") {
                ForEach(settings.homeQuickActionOrder) { action in
                    Label(action.title, systemImage: action.systemImage)
                }
                .onMove { source, destination in
                    settings.homeQuickActionOrder.move(fromOffsets: source, toOffset: destination)
                }
            }

            Section {
                Button("ui.settings.home_layout.reset") {
                    withAnimation {
                        settings.homeSectionOrder = HomeSection.defaultOrder
                        settings.homeQuickActionOrder = HomeQuickAction.allCases
                    }
                }
                .disabled(
                    settings.homeSectionOrder == HomeSection.defaultOrder
                        && settings.homeQuickActionOrder == HomeQuickAction.allCases
                )
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("ui.settings.home_layout.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
