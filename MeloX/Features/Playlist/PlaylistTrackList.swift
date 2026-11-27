import SwiftUI

enum CollectionTrackStyle {
    case playlist
    case album(artists: [Artist])

    var showsArtwork: Bool {
        if case .playlist = self { return true }
        return false
    }

    func artistSubtitle(for song: Song) -> String? {
        if case .album(let albumArtists) = self {
            let guests = song.artists.filter { performer in
                !albumArtists.contains { artist in
                    if artist.id > 0 && performer.id > 0 { return artist.id == performer.id }
                    return artist.name.localizedCaseInsensitiveCompare(performer.name) == .orderedSame
                }
            }
            if guests.count < song.artists.count {
                let credit = L10n.artistNames(guests.map(\.name))
                return credit.isEmpty ? nil : L10n.format("ui.album.with_artists", credit)
            }
        }
        let credit = song.artistText
        return credit.isEmpty ? nil : credit
    }
}

struct PlaylistTrackList: View {
    let tracks: [Song]
    let sourceID: Int
    let style: CollectionTrackStyle
    var onPlayTrack: (() -> Void)?
    var onRemoveSong: ((Song) -> Void)?
    var downloadSelection: MusicCollectionDownloadCoordinator?
    var highlightedSongID: Int?

    var body: some View {
        if tracks.isEmpty {
            ContentUnavailableView("ui.songs.empty", systemImage: "music.note.list")
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, song in
                PlaylistTrackRow(
                    song: song,
                    tracks: tracks,
                    sourceID: sourceID,
                    index: index,
                    style: style,
                    downloadSelection: downloadSelection,
                    onPlayTrack: onPlayTrack,
                    onRemoveSong: onRemoveSong,
                    isHighlighted: highlightedSongID == song.id
                )
                .id(song.id)
                .alignmentGuide(.listRowSeparatorLeading) { _ in
                    (style.showsArtwork ? 80 : 51) + (isSelectingDownloads ? 36 : 0)
                }
            }
        }
    }

    private var isSelectingDownloads: Bool {
        downloadSelection?.isSelecting == true
    }
}

private struct PlaylistTrackRow: View {
    let song: Song
    let tracks: [Song]
    let sourceID: Int
    let index: Int
    let style: CollectionTrackStyle
    let downloadSelection: MusicCollectionDownloadCoordinator?
    let onPlayTrack: (() -> Void)?
    let onRemoveSong: ((Song) -> Void)?
    let isHighlighted: Bool

    @Environment(\.openMusicRoute) private var openMusicRoute
    @Environment(PlayerStore.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadStore.self) private var downloads
    @Environment(AppSettings.self) private var settings
    @Environment(\.musicCollectionDetailMetrics) private var detailMetrics

    @State private var presentedSheet: PlaylistSongSheet?

    private var isCurrentSong: Bool {
        player.currentSong?.id == song.id
    }

    private var isSelectingDownloads: Bool {
        downloadSelection?.isSelecting == true
    }

    private var isSelectedForDownload: Bool {
        downloadSelection?.selectedSongIDs.contains(song.id) == true
    }

    private var canSelectForDownload: Bool {
        !downloads.contains(songID: song.id)
            && !downloads.isDownloading(songID: song.id)
    }

    var body: some View {
        let subtitle = style.artistSubtitle(for: song)
        HStack(spacing: 4) {
            Button(action: primaryAction) {
                HStack(spacing: style.showsArtwork ? 12 : 7) {
                    if isSelectingDownloads {
                        Image(
                            systemName: isSelectedForDownload
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            canSelectForDownload ? .primary : .tertiary
                        )
                        .frame(width: 24)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                    }

                    leadingContent

                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.name)
                            .font(.body)
                            .lineLimit(style.showsArtwork ? 1 : 2)

                        if let subtitle, !usesWideTrackColumns {
                            Text(verbatim: subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(style.showsArtwork ? 1 : nil)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if usesWideTrackColumns {
                        Text(verbatim: subtitle ?? "")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(style.showsArtwork ? 1 : nil)
                            .frame(width: detailMetrics.viewport.width * 0.25, alignment: .leading)
                        Text(song.durationText)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isSelectingDownloads && !canSelectForDownload)
            .accessibilityLabel(primaryActionAccessibilityLabel)
            .accessibilityValue(primaryActionAccessibilityValue)
            .accessibilityIdentifier("collection-track-\(song.id)")

            if settings.isContentFeatureEnabled(.downloads) {
                if downloads.isDownloading(songID: song.id) {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("ui.downloads.downloading")
                } else if downloads.contains(songID: song.id) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("ui.downloads.downloaded")
                }
            }

            if !isSelectingDownloads {
                Menu {
                    Button {
                        Task { await player.playNext(song) }
                    } label: {
                        Label(
                            "ui.player.play_next",
                            systemImage:
                                "text.line.first.and.arrowtriangle.forward"
                        )
                    }

                    if settings.isContentFeatureEnabled(.downloads) {
                        if downloads.isDownloading(songID: song.id) {
                            Button {
                                downloads.cancel(songID: song.id)
                            } label: {
                                Label("ui.downloads.cancel", systemImage: "xmark.circle")
                            }
                        } else if downloads.contains(songID: song.id) {
                            Button(role: .destructive) {
                                downloads.remove(songID: song.id)
                            } label: {
                                Label("ui.downloads.delete", systemImage: "trash")
                            }
                        } else {
                            Menu {
                                ForEach(MusicQuality.allCases) { quality in
                                    Button(quality.title) {
                                        downloads.start(song, quality: quality)
                                    }
                                }
                            } label: {
                                Label("ui.downloads.download_song", systemImage: "arrow.down.circle")
                            }
                        }
                    }

                    Button {
                        openMusicRoute(.song(song))
                    } label: {
                        Label("ui.song.information", systemImage: "info.circle")
                    }

                    Button {
                        library.toggle(song: song)
                    } label: {
                        Label(
                            library.contains(song: song)
                                ? L10n.string("ui.song.unlike")
                                : L10n.string("ui.song.like"),
                            systemImage: library.contains(song: song) ? "heart.slash" : "heart"
                        )
                    }

                    Button {
                        presentedSheet = .comments(song)
                    } label: {
                        Label("ui.comments.title", systemImage: "bubble.left.and.bubble.right")
                    }

                    Button {
                        presentedSheet = .addToPlaylist(song)
                    } label: {
                        Label("ui.playlists.add_to", systemImage: "text.badge.plus")
                    }

                    if let onRemoveSong {
                        Divider()
                        Button("ui.playlists.remove_song", systemImage: "minus.circle", role: .destructive) {
                            onRemoveSong(song)
                        }
                    }

                    Menu {
                        NeteaseShareMenuContent(resource: .song(song))
                    } label: {
                        Label("ui.common.share", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 42, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel(L10n.format("ui.song.more_actions", song.name))
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, style.showsArtwork ? 8 : 4)
        .background(
            isHighlighted ? Color.accentColor.opacity(0.16)
                : isCurrentSong ? Color.primary.opacity(0.10) : .clear
        )
        .musicMatchedTransitionSource(for: .song(song))
        .accessibilityElement(children: .contain)
        .songSwipeActions(song, removal: onRemoveSong.map { remove in
            .action("ui.playlists.remove_song") { remove(song) }
        } ?? (style.showsArtwork ? .library : .none), enabled: !isSelectingDownloads)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .comments(let selectedSong):
                SongCommentsSheet(song: selectedSong)
            case .addToPlaylist(let selectedSong):
                AddToPlaylistSheet(song: selectedSong)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private var leadingContent: some View {
        if style.showsArtwork {
            SongRowArtwork(songID: song.id, url: song.album?.artworkURL)
                .frame(width: 48, height: 48)
        } else if isCurrentSong && !isSelectingDownloads {
            if player.isLoading && !player.isPlaying {
                ProgressView().controlSize(.mini).frame(width: 24)
            } else {
                SongRowWaveform().frame(width: 24)
            }
        } else {
            Text(
                (index + 1).formatted(
                    .number.locale(L10n.locale)
                )
            )
                .font(.body)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 24, alignment: .center)
        }
    }

    private var usesWideTrackColumns: Bool {
        detailMetrics.usesAdaptiveHeader
            && detailMetrics.viewport.width >= 720
            && !detailMetrics.usesAccessibilityText
    }

    private var primaryActionAccessibilityLabel: String {
        L10n.format(
            "ui.accessibility.song_and_artist",
            song.name,
            song.artistText
        )
    }

    private var primaryActionAccessibilityValue: String {
        guard isSelectingDownloads else {
            return isCurrentSong ? L10n.string("ui.player.now_playing") : ""
        }
        if !canSelectForDownload {
            return downloads.contains(songID: song.id)
                ? L10n.string("ui.downloads.downloaded")
                : L10n.string("ui.downloads.downloading")
        }
        return isSelectedForDownload
            ? L10n.string("ui.common.selected")
            : L10n.string("ui.common.not_selected")
    }

    private func primaryAction() {
        if isSelectingDownloads {
            guard canSelectForDownload else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                downloadSelection?.toggleSelection(songID: song.id)
            }
        } else {
            playOrPause()
        }
    }

    private func playOrPause() {
        if !isCurrentSong || !player.isPlaying { onPlayTrack?() }
        if isCurrentSong {
            player.togglePlayback()
        } else {
            Task { await player.play(song, in: tracks, sourceID: sourceID) }
        }
    }
}

private enum PlaylistSongSheet: Identifiable {
    case comments(Song)
    case addToPlaylist(Song)

    var id: String {
        switch self {
        case .comments(let song):
            "comments-\(song.id)"
        case .addToPlaylist(let song):
            "add-to-playlist-\(song.id)"
        }
    }
}
