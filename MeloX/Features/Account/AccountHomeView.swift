import SwiftUI

struct AccountHomeView: View {
    let initialProfile: AccountProfile
    let onOpenPlaylist: ((Playlist) -> Void)?
    let onOpenSettings: (() -> Void)?
    let onOpenSongRecognition: (() -> Void)?

    @Environment(NeteaseAPI.self) private var api
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var detail: AccountDetail?
    @State private var playlists: [Playlist]
    @State private var phase: LoadingPhase
    @State private var errorMessage: String?
    @State private var artworkPalette: ArtworkDetailPalette?
    @State private var blurredBackdropImage: CGImage?

    init(
        initialProfile: AccountProfile,
        initialDetail: AccountDetail? = nil,
        initialPlaylists: [Playlist] = [],
        onOpenPlaylist: ((Playlist) -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onOpenSongRecognition: (() -> Void)? = nil
    ) {
        let cachedAssets = ArtworkAccentColorProvider.cachedDetailAssets(
            for: initialProfile.artworkURL
        )
        self.initialProfile = initialProfile
        self.onOpenPlaylist = onOpenPlaylist
        self.onOpenSettings = onOpenSettings
        self.onOpenSongRecognition = onOpenSongRecognition
        _detail = State(initialValue: initialDetail)
        _playlists = State(initialValue: initialPlaylists)
        _phase = State(initialValue: .loaded)
        _artworkPalette = State(initialValue: cachedAssets?.palette)
        _blurredBackdropImage = State(
            initialValue: cachedAssets?.blurredBackdropImage
        )
    }

    var body: some View {
        AccountHomeContent(
            profile: displayedProfile,
            isPersonalAccount: onOpenSettings != nil,
            detail: detail,
            playlists: playlists,
            onOpenPlaylist: onOpenPlaylist,
            palette: resolvedPalette,
            blurredBackdropImage: blurredBackdropImage,
            isLoading: phase == .loading,
            failureMessage: errorMessage,
            onRetry: {
                Task { await load() }
            },
            onRefresh: load
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            accountToolbar
        }
        .task {
            await load()
        }
        .task(id: displayedProfile.artworkURL) {
            await loadArtworkAssets()
        }
    }

    private var displayedProfile: AccountProfile {
        detail?.profile ?? initialProfile
    }

    private var resolvedPalette: ArtworkDetailPalette {
        artworkPalette?.collectionPalette(for: systemColorScheme)
            ?? .fallback(prefersDarkAppearance: systemColorScheme == .dark)
    }

    private var homepageURL: URL {
        URL(string: "https://music.163.com/#/user/home?id=\(displayedProfile.id)")!
    }

    @ToolbarContentBuilder
    private var accountToolbar: some ToolbarContent {
        if onOpenSettings != nil {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(value: AccountRoute.privateMessages) {
                    Image(systemName: "envelope")
                }
                .tint(.primary)
                .accessibilityLabel("ui.messages.private.title")
            }
            .sharedBackgroundVisibility(.visible)

            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            ShareLink(item: homepageURL) {
                Image(systemName: "square.and.arrow.up")
            }
            .tint(.primary)
            .accessibilityLabel("ui.account.share_profile")

            if let onOpenSettings, let onOpenSongRecognition {
                Menu {
                    Button("ui.settings.title", systemImage: "gearshape", action: onOpenSettings)
                    Button("ui.recognition.title", systemImage: "waveform", action: onOpenSongRecognition)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .tint(.primary)
                .accessibilityLabel("ui.common.more")
            }
        }
        .sharedBackgroundVisibility(.visible)
    }

    private func loadArtworkAssets() async {
        let loadedAssets = await ArtworkAccentColorProvider.shared.detailAssets(
            for: displayedProfile.artworkURL,
            fallbackPrefersDarkAppearance: systemColorScheme == .dark
        )
        guard !Task.isCancelled else { return }

        let backdropAlreadyResolved = blurredBackdropImage != nil
            || loadedAssets.blurredBackdropImage == nil
        guard artworkPalette != loadedAssets.palette
                || !backdropAlreadyResolved else {
            return
        }

        withAnimation(artworkTransitionAnimation) {
            artworkPalette = loadedAssets.palette
            blurredBackdropImage = loadedAssets.blurredBackdropImage
        }
    }

    private var artworkTransitionAnimation: Animation? {
        accessibilityReduceMotion ? nil : .easeOut(duration: 0.18)
    }

    private func load() async {
        guard phase != .loading else { return }

        phase = .loading
        errorMessage = nil
        defer { phase = .loaded }
        do {
            async let loadedDetail = api.userDetail(userID: initialProfile.id)
            async let loadedPlaylists = api.userPlaylists(userID: initialProfile.id)
            let newDetail = try await loadedDetail
            try Task.checkCancellation()
            detail = newDetail
            let newPlaylists = try await loadedPlaylists
            try Task.checkCancellation()
            playlists = newPlaylists
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
