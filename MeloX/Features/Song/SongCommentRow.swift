import NukeUI
import SwiftUI

struct SongCommentRow: View {
    @Environment(LibraryStore.self) private var library
    let comment: SongComment
    var featured = false
    var isFloorReply = false
    var replyTarget: String?
    let onReply: () -> Void
    let onDelete: (SongComment) -> Void

    private var canDelete: Bool {
        comment.id > 0 && comment.user.id > 0 && library.isLoggedIn && library.profile?.id == comment.user.id
    }

    var body: some View {
        if canDelete {
            row.contentShape(.rect)
                .contextMenu {
                    Button("ui.comments.copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = comment.content }
                    Button("ui.comments.delete", systemImage: "trash", role: .destructive) { onDelete(comment) }
                }
        } else {
            row.contextMenu {
                Button("ui.comments.copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = comment.content }
            }
        }
    }

    private var row: some View {
        Group {
            if featured {
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: "quote.opening")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    replyButton
                        .font(.system(.headline, design: .serif, weight: .semibold))
                        .lineSpacing(4)
                    HStack(spacing: 8) {
                        avatar
                        VStack(alignment: .leading, spacing: 2) {
                            author
                            metadata
                        }
                        Spacer(minLength: 4)
                        likes
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    avatar
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            author
                            Spacer(minLength: 4)
                            likes
                        }
                        metadata
                        replyButton
                            .font(isFloorReply ? .footnote : .callout)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ScaledMetric(relativeTo: .callout) private var faceSize: CGFloat = 18
    private static let atlas = UIImage(named: "NetEaseCommentFaces")?.cgImage
    private static let tiles = NSCache<NSString, UIImage>()

    private var replyButton: some View {
        Button(action: onReply) {
            let text = replyTarget.map { L10n.format("ui.comments.reply_to", $0, comment.content) } ?? comment.content
            inlineText(text)
                .multilineTextAlignment(.leading)
                .accessibilityLabel(text)
        }
        .buttonStyle(.plain)
        .disabled(comment.id <= 0)
        .accessibilityHint("ui.comments.tap_reply")
    }

    private func inlineText(_ text: String) -> Text {
        var result = Text(verbatim: "")
        var start = text.startIndex
        for match in text.matches(of: #/\[([^\[\]\r\n]{1,24})\]/#) {
            guard let tile = CommentEmoticons.tiles[String(match.1)],
                  let atlas = Self.atlas else { continue }
            let key = "\(tile)-\(faceSize)" as NSString
            let image: UIImage
            if let cached = Self.tiles.object(forKey: key) {
                image = cached
            } else {
                let rect = CGRect(x: tile % 8 * 60, y: tile / 8 * 60, width: 60, height: 60)
                guard let crop = atlas.cropping(to: rect) else { continue }
                image = UIImage(cgImage: crop, scale: 60 / faceSize, orientation: .up)
                Self.tiles.setObject(image, forKey: key)
            }
            let prefix = String(text[start..<match.range.lowerBound])
            result = Text("\(result)\(Text(verbatim: prefix))\(Image(uiImage: image))")
            start = match.range.upperBound
        }
        return Text("\(result)\(Text(verbatim: String(text[start...])))")
    }

    private var author: some View {
        profileLink {
            Text(comment.user.nickname).font(.subheadline.weight(.semibold))
        }
    }

    private var metadata: some View {
        HStack(spacing: 5) {
            Text(commentDateText)
            if let location = comment.ipLocation?.location, !location.isEmpty {
                Text(location)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var likes: some View {
        HStack(spacing: 3) {
            Image(systemName: comment.isLiked ? "heart.fill" : "heart")
                .foregroundStyle(comment.isLiked ? Color.pink : .secondary)
            if comment.likedCount > 0 {
                Text(comment.likedCount.formatted(.number.locale(L10n.locale)))
            }
        }
        .accessibilityLabel(L10n.format("ui.comments.like_count", comment.likedCount))
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var avatar: some View {
        profileLink { avatarImage.contentShape(.interaction, Rectangle().inset(by: -5)) }
    }

    @ViewBuilder
    private func profileLink<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        if comment.user.id > 0 {
            NavigationLink(value: AccountProfile(userID: comment.user.id, nickname: comment.user.nickname,
                                                 avatarURLString: comment.user.avatarURLString)) {
                label()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.format("ui.account.profile_for_user", comment.user.nickname))
        } else {
            label()
        }
    }

    private var avatarImage: some View {
        let size: CGFloat = isFloorReply ? 24 : 32
        return LazyImage(url: comment.user.artworkURL) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                Text(String(comment.user.nickname.prefix(1)))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemFill))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }

    private var commentDateText: String {
        if let description = comment.timeDescription, !description.isEmpty {
            return description
        }
        guard let time = comment.time else { return "" }
        return Date(timeIntervalSince1970: time / 1_000).formatted(
            .dateTime.year().month().day().locale(L10n.locale)
        )
    }
}
