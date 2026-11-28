import SwiftUI

struct MusicDeepLinkOpeningModifier: ViewModifier {
    @Environment(NeteaseAPI.self) private var api

    let openRoute: (MusicRoute) -> Void

    @State private var openingTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.onOpenURL { url in
            guard let link = MusicDeepLink(url) else { return }
            openingTask?.cancel()
            openingTask = Task { await open(link) }
        }
    }

    private func open(_ link: MusicDeepLink) async {
        guard let route = await resolve(link),
              !Task.isCancelled else {
            return
        }
        openRoute(route)
    }

    private func resolve(_ link: MusicDeepLink) async -> MusicRoute? {
        do {
            switch link.resource {
            case .song:
                let songs = try await api.songDetails(ids: [link.id])
                guard let song = songs.first else { return nil }
                return .song(song)
            case .playlist:
                let playlist = try await api.playlist(
                    id: link.id,
                    trackLimit: 30
                )
                return .playlist(playlist)
            case .album:
                let (album, _) = try await api.album(id: link.id)
                return .album(album)
            case .artist:
                return .artist(link.id)
            }
        } catch {
            return nil
        }
    }
}

extension View {
    func opensMusicDeepLinks(
        openRoute: @escaping (MusicRoute) -> Void
    ) -> some View {
        modifier(MusicDeepLinkOpeningModifier(openRoute: openRoute))
    }
}
