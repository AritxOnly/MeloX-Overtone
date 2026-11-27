import Nuke
import SwiftUI

struct SongCommentThread: View {
    @Environment(NeteaseAPI.self) private var api
    @Environment(\.colorScheme) private var colorScheme

    let songID: Int
    let root: SongComment
    let featured: Bool

    let avatarPrefetcher: ImagePrefetcher
    let deletedIDs: Set<Int64>
    @Binding var localReplies: SongCommentEdits
    let onReply: (SongComment) -> Void
    let onDelete: (SongComment) -> Void
    private static let batchSize = 10
    @State private var visibleLimit = Self.batchSize
    @State private var expanded = false
    @State private var replies: [SongComment] = []
    @State private var authors: [Int64: String] = [:]
    @State private var nextTime: Int64? = -1
    @State private var errorMessage: String?
    @State private var loading = false

    private var visibleReplies: [SongComment] {
        (localReplies.posted + replies).filter { !deletedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: featured ? 6 : 1) {
            SongCommentRow(comment: root, featured: featured, onReply: { onReply(root) }, onDelete: onDelete)
            let replyCount = max(0, root.replyCount + localReplies.posted.count - replies.filter { deletedIDs.contains($0.id) }.count)
            if replyCount > 0 {
                Button {
                    expanded.toggle()
                    visibleLimit = Self.batchSize
                    if expanded && nextTime == -1 {
                        Task { await loadPage() }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(expanded ? L10n.string("ui.common.collapse")
                             : L10n.format("ui.comments.expand_replies", replyCount))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .imageScale(.small)
                    }
                    .font(.caption)
                    .padding(.vertical, 3)
                }
                .padding(.leading, 40)
                .buttonStyle(.borderless)
            }
        }
        .padding(featured ? 16 : 0)
        .background {
            if featured {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark
                          ? Color(red: 0.22, green: 0.18, blue: 0.17)
                          : Color(red: 0.957, green: 0.922, blue: 0.902))
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)

        .onChange(of: localReplies.posted.first?.id, initial: true) { _, newest in
            guard newest != nil else { return }
            expanded = true
            if nextTime == -1 { Task { await loadPage() } }
        }

        if expanded {
            ForEach(visibleReplies.prefix(visibleLimit)) { reply in
                SongCommentRow(comment: reply, isFloorReply: true, replyTarget: reply.replyTarget(inFloor: root.id, authors: authors), onReply: { onReply(reply) }, onDelete: onDelete)
                    .padding(.leading, 40)
                    .padding(.vertical, 4)
            }
            if let errorMessage {
                VStack(alignment: .leading) {
                    Text(errorMessage).font(.caption).foregroundStyle(.secondary)
                    Button("ui.common.retry") { Task { await loadPage() } }
                }
                .padding(.leading, 40)
            } else if visibleReplies.isEmpty && nextTime == -1 {
                ProgressView("ui.comments.replies.loading")
            } else if nextTime != nil || visibleReplies.count > visibleLimit {
                Button("ui.comments.more_replies") {
                    visibleLimit = min(visibleLimit, visibleReplies.count) + Self.batchSize
                    if visibleReplies.count < visibleLimit && nextTime != nil {
                        Task { await loadPage() }
                    }
                }
                .disabled(loading)
                .padding(.leading, 40)
            } else if visibleReplies.isEmpty {
                Text("ui.comments.replies.empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 40)
            }
        }
    }

    // A newly submitted reply belongs to this floor even while its read endpoint catches up.
    private func loadPage() async {
        guard let cursor = nextTime, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await api.songCommentReplies(
                songID: songID, parentCommentID: root.id, time: cursor, limit: Self.batchSize
            ).data
            try Task.checkCancellation()
            var seen = Set(replies.map(\.id))
            seen.insert(root.id)
            let rows = (page.bestComments + page.comments).filter { seen.insert($0.id).inserted }
            for row in rows { authors[row.id] = row.user.nickname }
            let newVisibleCount = max(0, visibleLimit - replies.count)
            avatarPrefetcher.startPrefetching(with: rows.prefix(newVisibleCount).compactMap { $0.user.artworkURL })
            localReplies.reconcile(with: rows)
            replies.append(contentsOf: rows)
            nextTime = page.hasMore && page.time != cursor ? page.time : nil
            errorMessage = nil
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }
}
