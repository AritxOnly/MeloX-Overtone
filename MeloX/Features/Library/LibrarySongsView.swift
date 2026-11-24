import SwiftUI

struct LibrarySongsView: View {
    let searchQuery: String

    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player

    @Environment(DownloadStore.self) private var downloads
    @Environment(\.locale) private var locale

    @AppStorage("library.songs.sort") private var sort: LibrarySongSort = .artist
    @State private var filter: LibrarySongFilter = .all
    @State private var index = LibrarySongIndex()
    @State private var indexedRequest: LibrarySongIndex.Request?
    @State private var isStartingHeartMode = false
    @State private var heartModeErrorMessage: String?
    @State private var isPreparingPlayback = false
    @State private var playbackErrorMessage: String?

    private var request: LibrarySongIndex.Request {
        LibrarySongIndex.Request(favorites: library.favoriteSongs, favoriteDates: library.favoriteAddedDates,
                                 downloads: AppFeatureAvailability.downloads ? downloads.downloads : [],
                                 filter: filter, sort: sort, query: normalizedLibrarySearchQuery(searchQuery),
                                 locale: locale)
    }

    var body: some View {
        let request = request
        List {
            if !index.songs.isEmpty {
                SongListPlaybackActions(isPreparing: isPreparingPlayback) { shuffled in
                    playDisplayedSongs(shuffled: shuffled)
                }
            }
            ForEach(index.sections) { section in
                Section {
                    ForEach(section.songs) { song in
                        TrackRowView(song: song, showsArtwork: true) {
                            Task { await player.play(song, in: index.songs) }
                        }
                        .overlay(alignment: .leading) {
                            if library.contains(song: song) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.yellow)
                                    .offset(x: -14)
                                    .accessibilityHidden(true)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 16))
                        .swipeActions {
                            if library.contains(song: song) {
                                Button("ui.common.unfavorite", systemImage: "heart.slash", role: .destructive) {
                                    library.toggle(song: song)
                                }
                            }
                        }
                    }
                } header: {
                    if !section.title.isEmpty {
                        Text(section.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }
                .sectionIndexLabel(section.title.isEmpty ? nil : section.title)
            }

            if library.hasMoreFavoriteSongs, filter != .downloaded {
                if let message = library.favoriteSongsLoadMoreError {
                    ConnectionUnavailableView(message: message) {
                        Task { await library.loadRemainingFavoriteSongs() }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.plain)
        .listSectionIndexVisibility(sort == .added ? .hidden : .visible)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                LibraryFilterMenu(selection: $filter, allTitle: "ui.library.songs.filter.all",
                                  allSymbol: "music.note.list")

                Menu {
                    Picker("ui.library.songs.sort", selection: $sort) {
                        Label("ui.library.songs.sort.artist", systemImage: "music.microphone").tag(LibrarySongSort.artist)
                        Label("ui.library.songs.sort.added", systemImage: "calendar").tag(LibrarySongSort.added)
                        Label("ui.library.songs.sort.name", systemImage: "textformat").tag(LibrarySongSort.name)
                    }
                    Divider()
                    Button("ui.home.action.heart_mode", systemImage: "heart.circle.fill", action: startHeartMode)
                        .disabled(!library.canStartHeartMode || isStartingHeartMode)
                } label: {
                    Label("ui.common.more", systemImage: "ellipsis")
                }
                .tint(.primary)
            }
        }
        .refreshable {
            await library.refresh(force: true)
            await library.loadRemainingFavoriteSongs()
        }
        .task(id: library.hasMoreFavoriteSongs && filter != .downloaded) {
            if library.hasMoreFavoriteSongs && filter != .downloaded {
                await library.loadRemainingFavoriteSongs()
            }
        }
        .task(id: request) {
            guard let result = try? await LibrarySongIndex.build(request), !Task.isCancelled else { return }
            index = result
            indexedRequest = request
        }
        .overlay {
            if index.songs.isEmpty, indexedRequest == request,
               !library.hasMoreFavoriteSongs || filter == .downloaded {
                if !request.query.isEmpty {
                    ContentUnavailableView.search(text: request.query)
                } else {
                    ContentUnavailableView("ui.songs.empty", systemImage: "music.note.list")
                }
            }
        }
        .alert(
            "ui.library.heart_mode_failed",
            isPresented: Binding(
                get: { heartModeErrorMessage != nil },
                set: { presented in
                    if !presented {
                        heartModeErrorMessage = nil
                    }
                }
            )
        ) {
            Button("ui.common.ok", role: .cancel) {
                heartModeErrorMessage = nil
            }
        } message: {
            Text(heartModeErrorMessage ?? L10n.string("ui.error.try_again_later"))
        }
        .alert(
            "ui.library.play_all_failed",
            isPresented: Binding(
                get: { playbackErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        playbackErrorMessage = nil
                    }
                }
            )
        ) {
            Button("ui.common.ok", role: .cancel) {
                playbackErrorMessage = nil
            }
        } message: {
            Text(playbackErrorMessage ?? L10n.string("ui.library.complete_song_list_failed"))
        }
    }

    private func startHeartMode() {
        guard !isStartingHeartMode,
              let playlistID = library.likedPlaylistID,
              let seedSongID = library.randomHeartModeSeedSongID() else {
            return
        }

        isStartingHeartMode = true
        heartModeErrorMessage = nil
        Task { @MainActor in
            defer { isStartingHeartMode = false }
            do {
                try await player.playHeartMode(
                    playlistID: playlistID,
                    seedSongID: seedSongID
                )
            } catch is CancellationError {
                return
            } catch {
                heartModeErrorMessage = error.localizedDescription
            }
        }
    }

    private func playDisplayedSongs(shuffled: Bool) {
        guard !isPreparingPlayback else { return }
        isPreparingPlayback = true
        var selection = request
        Task { @MainActor in
            defer { isPreparingPlayback = false }
            do {
                if selection.filter != .downloaded && library.hasMoreFavoriteSongs {
                    selection.favorites = try await library.favoriteSongsForPlayback()
                }
                let songs = try await LibrarySongIndex.build(selection).songs
                try Task.checkCancellation()
                await player.playAll(shuffled ? songs.shuffled() : songs)
            } catch is CancellationError {
                return
            } catch {
                playbackErrorMessage = error.localizedDescription
            }
        }
    }
}
