import SwiftUI

struct NowPlayingQueuePage: View {
    @Environment(PlayerStore.self) private var player

    let song: Song
    let presentation: NowPlayingLyricsPresentation
    let artworkNamespace: Namespace.ID
    let usesArtworkTransition: Bool
    let showsSongHeader: Bool
    let onSongHeaderHiddenChange: (Bool) -> Void
    let onSongHeaderOffsetChange: (CGFloat) -> Void
    let onReorderingChange: (Bool) -> Void
    @State private var isReordering = false

    @State private var songHeaderHeight = NowPlayingSongHeader.referenceHeight
    @State private var scrollOffset: CGFloat = 0
    @State private var isSongHeaderHidden = false
    @State private var isSongHeaderAtRest = true

    init(
        song: Song,
        presentation: NowPlayingLyricsPresentation,
        artworkNamespace: Namespace.ID,
        usesArtworkTransition: Bool = true,
        showsSongHeader: Bool = true,
        onSongHeaderHiddenChange:
            @escaping (Bool) -> Void = { _ in },
        onSongHeaderOffsetChange:
            @escaping (CGFloat) -> Void = { _ in },
        onReorderingChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.onReorderingChange = onReorderingChange
        self.song = song
        self.presentation = presentation
        self.artworkNamespace = artworkNamespace
        self.usesArtworkTransition = usesArtworkTransition
        self.showsSongHeader = showsSongHeader
        self.onSongHeaderHiddenChange = onSongHeaderHiddenChange
        self.onSongHeaderOffsetChange = onSongHeaderOffsetChange
    }

    var body: some View {
        VStack(spacing: 0) {
            UpcomingQueueList(
                entries: upcomingEntries,
                headerInset: reservedSongHeaderHeight + 60,
                indicatorInset: visibleQueueTopInset,
                onScroll: { offset in
                    updateSongHeaderState(for: min(max(offset, 0), reservedSongHeaderHeight))
                },
                onReordering: { active in
                    isReordering = active
                    onReorderingChange(active)
                },
                onMove: moveQueueItems
            )
            .mask {
                Rectangle()
                    .padding(.top, visibleQueueTopInset)
            }
            .overlay(alignment: .top) {
                // A single set of controls moves continuously, then stays at
                // the top without swapping between two header containers.
                NowPlayingQueueModeControls()
                    .padding(.vertical, 8)
                    .frame(height: 60)
                    .offset(y: modeControlsOffset)
            }
            .overlay(alignment: .top) {
                if presentation == .portrait && showsSongHeader {
                    NowPlayingSongHeader(
                        song: song,
                        artworkNamespace: artworkNamespace,
                        usesReferenceLayout: true,
                        usesArtworkTransition: usesArtworkTransition && isSongHeaderAtRest
                    )
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { newHeight in
                        if newHeight > 0 {
                            songHeaderHeight = newHeight
                        }
                    }
                    .offset(y: -scrollOffset)
                    .clipped()
                }
            }
            .padding(.bottom, bottomContentInset)
        }
        .onDisappear {
            isReordering = false
            onReorderingChange(false)
        }
        .onAppear {
            if presentation == .portrait {
                scrollOffset = 0
                isSongHeaderHidden = false
                isSongHeaderAtRest = true
                onSongHeaderHiddenChange(false)
                onSongHeaderOffsetChange(0)
            }
        }
    }

    private var upcomingEntries: [UpcomingQueueEntry] {
        var occurrences: [Int: Int] = [:]
        return player.unplayedQueueIndices.compactMap { index in
            guard player.queue.indices.contains(index) else {
                return nil
            }
            let song = player.queue[index]
            let occurrence = occurrences[song.id, default: 0]
            occurrences[song.id] = occurrence + 1
            return UpcomingQueueEntry(
                id: UpcomingQueueEntry.ID(
                    songID: song.id,
                    occurrence: occurrence
                ),
                queueIndex: index,
                song: song
            )
        }
    }

    private var bottomContentInset: CGFloat {
        presentation == .portrait
            ? (isReordering ? 0 : NowPlayingBottomControls.coreHeight)
            : 12
    }

    private var reservedSongHeaderHeight: CGFloat {
        presentation == .portrait ? songHeaderHeight : 0
    }

    private var modeControlsOffset: CGFloat {
        max(reservedSongHeaderHeight - scrollOffset, 0)
    }

    private var visibleQueueTopInset: CGFloat {
        modeControlsOffset + 60
    }

    private func updateSongHeaderState(for offset: CGFloat) {
        guard presentation == .portrait else { return }

        scrollOffset = offset

        onSongHeaderOffsetChange(
            -min(offset, max(songHeaderHeight, 0))
        )

        let isHidden =
            songHeaderHeight > 0
            && offset >= songHeaderHeight
        if isSongHeaderHidden != isHidden {
            isSongHeaderHidden = isHidden
            onSongHeaderHiddenChange(isHidden)
        }

        let isAtRest = offset <= 0.5
        if isSongHeaderAtRest != isAtRest {
            isSongHeaderAtRest = isAtRest
        }
    }

    private func moveQueueItems(
        from source: IndexSet,
        to destination: Int
    ) {
        withAnimation(.smooth(duration: 0.28)) {
            player.moveUpcomingQueueItems(
                fromOffsets: source,
                toOffset: destination
            )
        }
    }
}

private struct NowPlayingQueueModeControls: View {
    @Environment(PlayerStore.self) private var player

    var body: some View {
        HStack(spacing: 14) {
            modeButton(
                systemImage: "shuffle",
                isSelected: player.isShuffled,
                isEnabled: true,
                accessibilityLabel:
                    player.isShuffled
                        ? L10n.string("ui.player.shuffle_off")
                        : L10n.string("ui.player.shuffle_on"),
                action: toggleShuffle
            )

            modeButton(
                systemImage: player.repeatMode.systemImage,
                isSelected: player.repeatMode != .off,
                isEnabled: true,
                accessibilityLabel:
                    player.repeatMode.accessibilityTitle,
                action: cycleRepeatMode
            )

            modeButton(
                systemImage: "infinity",
                isSelected: player.isAutoplayEnabled,
                isEnabled: !player.isListenTogetherSessionActive,
                accessibilityLabel:
                    player.isAutoplayEnabled
                        ? L10n.string("ui.player.autoplay_off")
                        : L10n.string("ui.player.autoplay_on"),
                action: toggleAutoplay
            )

            modeButton(
                systemImage: "circle.circle.fill",
                isSelected: player.isAutoMixEnabled,
                isEnabled: !player.isListenTogetherSessionActive,
                accessibilityLabel:
                    player.isAutoMixEnabled
                        ? L10n.string("ui.player.automix_off")
                        : L10n.string("ui.player.automix_on"),
                action: toggleAutoMix
            )
        }
    }

    private func modeButton(
        systemImage: String,
        isSelected: Bool,
        isEnabled: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .contentTransition(
                    .symbolEffect(.replace.downUp.wholeSymbol)
                )
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundStyle(
                    isSelected
                        ? .black.opacity(0.62)
                        : .white.opacity(0.86)
                )
                .background(
                    .white.opacity(isSelected ? 0.7 : 0.12),
                    in: .rect(cornerRadius: 22)
                )
                .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(
            isEnabled
                ? ""
                : L10n.string("ui.listen_together.playback_mode_managed")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggleShuffle() {
        withAnimation(.smooth(duration: 0.34)) {
            player.toggleShuffle()
        }
    }

    private func cycleRepeatMode() {
        withAnimation(.smooth(duration: 0.34)) {
            player.cycleRepeatMode()
        }
    }

    private func toggleAutoplay() {
        withAnimation(.smooth(duration: 0.34)) {
            player.toggleAutoplay()
        }
    }

    private func toggleAutoMix() {
        withAnimation(.smooth(duration: 0.34)) {
            player.toggleAutoMix()
        }
    }
}

struct NowPlayingQueueRow: View {
    @Environment(PlayerStore.self) private var player

    let entry: UpcomingQueueEntry
    let previewWidth: () -> CGFloat
    private let previewShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                SongRowArtwork(songID: entry.song.id, url: entry.song.album?.artworkURL,
                               representsCurrentEntry: entry.queueIndex == player.currentIndex)
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.song.name)
                        .font(.body)
                        .lineLimit(1)

                    Text(entry.song.artistText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .contentShape(.contextMenuPreview, previewShape)
        .contextMenu {
            QueueEntryActions(song: entry.song, index: entry.queueIndex)
        } preview: {
            HStack(spacing: 14) {
                ArtworkImage(url: entry.song.album?.artworkURL, cornerRadius: 8)
                    .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: entry.song.name).font(.headline).lineLimit(2)
                    Text(verbatim: entry.song.artistText).font(.subheadline).lineLimit(2)
                    if let album = entry.song.album, !album.name.isEmpty {
                        Text(verbatim: album.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(minWidth: 0, idealWidth: previewWidth(), maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: previewShape)
            .clipShape(previewShape)
            .contentShape(.contextMenuPreview, previewShape)
            .preferredColorScheme(.dark)
        }
    }

    private func play() {
        Task {
            await player.playFromQueue(at: entry.queueIndex)
        }
    }
}

struct UpcomingQueueEntry: Identifiable, Equatable {
    struct ID: Hashable {
        let songID: Int
        let occurrence: Int
    }

    let id: ID
    let queueIndex: Int
    let song: Song
}
