import SwiftUI

enum NeteasePrivateMessageRoute: Hashable {
    case activity(InboxFeed)
    case contacts
    case conversation(NeteaseMessageContact)
}

struct NeteasePrivateMessagesView: View {
    @Environment(LibraryStore.self) private var library
    @State private var showingLogin = false

    var body: some View {
        if library.isLoggedIn {
            MessageInbox().id(library.profile?.id)
        } else {
            ContentUnavailableView {
                Label("ui.account.login_required", systemImage: "person.crop.circle")
            } actions: {
                Button("ui.account.login_netease") { showingLogin = true }
                    .buttonStyle(.borderedProminent)
            }
            .navigationTitle("ui.messages.inbox")
            .sheet(isPresented: $showingLogin) { NavigationStack { NeteaseLoginView() } }
        }
    }
}

private struct MessageInbox: View {
    @Environment(NeteaseAPI.self) private var api
    @Environment(LibraryStore.self) private var library

    @State private var conversations: [NeteasePrivateConversation] = []
    @State private var currentUserID = 0
    @State private var phase: LoadingPhase = .loading
    @State private var isLoadingConversations = false
    @State private var hasMoreConversations = false
    @State private var mayHaveMoreUnreadConversations = false
    @State private var isMarkingAllRead = false
    @State private var markAllReadError: String?

    @State private var unreadOnly = false

    @State private var query = ""
    @State private var searching = false
    @State private var confirmRead = false
    @State private var pinned: Set<Int> = []
    @State private var reminders: Set<Int> = []
    @State private var counts: InboxCounts?
    @State private var previews: [InboxFeed: String] = [:]
    @State private var markingContact: Int?
    @State private var nextOffset = 0
    @State private var readError: String?

    private var visibleConversations: [NeteasePrivateConversation] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = conversations.filter {
            let contact = $0.participant(currentUserID: currentUserID)
            return (!unreadOnly || unreadCount($0, contact.id) > 0)
                && (term.isEmpty || contact.displayName.localizedCaseInsensitiveContains(term)
                    || contact.nickname.localizedCaseInsensitiveContains(term))
        }
        return matches.filter { pinned.contains(peerID($0)) } + matches.filter { !pinned.contains(peerID($0)) }
    }

    private var recentContacts: [NeteaseMessageContact] {
        var seen: Set<Int> = []
        var contacts: [NeteaseMessageContact] = []
        for conversation in conversations {
            let contact = conversation.participant(currentUserID: currentUserID)
            if contact.id > 0, seen.insert(contact.id).inserted {
                contacts.append(contact)
                if contacts.count == 12 { break }
            }
        }
        return contacts
    }

    private var canMarkAllRead: Bool {
        currentUserID > 0 && !isLoadingConversations && !isMarkingAllRead && markingContact == nil
            && (mayHaveMoreUnreadConversations || !reminders.isEmpty || conversations.contains { $0.unreadCount > 0 })
    }

    var body: some View {
        List {
            if !searching {
                if !recentContacts.isEmpty { contactRail }
                ForEach([InboxFeed.followers, .comments, .notices]) { feed in
                    NavigationLink(value: NeteasePrivateMessageRoute.activity(feed)) {
                        HStack(spacing: 12) {
                            feed.icon
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feed.groupTitle).font(.headline)
                                if let preview = previews[feed] {
                                    Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            if let count = counts?.count(for: feed), count > 0 { badge(count) }
                        }
                    }
                    .disabled(currentUserID <= 0)
                    .listRowSeparator(.hidden)
                }
            }
            Section {
                ForEach(visibleConversations) { conversation in
                    conversationLink(conversation)
                }
                listStatus
                if hasMoreConversations {
                    Button("ui.messages.load_more") { Task { await load(more: true) } }
                        .disabled(isLoadingConversations || isMarkingAllRead)
                }
            } header: {
                HStack {
                    Text("ui.messages.private.title").font(.headline)
                    Spacer()
                    Menu {
                        Picker("ui.messages.filter.title", selection: $unreadOnly) {
                            Text("ui.messages.filter.all").tag(false)
                            Text("ui.messages.filter.unread").tag(true)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(unreadOnly ? "ui.messages.filter.unread" : "ui.messages.filter.all")
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                    }.font(.subheadline).accessibilityLabel("ui.messages.filter.title")
                }.textCase(nil)
            }
        }
        .listStyle(.plain)
        .navigationTitle("ui.messages.inbox")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, isPresented: $searching, placement: .toolbar, prompt: "ui.messages.search")
        .searchToolbarBehavior(.minimize)
        .toolbar {
            DefaultToolbarItem(kind: .search, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink(value: NeteasePrivateMessageRoute.contacts) {
                        Label("ui.messages.start_private_message", systemImage: "square.and.pencil")
                    }
                    Button { confirmRead = true } label: {
                        Label("ui.messages.read_all_chats", systemImage: "envelope.open")
                    }.disabled(!canMarkAllRead)
                } label: {
                    Label("ui.common.more", systemImage: "ellipsis")
                        .foregroundStyle(.primary)
                }
                .tint(.primary)
            }
        }
        .refreshable {
            async let badges: Void = refreshCounts()
            await load()
            await badges
        }
        .confirmationDialog("ui.messages.read_all_chats", isPresented: $confirmRead, titleVisibility: .visible) {
            Button("ui.messages.read_all_chats") { isMarkingAllRead = true }
        }
        .navigationDestination(for: NeteasePrivateMessageRoute.self) { route in
            switch route {
            case .activity(let feed):
                InboxActivityView(category: feed, userID: currentUserID) { loaded, preview in
                    previews[loaded == .mentions ? .comments : loaded] = preview
                }
                .onDisappear { Task { await refreshCounts() } }
            case .contacts:
                NeteaseMessageContactsView()
            case .conversation(let contact):
                NeteaseConversationView(contact: contact) {
                    // 只有历史接口成功返回后才清除本地角标。首次历史
                    // 请求会同时在网易云服务端完成已读上报。
                    clearUnreadCount(for: contact.id)
                }
                .onDisappear {
                    Task {
                        await load()
                    }
                }
            }
        }
        .task { await refreshCounts() }
        .task {
            await load()
        }
        .task(id: isMarkingAllRead) {
            if isMarkingAllRead {
                await markAllRead()
            }
        }
        .alert("ui.messages.mark_read_failed", isPresented: Binding(get: { readError != nil }, set: { if !$0 { readError = nil } })) {
            Button("ui.common.ok", role: .cancel) {}
        } message: { Text(readError ?? "") }
        .alert(
            "ui.messages.mark_all_read_failed",
            isPresented: Binding(
                get: { markAllReadError != nil },
                set: { if !$0 { markAllReadError = nil } }
            )
        ) {
            Button("ui.common.ok", role: .cancel) {}
        } message: {
            Text(markAllReadError ?? "")
        }
    }

    private func conversationLink(_ conversation: NeteasePrivateConversation) -> some View {
        let contact = conversation.participant(currentUserID: currentUserID)
        return NavigationLink(value: NeteasePrivateMessageRoute.conversation(contact)) {
            conversationRow(conversation, contact: contact)
        }
        .navigationLinkIndicatorVisibility(.hidden)
        .listRowBackground(pinned.contains(contact.id) ? Color(uiColor: .secondarySystemBackground) : Color.clear)
        .swipeActions(edge: .leading) { pinButton(contact.id) }
        .swipeActions(edge: .trailing) { readButton(conversation, contact.id) }
        .contextMenu { pinButton(contact.id); readButton(conversation, contact.id) }
    }

    private var contactRail: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(recentContacts) { contact in
                    NavigationLink(value: NeteasePrivateMessageRoute.conversation(contact)) {
                        VStack(spacing: 6) {
                            ArtworkImage(url: contact.artworkURL, cornerRadius: 30, placeholderSymbol: "person.fill")
                                .frame(width: 54, height: 54)
                            Text(contact.displayName).font(.caption).lineLimit(1)
                        }.frame(width: 64)
                    }
                    .buttonStyle(.plain)
                }
            }.padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
        .listRowSeparator(.hidden)
    }

    @ViewBuilder private var listStatus: some View {
        switch phase {
        case .loading where conversations.isEmpty:
            ProgressView("ui.messages.loading_private_messages")
        case .failed(let message):
            ConnectionUnavailableView(message: message) { Task { await load() } }
        case .loaded where visibleConversations.isEmpty:
            if !query.isEmpty { ContentUnavailableView.search(text: query) }
            else if unreadOnly { ContentUnavailableView("ui.messages.all_read", systemImage: "envelope.open") }
            else {
                ContentUnavailableView {
                    Label("ui.messages.empty", systemImage: "bubble.left.and.bubble.right")
                } actions: {
                    NavigationLink("ui.messages.start_private_message", value: NeteasePrivateMessageRoute.contacts)
                        .buttonStyle(.borderedProminent)
                }
            }
        default: EmptyView()
        }
    }

    private func peerID(_ conversation: NeteasePrivateConversation) -> Int {
        conversation.participant(currentUserID: currentUserID).id
    }

    private func unreadCount(_ conversation: NeteasePrivateConversation, _ id: Int) -> Int {
        max(conversation.unreadCount, reminders.contains(id) ? 1 : 0)
    }

    private func pinButton(_ id: Int) -> some View {
        Button {
            if !pinned.insert(id).inserted { pinned.remove(id) }
            savePreferences()
        } label: {
            Label(pinned.contains(id) ? "ui.messages.unpin" : "ui.messages.pin",
                  systemImage: pinned.contains(id) ? "pin.slash" : "pin")
        }.tint(.orange)
    }

    private func readButton(_ conversation: NeteasePrivateConversation, _ id: Int) -> some View {
        let unread = unreadCount(conversation, id) > 0
        return Button {
            if conversation.unreadCount > 0 {
                markingContact = id
                Task {
                    defer { markingContact = nil }
                    do {
                        _ = try await api.privateMessageHistory(userID: id, limit: 1)
                        clearUnreadCount(for: id)
                    } catch { readError = error.localizedDescription }
                }
            } else {
                if unread { reminders.remove(id) } else { reminders.insert(id) }
                savePreferences()
            }
        } label: {
            Label(unread ? "ui.messages.mark_read" : "ui.messages.mark_unread",
                  systemImage: unread ? "envelope.open" : "envelope.badge")
        }.tint(.blue).disabled(isLoadingConversations || isMarkingAllRead || markingContact != nil)
    }

    private func badge(_ number: Int) -> some View {
        Text(number > 99 ? "99+" : String(number)).font(.caption2.bold())
            .padding(.horizontal, 5).padding(.vertical, 2)
            .foregroundStyle(.white).background(.red, in: Capsule())
            .accessibilityLabel(L10n.format("ui.messages.unread_count", number))
    }

    private func conversationRow(_ conversation: NeteasePrivateConversation, contact: NeteaseMessageContact) -> some View {
        HStack(spacing: 12) {
            ArtworkImage(url: contact.artworkURL, cornerRadius: 24, placeholderSymbol: "person.fill")
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(contact.displayName).font(.headline).lineLimit(1)
                    if pinned.contains(contact.id) {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                            .accessibilityLabel("ui.messages.pinned")
                    }
                    Spacer()
                    if conversation.lastMessageTime > 0 {
                        Text(formattedTime(conversation.lastMessageTime)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    if let resource = conversation.lastMessage.resource {
                        Label(resource.title, systemImage: "music.note")
                    } else { Text(conversation.lastMessage.summary) }
                    Spacer(minLength: 4)
                    let count = unreadCount(conversation, contact.id)
                    if count > 0 { badge(count) }
                }.font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }.alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }.padding(.vertical, 2).accessibilityElement(children: .combine)
    }

    private func formattedTime(_ milliseconds: Int64) -> String {
        let date = Date(
            timeIntervalSince1970: TimeInterval(milliseconds) / 1_000
        )
        if Calendar.current.isDateInToday(date) {
            return date.formatted(
                Date.FormatStyle(date: .omitted, time: .shortened)
                    .locale(L10n.locale)
            )
        }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(L10n.locale)
        )
    }

    private func clearUnreadCount(for contactID: Int) {
        if reminders.remove(contactID) != nil { savePreferences() }
        guard let index = conversationIndex(for: contactID) else { return }
        conversations[index].unreadCount = 0
    }

    private func conversationIndex(for contactID: Int) -> Int? {
        conversations.firstIndex { conversation in
            conversation.participant(currentUserID: currentUserID).id == contactID
        }
    }

    private func savePreferences() {
        guard currentUserID > 0 else { return }
        UserDefaults.standard.set(Array(pinned), forKey: "inbox.pins.\(currentUserID)")
        UserDefaults.standard.set(Array(reminders), forKey: "inbox.reminders.\(currentUserID)")
    }

    private func refreshCounts() async {
        guard library.isLoggedIn else { return }
        if let snapshot = try? await api.inboxCounts() { counts = snapshot }
    }

    private func load(more: Bool = false) async {
        guard !isLoadingConversations, !isMarkingAllRead else { return }
        isLoadingConversations = true
        defer { isLoadingConversations = false }
        phase = .loading
        do {
            if let profileID = library.profile?.id {
                currentUserID = profileID
            } else {
                currentUserID = try await api.accountProfile().id
            }
            pinned = Set(UserDefaults.standard.array(forKey: "inbox.pins.\(currentUserID)") as? [Int] ?? [])
            reminders = Set(UserDefaults.standard.array(forKey: "inbox.reminders.\(currentUserID)") as? [Int] ?? [])
            let offset = more ? nextOffset : 0
            let page = try await api.privateMessageConversationsPage(offset: offset)
            try Task.checkCancellation()
            if !more { conversations = [] }
            var seen = Set(conversations.map(\.id))
            conversations += page.messages.filter { seen.insert($0.id).inserted }
            nextOffset = offset + page.messages.count
            hasMoreConversations = page.more == true && !page.messages.isEmpty
            mayHaveMoreUnreadConversations = hasMoreConversations && (!more || mayHaveMoreUnreadConversations)
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func markAllRead() async {
        defer { isMarkingAllRead = false }
        do {
            try await api.markAllPrivateMessagesRead(
                currentUserID: currentUserID,
                onMarkedRead: clearUnreadCount(for:)
            )
            for index in conversations.indices {
                conversations[index].unreadCount = 0
            }
            mayHaveMoreUnreadConversations = false
            reminders.removeAll()
            savePreferences()
        } catch is CancellationError {
            return
        } catch {
            markAllReadError = error.localizedDescription
        }
    }
}
