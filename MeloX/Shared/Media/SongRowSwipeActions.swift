import SwiftUI

enum SongRowRemoval {
    case none
    case library
    case download
    case action(LocalizedStringKey, () -> Void)
}

extension View {
    func songSwipeActions(_ song: Song, removal: SongRowRemoval = .library,
                          enabled: Bool = true) -> some View {
        modifier(SongRowSwipeActions(song: song, removal: removal,
                                     enabled: enabled))
    }
}

private struct RowAction {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color
    let perform: () -> Void

    var button: some View {
        Button(action: perform) { Image(systemName: symbol) }
            .accessibilityLabel(title)
            .tint(color)
    }

    static func download(for song: Song, downloads: DownloadStore, settings: AppSettings) -> RowAction? {
        guard AppFeatureAvailability.downloads, settings.isContentFeatureEnabled(.downloads),
              !downloads.contains(songID: song.id) else { return nil }
        if downloads.isDownloading(songID: song.id) {
            return RowAction(title: "ui.downloads.cancel", symbol: "xmark.circle", color: .blue) {
                downloads.cancel(songID: song.id)
            }
        }
        return RowAction(title: "ui.common.download", symbol: "arrow.down.circle", color: .blue) {
            downloads.start(song, quality: settings.quality)
        }
    }
}

private struct SongRowSwipeActions: ViewModifier {
    let song: Song
    let removal: SongRowRemoval
    let enabled: Bool
    @Environment(PlayerStore.self) private var player
    @Environment(DownloadStore.self) private var downloads
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings

    func body(content: Content) -> some View {
        let playNext = RowAction(title: "ui.player.play_next", symbol: "text.line.first.and.arrowtriangle.forward",
                                 color: .purple, perform: { Task { await player.playNext(song) } })
        let remove = removalAction
        let download = RowAction.download(for: song, downloads: downloads, settings: settings)
        if !enabled {
            content
        } else {
            content
                .swipeActions(edge: .leading) { playNext.button }
                .swipeActions(edge: .trailing) {
                    remove?.button
                    download?.button
                }
        }
    }

    private var removalAction: RowAction? {
        switch removal {
        case .none: return nil
        case .action(let title, let action):
            return RowAction(title: title, symbol: "trash", color: .red, perform: action)
        case .library:
            if library.isLoggedIn && library.contains(song: song) {
                return RowAction(title: "ui.song.unlike", symbol: "trash", color: .red) {
                    if library.contains(song: song) { library.toggle(song: song) }
                }
            }
            fallthrough
        case .download:
            guard AppFeatureAvailability.downloads && downloads.contains(songID: song.id) else { return nil }
            return RowAction(title: "ui.downloads.delete", symbol: "trash", color: .red) {
                downloads.remove(songID: song.id)
            }
        }
    }
}

struct QueueEntryActions: View {
    @Environment(PlayerStore.self) private var player
    @Environment(DownloadStore.self) private var downloads
    @Environment(AppSettings.self) private var settings
    let song: Song
    let index: Int

    var body: some View {
        if index != player.currentIndex {
            Button("ui.player.play_next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                Task { await player.promoteQueuedSong(at: index, matching: song) }
            }
            Button("ui.player.remove_from_queue", systemImage: "trash", role: .destructive) {
                player.removeQueuedSong(at: index, matching: song.id)
            }
        }
        if let action = RowAction.download(for: song, downloads: downloads, settings: settings) {
            Button(action: action.perform) { Label(action.title, systemImage: action.symbol) }
        }
    }
}
