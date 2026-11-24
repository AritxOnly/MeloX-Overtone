import SwiftUI

struct LibraryFilterMenu: View {
    @Binding var selection: LibrarySongFilter
    let allTitle: LocalizedStringKey
    let allSymbol: String

    var body: some View {
        Menu {
            option(.all, title: allTitle, symbol: allSymbol)
            Divider()
            option(.favorites, title: "ui.library.filter.favorites", symbol: "star")
            if AppFeatureAvailability.downloads {
                option(.downloaded, title: "ui.common.download", symbol: "arrow.down.circle")
            }
        } label: {
            Label("ui.library.songs.filter", systemImage: "line.3.horizontal.decrease")
        }
        .tint(.primary)
    }

    private func option(_ value: LibrarySongFilter, title: LocalizedStringKey, symbol: String) -> some View {
        Toggle(isOn: Binding(get: { selection == value }, set: { _ in selection = value })) {
            Label(title, systemImage: symbol)
        }
    }
}
