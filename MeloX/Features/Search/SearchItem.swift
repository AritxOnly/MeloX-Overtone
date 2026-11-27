import Foundation

enum SearchItem: Codable, Identifiable {
    case keyword(String)
    case artist(Artist)
    case album(Album)
    case song(Song)
    case playlist(Playlist)
    case podcast(Podcast)

    var id: String {
        switch self {
        case .keyword(let text): "q-\(text.lowercased())"
        case .artist(let artist): "artist-\(artist.id)"
        case .album(let album): "album-\(album.id)"
        case .song(let song): "song-\(song.id)"
        case .playlist(let playlist): "playlist-\(playlist.id)"
        case .podcast(let podcast): "podcast-\(podcast.id)"
        }
    }

    var title: String {
        switch self {
        case .keyword(let text): text
        case .artist(let artist): artist.name
        case .album(let album): album.name
        case .song(let song): song.name
        case .playlist(let playlist): playlist.name
        case .podcast(let podcast): podcast.name
        }
    }

    var song: Song? {
        if case .song(let song) = self { return song }
        return nil
    }

    static func results(_ payload: SearchPayload, kind: SearchKind) -> [Self] {
        switch kind {
        case .artists: (payload.artists ?? []).map(Self.artist)
        case .albums: (payload.albums ?? []).map(Self.album)
        case .songs: (payload.songs ?? []).map(Self.song)
        case .playlists: (payload.playlists ?? []).map(Self.playlist)
        case .podcasts: (payload.podcasts ?? []).map(Self.podcast)
        }
    }

    // Songs, artists and albums lead Top Results. Other categories join after the opening rows.
    static func bestMatches(_ groups: [[Self]], query: String) -> [Self] {
        let music = groups.prefix(3)
        let other = groups.dropFirst(3)
        var leading: [Self] = []
        var remaining: [Self] = []
        for index in 0..<(groups.map(\.count).max() ?? 0) {
            let musicRows = music.compactMap { $0.indices.contains(index) ? $0[index] : nil }
            if index < 3 {
                leading += musicRows
            } else {
                remaining += musicRows
            }
            remaining += other.compactMap { $0.indices.contains(index) ? $0[index] : nil }
        }
        if let index = leading.firstIndex(where: { $0.title.localizedCaseInsensitiveCompare(query) == .orderedSame }) {
            let first = leading.remove(at: index)
            leading.insert(first, at: 0)
        }
        return leading + remaining
    }
}

struct SearchLibrarySnapshot: Equatable {
    let songs: [Song]
    let downloads: [Song]
    let albums: [Album]
    let artists: [Artist]
    let playlists: [Playlist]
    let podcasts: [Podcast]

    @concurrent func matches(query: String, kinds: [SearchKind]) async throws -> [[SearchItem]] {
        let tracks = unique(songs + downloads).filter { !$0.isPodcastProgram }
        return try kinds.map { kind in
            try Task.checkCancellation()
            switch kind {
            case .songs:
                return tracks.filter {
                    [$0.name, $0.artistText, $0.album?.name ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
                }.map(SearchItem.song)
            case .artists:
                let candidates = artists + albums.flatMap(\.artists) + tracks.flatMap(\.artists)
                return unique(candidates).filter {
                    ([$0.name] + $0.aliases).contains { $0.localizedCaseInsensitiveContains(query) }
                }.map(SearchItem.artist)
            case .albums:
                return unique(albums + tracks.compactMap(\.album)).filter {
                    $0.name.localizedCaseInsensitiveContains(query) || $0.artistText.localizedCaseInsensitiveContains(query)
                }.map(SearchItem.album)
            case .playlists:
                return filterLibraryPlaylists(playlists, query: query).map(SearchItem.playlist)
            case .podcasts:
                return filterLibraryPodcasts(podcasts, query: query).map(SearchItem.podcast)
            }
        }
    }

    nonisolated private func unique<T: Identifiable>(_ values: [T]) -> [T] where T.ID == Int {
        var seen = Set<Int>()
        return values.filter { $0.id > 0 && seen.insert($0.id).inserted }
    }
}
