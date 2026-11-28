import SwiftUI

extension InboxFeed {
    var symbol: String {
        switch self {
        case .followers: "person.fill"
        case .comments, .mentions: "text.bubble.fill"
        case .notices: "hand.thumbsup.fill"
        }
    }

    var color: Color {
        switch self {
        case .followers: .red
        case .comments, .mentions: .blue
        case .notices: .orange
        }
    }

    var groupTitle: String {
        self == .comments || self == .mentions ? L10n.string("ui.messages.interactions") : title
    }

    var icon: some View {
        Image(systemName: symbol)
            .font(.title3.weight(.semibold)).foregroundStyle(.white)
            .frame(width: 44, height: 44).background(color, in: Circle())
            .accessibilityHidden(true)
    }
}

struct InboxActivityView: View {
    let category: InboxFeed
    let userID: Int
    let onLoaded: (InboxFeed, String?) -> Void
    @State private var selection: InboxFeed = .comments

    var body: some View {
        let feed = category == .comments ? selection : category
        InboxActivityList(feed: feed, userID: userID, onLoaded: onLoaded)
            .id(feed)
            .safeAreaBar(edge: .top, spacing: 0) {
                if category == .comments {
                    Picker("ui.messages.interactions", selection: $selection) {
                        Text(InboxFeed.comments.title).tag(InboxFeed.comments)
                        Text(InboxFeed.mentions.title).tag(InboxFeed.mentions)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle(category.groupTitle)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct InboxActivityList: View {
    @Environment(NeteaseAPI.self) private var api
    let feed: InboxFeed
    let userID: Int
    let onLoaded: (InboxFeed, String?) -> Void
    @State private var selectedItem: InboxActivity?
    @Namespace private var navigationNamespace
    @State private var items: [InboxActivity] = []
    @State private var phase: LoadingPhase = .loading
    @State private var loading = false
    @State private var more = false
    @State private var offset = 0
    @State private var before: Int64 = -1

    var body: some View {
        List {
            ForEach(items) { item in
                if feed != .followers {
                    Button { selectedItem = item } label: {
                        activityRow(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .foregroundStyle(.primary)
                    }
                    .accessibilityIdentifier("activity-row-\(item.id)")
                } else {
                    NavigationLink {
                        InboxActivityDetail(item: item, feed: feed) {
                            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].followed = true }
                        }
                    } label: { activityRow(item) }
                }
            }
            if more {
                Button("ui.messages.load_more") { Task { await load(reset: false) } }
                    .disabled(loading)
            }
            if case .failed(let message) = phase {
                ConnectionUnavailableView(message: message) { Task { await load(reset: items.isEmpty) } }
            } else if items.isEmpty {
                if loading { ProgressView() }
                else { ContentUnavailableView("ui.messages.no_activity", systemImage: feed.symbol) }
            }
        }
        .listStyle(.plain)
        .task { await load(reset: true) }
        .refreshable { await load(reset: true) }
        .sheet(item: $selectedItem) { item in
            if let thread = item.threadID {
                SongCommentsSheet(discussion: CommentDiscussion(threadID: thread, resource: item.resource,
                    commentID: item.commentID, parentID: item.parentCommentID,
                    originalComment: item.originalComment, eventURL: item.eventURL))
            } else {
                NavigationStack {
                    InboxActivityDetail(item: item, feed: feed, onFollow: {})
                        .musicDestinations(in: navigationNamespace)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("ui.common.done") { selectedItem = nil }
                            }
                        }
                }
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func activityRow(_ item: InboxActivity) -> some View {
        HStack(spacing: 12) {
            if let author = item.author {
                ArtworkImage(url: author.artworkURL, cornerRadius: 24, placeholderSymbol: "person.fill")
                    .frame(width: 44, height: 44)
            } else { feed.icon }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.author?.displayName ?? feed.title).font(.headline)
                Text(item.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(.vertical, 1)
    }

    private func load(reset: Bool) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let response = try await api.inboxActivityPage(feed, userID: userID, offset: reset ? 0 : offset,
                                                           before: reset ? -1 : before)
            let page = try response.activities(for: feed)
            try Task.checkCancellation()
            if reset { items = []; offset = 0; before = -1 }
            var seen = Set(items.map(\.id))
            let added = page.filter { seen.insert($0.id).inserted }
            items += added
            offset += page.count
            let next = page.last?.time ?? 0
            let cursorAdvanced = feed == .followers || feed == .mentions || (next > 0 && next != before)
            more = (response.more ?? (page.count == 30)) && !added.isEmpty && cursorAdvanced
            before = next
            phase = .loaded
            if reset, let first = items.first {
                let summary = [first.author?.displayName, first.text].compactMap { $0 }.joined(separator: " ")
                onLoaded(feed, summary)
            } else if reset { onLoaded(feed, nil) }
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

private struct InboxActivityDetail: View {
    @Environment(NeteaseAPI.self) private var api
    let item: InboxActivity
    let feed: InboxFeed
    let onFollow: () -> Void
    @State private var followed = false
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        List {
            if let author = item.author, author.id > 0 {
                NavigationLink(value: AccountProfile(userID: author.id, nickname: author.nickname, avatarURLString: author.avatarURLString)) {
                    HStack {
                        ArtworkImage(url: author.artworkURL, cornerRadius: 20).frame(width: 40, height: 40)
                        Text(author.displayName).font(.headline)
                    }
                }
                if feed == .followers {
                    Button(followed || item.followed == true ? "ui.messages.following_user" : "ui.messages.follow_user") {
                        Task { await follow(author.id) }
                    }.disabled(followed || item.followed == true || sending)
                    NavigationLink("ui.messages.start_private_message", value: NeteasePrivateMessageRoute.conversation(author))
                }
            }
            Text(item.text)
            if let quote = item.quotedText, !quote.isEmpty {
                Text(verbatim: "“\(quote)”").foregroundStyle(.secondary)
            }
            if item.time > 0 {
                Text(Date(timeIntervalSince1970: Double(item.time) / 1000), format: .dateTime)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let resource = item.resource {
                NavigationLink(value: resource.messageRoute) { Label(resource.title, systemImage: "music.note") }
            }
            if let url = item.eventURL {
                Link(destination: url) { Label("ui.messages.open_event", systemImage: "arrow.up.right.square") }
            }
        }
        .navigationTitle(feed.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("ui.error.netease_operation_incomplete", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("ui.common.ok", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func follow(_ id: Int) async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        do {
            try await api.followInboxUser(id)
            followed = true
            onFollow()
        } catch { self.error = error.localizedDescription }
    }
}
