import Foundation

/// A song keeps its most recently resolved quality. The underlying bounded
/// SQLite cache survives relaunch and is cleared with the account's page data.
struct PlaybackSourceCache {
    private struct Entry: Codable {
        let requestedQuality: MusicQuality
        let expires: Date
        let source: PlaybackSource
    }

    private let scope: String
    private let storage: PageContentCacheStorage

    init(cookie: String, storage: PageContentCacheStorage = .shared) {
        self.storage = storage
        scope = PageContentCache.scope(for: cookie)
    }

    private func key(_ id: Int) -> String { "playback-url.\(id)" }

    func value(id: Int, quality: MusicQuality, now: Date = Date()) async -> PlaybackSource? {
        guard let data = await storage.data(scope: scope, key: key(id)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.requestedQuality == quality, now < entry.expires else { return nil }
        return entry.source
    }

    func store(_ source: PlaybackSource, id: Int, quality: MusicQuality, expires: Date) async {
        let entry = Entry(requestedQuality: quality, expires: expires, source: source)
        guard expires > Date(), let data = try? JSONEncoder().encode(entry) else { return }
        await storage.store(data, scope: scope, key: key(id))
    }

    func invalidate(id: Int) async {
        await storage.remove(scope: scope, key: key(id))
    }
}
