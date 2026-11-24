import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 0) {
                    ForEach(LibraryPage.availableCases) { page in
                        NavigationLink(value: page) {
                            HStack(spacing: 16) {
                                Image(systemName: page.systemImage)
                                    .font(.title2)
                                    .frame(width: 32)
                                Text(page.title)
                                    .font(.title3)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 52)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 48)
                    }
                }

                if !library.favoriteSongs.isEmpty || !library.favoriteAlbums.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ui.library.recently_added")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 14)], alignment: .leading, spacing: 16) {
                            ForEach(library.favoriteSongs.prefix(12)) { song in
                                Button {
                                    Task { await player.play(song, in: library.favoriteSongs) }
                                } label: {
                                    coverCard(song.name, artist: song.artistText, url: song.album?.artworkURL)
                                }
                            }
                            if library.favoriteSongs.isEmpty {
                                ForEach(library.favoriteAlbums.prefix(12)) { album in
                                    NavigationLink(value: MusicRoute.album(album)) {
                                        coverCard(album.name, artist: album.artistText, url: album.artworkURL)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .navigationTitle("ui.navigation.library")
        .navigationDestination(for: LibraryPage.self) { page in
            LibraryCategoryView(section: page)
                .musicNavigationBarAtTop()
        }
        .refreshable { await library.refresh(force: true) }
    }

    private func coverCard(_ title: String, artist: String, url: URL?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ArtworkImage(url: url, cornerRadius: 6)
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }
}

private struct LibraryCategoryView: View {
    let section: LibraryPage
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadStore.self) private var downloads
    @State private var showsLogin = false
    @State private var searchQuery = ""

    var body: some View {
        Group {
            if section == .downloads {
                LibraryDownloadsView(searchQuery: searchQuery)
            } else if section == .songs, AppFeatureAvailability.downloads, !downloads.downloads.isEmpty {
                LibrarySongsView(searchQuery: searchQuery)
            } else if !library.isLoggedIn {
                loginUnavailableView
            } else if section == .cloud {
                CloudMusicView(searchQuery: searchQuery)
            } else {
                libraryContent
            }
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.large)
        .librarySearchable(text: $searchQuery, prompt: searchPrompt,
                           isEnabled: section == .downloads || library.isLoggedIn || (section == .songs && !downloads.downloads.isEmpty),
                           hidesSearchInitially: section == .songs)
        .sheet(isPresented: $showsLogin) {
            NavigationStack { NeteaseLoginView() }
        }
        .task(id: library.isLoggedIn) { await library.refresh() }
        .alert("ui.library.error.title", isPresented: Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.clearError() } }
        )) {
            Button("ui.common.ok", role: .cancel) { library.clearError() }
        } message: {
            Text(library.errorMessage ?? L10n.string("ui.common.unknown_error"))
        }
    }

    private var loginUnavailableView: some View {
        ContentUnavailableView {
            Label("ui.account.login_required", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text(
                AppFeatureAvailability.downloads
                    ? L10n.string("ui.library.login_message.downloads")
                    : L10n.string("ui.library.login_message")
            )
        } actions: {
            Button("ui.account.login_netease") {
                showsLogin = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        switch library.phase {
        case .loading where library.profile == nil:
            ProgressView("ui.library.loading")
        case .failed(let message) where library.profile == nil:
            ConnectionUnavailableView(message: message) {
                Task { await library.refresh(force: true) }
            }
        default:
            switch section {
            case .songs:
                LibrarySongsView(searchQuery: searchQuery)
            case .playlists:
                LibraryPlaylistsView(searchQuery: searchQuery)
            case .artists:
                LibraryArtistsView(searchQuery: searchQuery)
            case .albums:
                LibraryAlbumsView(searchQuery: searchQuery)
            case .podcasts:
                SubscribedPodcastsView(searchQuery: searchQuery)
            case .downloads:
                LibraryDownloadsView(searchQuery: searchQuery)
            case .cloud:
                CloudMusicView(searchQuery: searchQuery)
            case .history:
                LibraryHistoryView(searchQuery: searchQuery)
            }
        }
    }

    private var searchPrompt: String {
        switch section {
        case .songs:
            L10n.string("ui.library.search.favorite_songs")
        case .playlists:
            L10n.string("ui.library.search.favorite_playlists")
        case .artists:
            L10n.string("ui.library.artists.search")
        case .albums:
            L10n.string("ui.library.search.favorite_albums")
        case .podcasts:
            L10n.string("ui.library.search.subscribed_podcasts")
        case .downloads:
            AppFeatureAvailability.downloads
                ? L10n.string("ui.library.search.downloads")
                : L10n.string("ui.library.search.songs")
        case .cloud:
            L10n.string("ui.library.search.cloud")
        case .history:
            L10n.string("ui.library.search.history")
        }
    }
}

private extension View {
    @ViewBuilder
    func librarySearchable(
        text: Binding<String>,
        prompt: String,
        isEnabled: Bool,
        hidesSearchInitially: Bool
    ) -> some View {
        if isEnabled {
            searchable(
                text: text,
                placement: .navigationBarDrawer(displayMode: hidesSearchInitially ? .automatic : .always),
                prompt: Text(prompt)
            )
        } else {
            self
        }
    }
}
