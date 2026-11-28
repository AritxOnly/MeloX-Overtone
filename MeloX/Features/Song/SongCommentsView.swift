import Nuke
import NukeUI
import SwiftUI

struct CommentDiscussion: Identifiable {
    let threadID: String
    let resource: NeteaseShareResource?
    var commentID: Int64?
    var parentID: Int64?
    var originalComment: SongComment?
    var eventURL: URL?
    var id: String { "\(threadID):\(commentID ?? 0)" }
}

struct SongCommentsView: View {
    @Environment(NeteaseAPI.self) private var api
    @Environment(LibraryStore.self) private var library
    let discussion: CommentDiscussion

    @State private var sort: SongCommentSort = .popular
    @State private var displayedSort: SongCommentSort?
    @State private var firstPages: [SongCommentSort: SongCommentsResponse.Page] = [:]
    @State private var avatarPrefetcher = ImagePrefetcher(maxConcurrentRequestCount: 3)
    @State private var comments: [SongComment] = []
    @State private var total = 0
    @State private var nextCursor: String?
    @State private var nextPage = 1
    @State private var phase: LoadingPhase = .loading
    @State private var generation = UUID()
    @State private var hasScrolled = false
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var sending = false
    @State private var replyTarget: CommentReplyTarget?
    @State private var floorEdits: [Int64: SongCommentEdits] = [:]
    @State private var edits = SongCommentEdits()
    @State private var deleteCandidate: SongComment?
    @State private var deletionError: String?
    @State private var deleting: Set<Int64> = []

    @State private var hydratedSong: Song?
    @State private var metadataFailed = false
    private var headerResource: NeteaseShareResource? {
        hydratedSong.map(NeteaseShareResource.song) ?? discussion.resource
    }

    @State private var locatedComment: SongComment?
    @State private var locationError: String?
    @State private var locating = false

    private var visibleComments: [SongComment] {
        let posted = sort == .latest ? edits.posted : []
        return posted + comments.filter { !edits.deletedIDs.contains($0.id) && $0.id != locatedComment?.id }
    }

    var body: some View {
        ScrollView {
            songHero
            LazyVStack(alignment: .leading, spacing: 0) {
                Picker("ui.comments.title", selection: $sort) {
                    Text("ui.comments.popular").tag(SongCommentSort.popular)
                    Text("ui.comments.latest").tag(SongCommentSort.latest)
                }
                .pickerStyle(.segmented)
                .animation(.default, value: sort)
                .padding(.vertical, 6)

                if total > 0 {
                    Text(L10n.format("ui.comments.count", total))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }

                if let locatedComment, !edits.deletedIDs.contains(locatedComment.id) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("ui.messages.related_comments")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        thread(for: locatedComment)
                    }
                    .padding(12)
                    .background(.background, in: .rect(cornerRadius: 14))
                    .id("notification-comment")
                    .accessibilityIdentifier("notification-comment-\(locatedComment.id)")
                } else if locating {
                    ProgressView("ui.comments.loading")
                } else if let locationError {
                    VStack(alignment: .leading) {
                        Text(locationError).font(.footnote).foregroundStyle(.secondary)
                        Button("ui.common.retry") { Task { await locateComment() } }
                    }
                }

                ForEach(visibleComments) { root in thread(for: root) }

                switch phase {
                case .failed(let message):
                    VStack(spacing: 8) {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                        Button("ui.common.retry") { Task { await loadPage(reset: nextPage == 1) } }
                    }
                case .loading:
                    ProgressView("ui.comments.loading")
                case .loaded:
                    if let nextCursor {
                        ProgressView("ui.comments.loading_more")
                            .task(id: nextCursor) { await loadPage(reset: false) }
                    } else if visibleComments.isEmpty && locatedComment == nil {
                        ContentUnavailableView("ui.comments.empty", systemImage: "bubble.left")
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollPosition($scrollPosition)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectHidden(!hasScrolled, for: .top)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 0.5
        } action: { _, scrolled in
            hasScrolled = scrolled
        }
        .background(Color(uiColor: .systemGray6))
        .task(id: sort) {
            generation = UUID()
            displayedSort = sort
            if let cached = firstPages[sort] {
                apply(cached, cursor: "0", page: 1)
            } else {
                comments = []
                if edits.posted.isEmpty { total = 0 }
                nextCursor = nil
                nextPage = 1
                await loadPage(reset: true)
            }
        }
        .task(id: discussion.threadID) { await loadSongMetadata() }
        .task(id: discussion.id) { await locateComment() }
        .onChange(of: locatedComment?.id) { _, id in
            if id != nil { scrollPosition.scrollTo(id: "notification-comment", anchor: .center) }
        }
        .refreshable { await loadPage(reset: true) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SongCommentComposer(threadID: discussion.threadID, replyTarget: $replyTarget, isSending: $sending) { comment, target in
                if let target {
                    floorEdits[target.rootID, default: SongCommentEdits()].add(comment)
                    firstPages.removeAll()
                    return
                }
                edits.add(comment)
                total += 1
                firstPages.removeAll()
                scrollPosition.scrollTo(edge: .top)
                if sort == .latest {
                    await loadPage(reset: true)
                } else {
                    sort = .latest
                }
            }
        }
        .confirmationDialog("ui.comments.confirm_delete", isPresented: Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        ), titleVisibility: .visible, presenting: deleteCandidate) { comment in
            Button("ui.comments.delete", role: .destructive) {
                Task { await delete(comment) }
            }
            Button("ui.common.cancel", role: .cancel) {}
        }
        .alert("ui.comments.delete_failed", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) { Button("ui.common.ok", role: .cancel) {} } message: { Text(deletionError ?? "") }
    }

    private func locateComment() async {
        guard let id = discussion.commentID, id > 0, !locating else { return }
        if let original = discussion.originalComment, original.id == id, !original.content.isEmpty {
            locatedComment = original
            return
        }
        locating = true
        locationError = nil
        defer { locating = false }
        do {
            let parent = discussion.parentID.flatMap { $0 > 0 ? $0 : nil } ?? id
            var cursor: Int64 = -1
            var requested = Set<Int64>()
            while requested.insert(cursor).inserted {
                let floor = try await api.resourceCommentReplies(threadID: discussion.threadID, parentCommentID: parent, time: cursor).data
                try Task.checkCancellation()
                let candidates = [floor.ownerComment].compactMap { $0 } + floor.bestComments + floor.comments
                if let match = candidates.first(where: { $0.id == id }) {
                    locatedComment = match
                    return
                }
                guard floor.hasMore, let next = floor.time else { break }
                cursor = next
            }
            if let match = comments.first(where: { $0.id == id }) { locatedComment = match }
            else { locationError = L10n.string("ui.comments.target_unavailable") }
        } catch {
            if !Task.isCancelled { locationError = error.localizedDescription }
        }
    }

    private func thread(for root: SongComment) -> some View {
        SongCommentThread(
            threadID: discussion.threadID, root: root,
            featured: sort == .popular && root.id == comments.first?.id,
            avatarPrefetcher: avatarPrefetcher,
            deletedIDs: edits.deletedIDs,
            localReplies: Binding(
                get: { floorEdits[root.id] ?? SongCommentEdits() },
                set: { floorEdits[root.id] = $0 }
            ),
            onReply: { if !sending { replyTarget = CommentReplyTarget(rootID: root.id, comment: $0) } },
            onDelete: { deleteCandidate = $0 }
        )
    }

    private func delete(_ comment: SongComment) async {
        guard comment.id > 0, library.isLoggedIn, library.profile?.id == comment.user.id,
              deleting.insert(comment.id).inserted else { return }
        defer { deleting.remove(comment.id) }
        do {
            try await api.deleteResourceComment(comment.id, threadID: discussion.threadID)
            if replyTarget?.comment.id == comment.id || replyTarget?.rootID == comment.id { replyTarget = nil }
            edits.delete(comment.id)
            if let floor = floorEdits.keys.first(where: { floorEdits[$0]?.posted.contains(comment) == true }) {
                floorEdits[floor]?.delete(comment.id)
            }
            total = max(0, total - 1)
            firstPages.removeAll()
        } catch {
            deletionError = error.localizedDescription
        }
    }

    private func loadSongMetadata() async {
        let prefix = "R_SO_4_"
        guard discussion.threadID.hasPrefix(prefix),
              let id = Int(discussion.threadID.dropFirst(prefix.count)), id > 0 else { return }
        if case .song(let song) = headerResource, song.id == id, !song.artists.isEmpty,
           !song.name.isEmpty, song.name != L10n.string("ui.metadata.unknown_song"), song.album?.artworkURL != nil { return }
        metadataFailed = false
        do {
            let songs = try await api.songDetails(ids: [id])
            try Task.checkCancellation()
            guard let song = songs.first(where: { $0.id == id }) else { throw APIError.invalidResponse }
            hydratedSong = song
        } catch {
            if !Task.isCancelled { metadataFailed = true }
        }
    }

    private var songHero: some View {
        LazyImage(url: headerResource?.artworkURL ?? discussion.resource?.artworkURL) { state in
            let artwork = state.image
            HStack(alignment: .bottom, spacing: 16) {
                Group {
                    if let image = artwork {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "music.note")
                            .font(.largeTitle)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.white.opacity(0.12))
                    }
                }
                .frame(width: 88, height: 88)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(headerResource?.title ?? L10n.string("ui.comments.title"))
                        .font(.system(.title, design: .serif, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle = headerResource?.subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    }
                    if metadataFailed {
                        Button("ui.common.retry") { Task { await loadSongMetadata() } }
                            .font(.subheadline)
                    }
                    if let url = discussion.eventURL {
                        Link("ui.messages.open_event", destination: url).font(.subheadline)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if let image = artwork {
                    image.resizable().scaledToFill()
                        .scaleEffect(1.08)
                        .blur(radius: 8)
                        .overlay {
                            LinearGradient(
                                colors: [.black.opacity(0.12), .black.opacity(0.52)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        }
                        .accessibilityHidden(true)
                } else {
                    Color(white: 0.22)
                }
            }
            .clipped()
        }
    }

    private func loadPage(reset: Bool) async {
        let requestedSort = sort
        if !reset, nextCursor == nil || displayedSort != requestedSort { return }
        let request = UUID()
        generation = request
        let cursor = reset ? "0" : nextCursor ?? "0"
        let page = reset ? 1 : nextPage
        if reset { phase = .loading }
        do {
            let result = try await api.resourceComments(threadID: discussion.threadID, sort: requestedSort, cursor: cursor, page: page).data
            try Task.checkCancellation()
            guard generation == request, sort == requestedSort else { return }
            if reset { firstPages[requestedSort] = result }
            apply(result, cursor: cursor, page: page)
        } catch {
            guard !Task.isCancelled, generation == request, sort == requestedSort else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func apply(_ result: SongCommentsResponse.Page, cursor: String, page: Int) {
        var seen = page == 1 ? Set<Int64>() : Set(comments.map(\.id))
        let roots = (result.comments ?? []).filter { $0.isRoot && seen.insert($0.id).inserted }
        if sort == .latest { edits.reconcile(with: roots) }
        comments = page == 1 ? roots : comments + roots
        avatarPrefetcher.startPrefetching(with: roots.prefix(10).compactMap { $0.user.artworkURL })
        total = max(0, result.totalCount - roots.filter { edits.deletedIDs.contains($0.id) }.count)
        if sort == .latest, page == 1 { total += edits.posted.count }
        nextPage = page + 1
        nextCursor = result.hasMore && result.cursor != cursor ? result.cursor : nil
        phase = .loaded
    }
}

private struct SongCommentComposer: View {
    let threadID: String
    @Binding var replyTarget: CommentReplyTarget?
    @Binding var isSending: Bool
    let onPosted: (SongComment, CommentReplyTarget?) async -> Void

    @Environment(NeteaseAPI.self) private var api
    @Environment(LibraryStore.self) private var library
    @FocusState private var isFocused: Bool
    @State private var draft = ""
    @State private var showsLogin = false
    @State private var sendError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let target = replyTarget {
                HStack {
                    Text(L10n.format("ui.comments.replying_to", target.comment.user.nickname))
                        .lineLimit(1)
                    Spacer()
                    Button { replyTarget = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("ui.common.cancel")
                        .disabled(isSending)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            inputRow
        }
        .onChange(of: replyTarget) { _, target in
            if target != nil { isFocused = true }
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .padding(.horizontal, 32)
        .padding(.vertical, 6)
        .sheet(isPresented: $showsLogin) {
            NavigationStack { NeteaseLoginView() }
        }
        .alert("ui.comments.send_failed", isPresented: Binding(
            get: { sendError != nil },
            set: { if !$0 { sendError = nil } }
        )) {
            Button("ui.common.ok", role: .cancel) {}
        } message: {
            Text(sendError ?? "")
        }
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField("ui.comments.write", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.leading, 16)
                .padding(.vertical, 12)
                .focused($isFocused)
                .disabled(isSending)

            Button(action: send) {
                Group {
                    if isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .disabled(trimmedDraft.isEmpty || isSending)
            .accessibilityLabel("ui.common.send")
        }
        .padding(.trailing, 2)

    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() {
        let content = trimmedDraft
        guard !content.isEmpty, !isSending else { return }
        guard library.isLoggedIn else {
            isFocused = false
            showsLogin = true
            return
        }
        let target = replyTarget
        isSending = true
        Task {
            do {
                let profile: AccountProfile
                if let current = library.profile { profile = current }
                else { profile = try await api.accountProfile() }
                let sentAt = Date()
                let receipt = try await api.postResourceComment(content, threadID: threadID, replyingTo: target?.comment.id)
                let author = SongCommentUser(id: profile.id, nickname: profile.nickname,
                                             avatarURLString: profile.avatarURLString)
                draft = ""
                isFocused = false
                isSending = false
                if replyTarget == target { replyTarget = nil }
                await onPosted(receipt.postedComment(content: content, author: author, sentAt: sentAt, replyingTo: target), target)
            } catch {
                isSending = false
                sendError = error.localizedDescription
            }
        }
    }
}

struct SongCommentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openMusicRoute) private var openMusicRoute
    @State private var selectedPlaylist: Playlist?
    @Namespace private var navigationNamespace
    let discussion: CommentDiscussion

    init(song: Song) {
        discussion = CommentDiscussion(threadID: "R_SO_4_\(song.id)", resource: .song(song))
    }

    init(discussion: CommentDiscussion) {
        self.discussion = discussion
    }

    var body: some View {
        NavigationStack {
            SongCommentsView(discussion: discussion)
                .ignoresSafeArea(.container, edges: .top)
                .musicDestinations(in: navigationNamespace) { playlist in
                    selectedPlaylist = playlist
                    dismiss()
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.primary)
                        }
                        .tint(.primary)
                        .accessibilityLabel("ui.comments.close")
                    }
                }
        }
        .environment(\.musicNavigationNamespace, navigationNamespace)
        .presentationBackground(Color(uiColor: .systemGray6))
        .presentationDragIndicator(.visible)
        .onDisappear {
            if let playlist = selectedPlaylist {
                selectedPlaylist = nil
                openMusicRoute(.playlist(playlist))
            }
        }
    }
}
