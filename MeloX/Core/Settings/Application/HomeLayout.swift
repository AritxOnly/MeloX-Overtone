enum HomeSection: Identifiable, Equatable {
    case quickActions
    case recentlyPlayed
    case newAlbums
    case recommendation(HomeRecommendationSlot)

    static let defaultOrder: [Self] = [
        .quickActions, .recentlyPlayed, .newAlbums,
    ] + HomeRecommendationSlot.allCases.map(Self.recommendation)

    var id: String {
        switch self {
        case .quickActions: "quickActions"
        case .recentlyPlayed: "recentlyPlayed"
        case .newAlbums: "newAlbums"
        case .recommendation(let slot): "recommendation-\(slot.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .quickActions: L10n.string("ui.home.section.quick_actions")
        case .recentlyPlayed: L10n.string("ui.navigation.recently_played")
        case .newAlbums: L10n.string("ui.albums.new.title")
        case .recommendation(let slot): slot.fallbackTitle
        }
    }
}
