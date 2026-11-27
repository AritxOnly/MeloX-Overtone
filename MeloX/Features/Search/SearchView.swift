import SwiftUI

struct SearchView: View {
    let focusRequestToken: Int
    @FocusState private var focused: Bool
    @Environment(PlayerStore.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadStore.self) private var downloads
    @Environment(AppSettings.self) private var settings
    @Environment(\.openMusicRoute) private var openRoute

    @State private var query = ""
    @State private var presented = false
    @State private var submitted: String?
    @State private var inLibrary = false
    @State private var kind: SearchKind?
    @State private var cache = SearchResultCache()
    @State private var invitation: NeteaseListenTogetherLink?
    @AppStorage("search.recentItems") private var historyData = Data()

    private var keywords: String { normalizedLibrarySearchQuery(query) }
    private var kinds: [SearchKind] {
        [.artists, .albums, .songs, .playlists] + (settings.isContentFeatureEnabled(.podcasts) ? [.podcasts] : [])
    }

    var body: some View {
        VStack(spacing: 0) {
            if submitted != nil || presented || !keywords.isEmpty {
                if submitted != nil, link == nil {
                    filters
                }

                if keywords.isEmpty {
                    recentList
                } else if case .listenTogether(let value) = link {
                    ContentUnavailableView {
                        Label("ui.listen_together.invitation", systemImage: "person.2.wave.2")
                    } description: {
                        Text("ui.search.listen_together_link_recognized")
                    } actions: {
                        Button("ui.clipboard.view_invitation") { invitation = value }
                    }
                } else {
                    matches
                }
            } else {
                SearchDiscoveryView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("ui.navigation.search")
        .visibleDetailNavigationBar()
        .searchable(text: Binding(get: { query }, set: { value in
            if value != query { submitted = nil }
            query = value
        }), isPresented: $presented, placement: placement, prompt: "ui.search.prompt")
        .searchFocused($focused)
        .searchScopes($inLibrary, activation: .onSearchPresentation) {
            if submitted == nil {
                Text("ui.search.music_catalog").tag(false)
                Text("ui.search.personal_library").tag(true)
            }
        }
        .onSubmit(of: .search) { submit(keywords) }
        .onChange(of: focused) { _, editing in
            if editing { submitted = nil }
        }
        .onChange(of: focusRequestToken) {
            Task { @MainActor in
                await Task.yield()
                presented = true
                focused = true
            }
        }
        .onChange(of: kinds) {
            if let kind, !kinds.contains(kind) { self.kind = nil }
        }
        .sheet(item: $invitation) {
            ListenTogetherView(invitationText: $0.invitationText)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("ui.error.favorite_failed", isPresented: Binding(
            get: { library.errorMessage != nil }, set: { if !$0 { library.clearError() } }
        )) {
            Button("ui.common.ok", role: .cancel) { library.clearError() }
        } message: {
            Text(library.errorMessage ?? "")
        }
    }

    private var placement: SearchFieldPlacement {
        if #available(iOS 27, *) { return .toolbarPrincipal }
        return .navigationBarDrawer(displayMode: .always)
    }

    private var link: NeteaseMusicLink? {
        inLibrary ? nil : NeteaseMusicLinkParser.parse(keywords)
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                chip(nil)
                ForEach(kinds) { chip($0) }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ value: SearchKind?) -> some View {
        Button {
            kind = value
        } label: {
            Text(value?.title ?? L10n.string("ui.search.best"))
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(kind == value ? Color.white : Color.primary)
                .background(kind == value ? Color.accentColor : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(kind == value ? .isSelected : [])
    }

    private var matches: some View {
        let preview = submitted == nil
        let mixedKinds: [SearchKind] = [.songs, .artists, .albums] + (preview ? [] : kinds.filter { $0 == .playlists || $0 == .podcasts })
        let request = SearchInput(query: keywords, preview: preview, library: inLibrary,
                                  kinds: (!preview ? kind : nil).map { [$0] } ?? mixedKinds,
                                  suggestions: settings.searchSuggestionsEnabled, link: link)
        return SearchMatchesView(input: request, snapshot: inLibrary ? snapshot : nil,
                                 cache: $cache, row: itemRow)
            .id(request)
    }

    private var snapshot: SearchLibrarySnapshot {
        SearchLibrarySnapshot(songs: library.favoriteSongs,
                              downloads: AppFeatureAvailability.downloads ? downloads.downloadedSongs : [],
                              albums: library.favoriteAlbums, artists: library.favoriteArtists,
                              playlists: [library.likedPlaylist].compactMap { $0 } + library.favoritePlaylists.filter { $0.id != library.likedPlaylistID },
                              podcasts: library.subscribedPodcasts)
    }

    private var historyKey: String { inLibrary ? "library-\(library.profile?.id ?? 0)" : "catalog" }
    private var history: [String: [SearchItem]] {
        (try? JSONDecoder().decode([String: [SearchItem]].self, from: historyData)) ?? [:]
    }
    private var recentList: some View {
        let items = (history[historyKey] ?? []).filter {
            if case .podcast = $0 { return kinds.contains(.podcasts) }
            return true
        }
        let queue = items.compactMap(\.song)
        return List {
            Section {
                ForEach(items) { item in itemRow(item, queue) }
            } header: {
                HStack {
                    Text("ui.search.recent").font(.headline)
                    Spacer()
                    if !items.isEmpty {
                        Button("ui.common.clear") { saveHistory([]) }
                    }
                }
                .textCase(nil)
            }
        }
        .listStyle(.plain)
    }

    private func saveHistory(_ items: [SearchItem]) {
        var all = history
        all[historyKey] = items
        if let data = try? JSONEncoder().encode(all) { historyData = data }
    }

    private func remember(_ item: SearchItem) {
        let others = (history[historyKey] ?? []).filter { $0.id != item.id }
        saveHistory([item] + others.prefix(29))
    }

    private func submit(_ text: String) {
        let text = normalizedLibrarySearchQuery(text)
        guard !text.isEmpty else { return }
        query = text
        submitted = text
        kind = nil
        focused = false
        if link == nil { remember(.keyword(text)) }
    }

    @ViewBuilder
    private func itemRow(_ item: SearchItem, _ queue: [Song]) -> some View {
        switch item {
        case .keyword(let text):
            Button { submit(text) } label: {
                Label(text, systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
            }
            .buttonStyle(.plain)
        case .song(let song):
            TrackRowView(song: song, showsArtwork: true,
                         subtitleOverride: L10n.string("ui.common.song") + " · " + song.artistText) {
                remember(item)
                Task { await player.play(song, in: queue) }
            }
            .songSwipeActions(song)
        case .artist(let artist):
            mediaRow(item, route: .artist(artist.id), artwork: artist.artworkURL,
                     type: "ui.common.artist", circular: true)
        case .album(let album):
            mediaRow(item, route: .album(album), artwork: album.artworkURL,
                     type: "ui.common.album", detail: album.artistText)
        case .playlist(let playlist):
            mediaRow(item, route: .playlist(playlist), artwork: playlist.artworkURL,
                     type: "ui.common.playlist", detail: playlist.creator?.nickname)
        case .podcast(let podcast):
            mediaRow(item, route: .podcast(podcast), artwork: podcast.artworkURL,
                     type: "ui.common.podcast", detail: podcast.host?.nickname)
        }
    }

    private func mediaRow(_ item: SearchItem, route: MusicRoute, artwork: URL?,
                          type: String, detail: String? = nil, circular: Bool = false) -> some View {
        Button {
            remember(item)
            openRoute(route)
        } label: {
            HStack(spacing: 12) {
                ArtworkImage(url: artwork, cornerRadius: circular ? 24 : 6,
                             placeholderSymbol: circular ? "music.microphone" : "music.note")
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).lineLimit(1)
                    Text([L10n.string(type), detail].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .musicMatchedTransitionSource(for: route)
    }
}

struct SearchInput: Hashable {
    let query: String
    let preview: Bool
    let library: Bool
    let kinds: [SearchKind]
    let suggestions: Bool
    let link: NeteaseMusicLink?
}
