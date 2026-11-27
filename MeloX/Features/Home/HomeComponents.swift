import SwiftUI

extension MusicShelfLayout {
    var homeInset: CGFloat { max(horizontalPadding, 20) }
    var homeCoverSize: CGFloat {
        isWide ? artworkSize(compact: 160) : containerWidth * 0.4
    }
}

struct HomeEditorialCard: View {
    @Environment(\.musicShelfLayout) private var layout
    let action: HomeQuickAction
    let artworkURL: URL?
    let detail: String

    private var aspectRatio: CGFloat { layout.isWide ? 1.2 : 3.0 / 4 }

    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: action.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let artworkURL {
                    ArtworkImage(url: artworkURL, cornerRadius: 0, aspectRatio: aspectRatio)
                } else {
                    RadialGradient(colors: [.white.opacity(0.32), .clear], center: .trailing,
                                   startRadius: 0, endRadius: 180)
                }
            }
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.35),
                                       .init(color: .black.opacity(0.78), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: action.systemImage)
                    .font(.headline.weight(.semibold))
                    .padding(14)
                    .accessibilityHidden(true)
            }
            .overlay {
                if artworkURL == nil {
                    Text(action.title)
                        .font(layout.isWide ? .title2.bold() : .largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.eyebrow)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                    if artworkURL != nil {
                        Text(action.title).font(.title2.bold())
                    }
                    Text(detail)
                        .font(.subheadline)
                        .lineLimit(layout.isWide ? 2 : 3)
                }
                .padding(16)
            }
            .foregroundStyle(.white)
            .clipShape(.rect(cornerRadius: 16))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(action.title)
            .accessibilityValue(detail)
    }
}

struct HomePlaylistCard: View {
    @Environment(\.musicShelfLayout) private var layout
    let playlist: Playlist

    private var subtitle: String? {
        [playlist.copywriter, playlist.updateFrequency, playlist.creator?.nickname]
            .lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    var body: some View {
        MediaCardView(
            title: playlist.name,
            subtitle: subtitle,
            artworkURL: playlist.artworkURL,
            artworkSize: layout.homeCoverSize
        )
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: layout.homeCoverSize)
    }
}
