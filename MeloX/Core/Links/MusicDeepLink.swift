import Foundation

struct MusicDeepLink: Hashable {
    enum Resource: String {
        case song
        case playlist
        case album
        case artist
    }

    let resource: Resource
    let id: Int

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let resource = Resource(rawValue: url.host?.lowercased() ?? ""),
              url.pathComponents.count == 2,
              let id = Int(url.lastPathComponent),
              id > 0 else {
            return nil
        }
        self.resource = resource
        self.id = id
    }

    static let scheme = "overtone"
}
