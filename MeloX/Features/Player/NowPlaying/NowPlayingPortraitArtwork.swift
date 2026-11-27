import SwiftUI

enum NowPlayingPortraitCoordinateSpace {
    static let name = "nowPlayingPortraitPageContent"
}

struct NowPlayingPortraitArtwork: View {
    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    let song: Song
    let isArtworkPage: Bool

    @State private var bounceScale: CGFloat = 1

    var body: some View {
        ArtworkImage(
            url: song.album?.artworkURL,
            cornerRadius: isArtworkPage ? 10 : 8
        )
        .scaleEffect(bounceScale)
        .accessibilityElement()
        .accessibilityLabel(L10n.format("ui.song.artwork_accessibility", song.name))
        .task(id: shouldBounce) {
            await animateBounce()
        }
    }

    private var shouldBounce: Bool {
        isArtworkPage && player.isPlaying
    }

    private func animateBounce() async {
        bounceScale = 1
        guard shouldBounce, !accessibilityReduceMotion else {
            return
        }

        await Task.yield()
        withAnimation(.easeOut(duration: 0.17)) {
            bounceScale = 1.055
        }

        do {
            try await Task.sleep(for: .milliseconds(170))
        } catch {
            return
        }

        withAnimation(.spring(duration: 0.42, bounce: 0.24)) {
            bounceScale = 1
        }
    }
}

struct NowPlayingArtworkShadow: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PlayerStore.self) private var player

    var isVisible = true

    func body(content: Content) -> some View {
        content
            .shadow(
                color: isVisible ? .black.opacity(player.isPlaying ? 0.34 : 0.18) : .clear,
                radius: player.isPlaying ? 26 : 14,
                y: player.isPlaying ? 15 : 8
            )
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.3),
                value: player.isPlaying
            )
    }
}
