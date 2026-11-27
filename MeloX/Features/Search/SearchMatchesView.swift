import SwiftUI

struct SearchMatchesView<Row: View>: View {
    let input: SearchInput
    let snapshot: SearchLibrarySnapshot?
    @Binding var cache: SearchResultCache
    @ViewBuilder let row: (SearchItem, [Song]) -> Row

    @Environment(NeteaseAPI.self) private var api
    @State private var items: [SearchItem] = []
    @State private var suggestions: [String] = []
    @State private var phase = LoadingPhase.loading
    @State private var retry = 0

    var body: some View {
        let queue = items.compactMap(\.song)
        List {
            ForEach(suggestions, id: \.self) { text in row(.keyword(text), []) }
            ForEach(items) { item in row(item, queue) }
        }
        .listStyle(.plain)
        .overlay {
            if items.isEmpty && suggestions.isEmpty {
                switch phase {
                case .loading: ProgressView("ui.search.searching")
                case .failed(let message):
                    ContentUnavailableView {
                        Label("ui.search.failed", systemImage: "exclamationmark.magnifyingglass")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("ui.common.retry") { retry += 1 }
                    }
                case .loaded:
                    if !input.preview { ContentUnavailableView.search(text: input.query) }
                }
            }
        }
        .task(id: snapshot) { await load() }
        .task(id: retry) {
            if retry > 0 { await load() }
        }
        .task {
            guard input.preview, input.suggestions, !input.library, input.link == nil else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                let values = try await api.searchSuggestions(input.query)
                try Task.checkCancellation()
                suggestions = Array(values.prefix(3))
            } catch {}
        }
    }

    private func load() async {
        phase = .loading
        do {
            if case .song(let id) = input.link {
                let songs = try await api.songDetails(ids: [id])
                try Task.checkCancellation()
                guard let song = songs.first else {
                    phase = .failed(L10n.string("ui.clipboard.error.song_not_found"))
                    return
                }
                items = [.song(song)]
            } else if input.preview && !input.suggestions {
                suggestions = [input.query]
            } else {
                if input.preview { try await Task.sleep(for: .milliseconds(250)) }
                let groups: [[SearchItem]]
                if let snapshot {
                    groups = try await snapshot.matches(query: input.query, kinds: input.kinds)
                } else {
                    groups = try await catalogGroups()
                }
                try Task.checkCancellation()
                let mixed = input.kinds.count == 1 ? (groups.first ?? []) :
                    SearchItem.bestMatches(groups, query: input.query)
                items = input.preview ? Array(mixed.prefix(6)) : mixed
                if input.library && input.preview {
                    var seen = Set<String>()
                    suggestions = Array(mixed.map(\.title).filter { seen.insert($0.lowercased()).inserted }.prefix(3))
                }
            }
            phase = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func catalogGroups() async throws -> [[SearchItem]] {
        var payloads: [SearchKind: SearchPayload] = [:]
        var failure: Error?
        await withTaskGroup(of: (SearchKind, Result<SearchPayload, Error>).self) { group in
            for kind in input.kinds {
                if !input.preview, let saved = cache.value(for: input.query, kind: kind) {
                    payloads[kind] = saved
                    continue
                }
                group.addTask { @MainActor in
                    do {
                        let payload = try await api.search(input.query, kind: kind, limit: input.preview ? 3 : 30)
                        guard kind == .songs, let songs = payload.songs,
                              songs.contains(where: { $0.album?.artworkURL == nil }),
                              let details = try? await api.songDetails(ids: songs.map(\.id)) else {
                            return (kind, .success(payload))
                        }
                        let byID = Dictionary(details.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                        return (kind, .success(SearchPayload(songs: songs.map { byID[$0.id] ?? $0 },
                                                             albums: nil, artists: nil, playlists: nil, podcasts: nil)))
                    } catch {
                        return (kind, .failure(error))
                    }
                }
            }
            for await (kind, result) in group {
                guard !Task.isCancelled else { continue }
                switch result {
                case .success(let payload):
                    payloads[kind] = payload
                    if !input.preview { cache.insert(payload, for: input.query, kind: kind) }
                case .failure(let error):
                    failure = error
                }
            }
        }
        try Task.checkCancellation()
        let groups = input.kinds.map { kind in
            payloads[kind].map { SearchItem.results($0, kind: kind) } ?? []
        }
        if groups.allSatisfy(\.isEmpty), let failure { throw failure }
        return groups
    }
}
