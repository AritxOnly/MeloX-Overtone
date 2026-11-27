import SwiftUI

enum NeteasePrivateMessageRoute: Hashable {
    case contacts
    case conversation(NeteaseMessageContact)
}

struct NeteasePrivateMessagesView: View {
    @Environment(NeteaseAPI.self) private var api
    @Environment(LibraryStore.self) private var library

    @State private var conversations: [NeteasePrivateConversation] = []
    @State private var currentUserID = 0
    @State private var phase: LoadingPhase = .loading
    @State private var isLoadingConversations = false
    @State private var mayHaveMoreUnreadConversations = false
    @State private var isMarkingAllRead = false
    @State private var markAllReadError: String?

    @State private var unreadOnly = false

    private var visibleConversations: [NeteasePrivateConversation] {
        unreadOnly ? conversations.filter { $0.unreadCount > 0 } : conversations
    }

    private var canMarkAllRead: Bool {
        currentUserID > 0 && !isLoadingConversations && !isMarkingAllRead
            && (mayHaveMoreUnreadConversations || conversations.contains { $0.unreadCount > 0 })
    }

    var body: some View {
        List {
            ForEach(visibleConversations) { conversation in
                let contact = conversation.participant(
                    currentUserID: currentUserID
                )
                NavigationLink(
                    value: NeteasePrivateMessageRoute.conversation(contact)
                ) {
                    conversationRow(conversation, contact: contact)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(unreadOnly ? L10n.string("ui.messages.unread_title") : L10n.string("ui.messages.private.title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isMarkingAllRead = true
                } label: {
                    if isMarkingAllRead {
                        ProgressView()
                    } else {
                        Image(systemName: "envelope.open")
                    }
                }
                .accessibilityLabel("ui.messages.mark_all_read")
                .disabled(!canMarkAllRead)
                .tint(.primary)

                Menu {
                    Picker("ui.messages.filter.title", selection: $unreadOnly) {
                        Text("ui.messages.filter.all").tag(false)
                        Text("ui.messages.filter.unread").tag(true)
                    }
                } label: {
                    Label("ui.messages.filter.title", systemImage: unreadOnly
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: NeteasePrivateMessageRoute.contacts) {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("ui.messages.start_private_message")
                .tint(.primary)
            }
        }
        .refreshable {
            await load()
        }
        .overlay {
            switch phase {
            case .loading where conversations.isEmpty:
                ProgressView("ui.messages.loading_private_messages")
            case .failed(let message) where conversations.isEmpty:
                ConnectionUnavailableView(message: message) {
                    Task { await load() }
                }
            case .loaded where conversations.isEmpty:
                ContentUnavailableView {
                    Label("ui.messages.empty", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("ui.messages.empty.message")
                } actions: {
                    NavigationLink(
                        "ui.messages.start_private_message",
                        value: NeteasePrivateMessageRoute.contacts
                    )
                    .buttonStyle(.borderedProminent)
                }
            case .loaded where unreadOnly && visibleConversations.isEmpty:
                ContentUnavailableView("ui.messages.all_read", systemImage: "envelope.open")
            default:
                EmptyView()
            }
        }
        .navigationDestination(for: NeteasePrivateMessageRoute.self) { route in
            switch route {
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
        .task {
            await load()
        }
        .task(id: isMarkingAllRead) {
            if isMarkingAllRead {
                await markAllRead()
            }
        }
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

    private func conversationRow(
        _ conversation: NeteasePrivateConversation,
        contact: NeteaseMessageContact
    ) -> some View {
        let unread = conversation.unreadCount > 0
        return HStack(spacing: 9) {
            Circle()
                .fill(.blue)
                .frame(width: 8, height: 8)
                .opacity(unread ? 1 : 0)
                .accessibilityHidden(true)

            ArtworkImage(url: contact.artworkURL, cornerRadius: 24, placeholderSymbol: "person.fill")
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(contact.displayName)
                        .font(.body.weight(unread ? .bold : .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if conversation.lastMessageTime > 0 {
                        Text(formattedTime(conversation.lastMessageTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                messagePreview(conversation.lastMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(unread ? L10n.format("ui.messages.unread_count", conversation.unreadCount) : "")
    }

    @ViewBuilder
    private func messagePreview(_ payload: NeteasePrivateMessagePayload) -> some View {
        if let resource = payload.resource {
            if !payload.text.isEmpty {
                Text(payload.text)
                    .lineLimit(1)
            }
            Label {
                Text(resource.title)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "music.note")
            }
            .accessibilityLabel(L10n.format("ui.messages.resource_summary", resource.kindTitle, resource.title))
        } else {
            Text(payload.summary)
                .lineLimit(2)
        }
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
        guard let index = conversationIndex(for: contactID) else { return }
        conversations[index].unreadCount = 0
    }

    private func conversationIndex(for contactID: Int) -> Int? {
        conversations.firstIndex { conversation in
            conversation.participant(currentUserID: currentUserID).id == contactID
        }
    }

    private func load() async {
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
            let page = try await api.privateMessageConversationsPage()
            conversations = page.messages
            mayHaveMoreUnreadConversations = page.more == true
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
        } catch is CancellationError {
            return
        } catch {
            markAllReadError = error.localizedDescription
        }
    }
}
