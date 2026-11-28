import SwiftUI

struct NeteaseConversationView: View {
    let contact: NeteaseMessageContact
    var onMarkedRead: () -> Void = {}

    @Environment(NeteaseAPI.self) private var api
    @Environment(LibraryStore.self) private var library

    @State private var messages: [NeteasePrivateMessage] = []
    @State private var resolvedSongArtworkURLs: [Int: URL] = [:]
    @State private var currentUserID = 0
    @State private var draft = ""
    @State private var phase: LoadingPhase = .loading
    @State private var isSending = false
    @State private var sendError: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .defaultScrollAnchor(.bottom)
            .refreshable {
                await load()
            }
            .onChange(of: messages.last?.id) { _, messageID in
                guard let messageID else { return }
                withAnimation {
                    proxy.scrollTo(messageID, anchor: .bottom)
                }
            }
        }
        .background { ConversationBarTransition() }
        .navigationTitle(contact.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                contactLink {
                    ArtworkImage(url: contact.artworkURL, cornerRadius: 22, placeholderSymbol: "person.fill")
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .scaleEffect(1.15, anchor: .top)
                        .offset(y: 3)
                }
                .accessibilityHidden(true)
            }
        }
        .overlay {
            switch phase {
            case .loading where messages.isEmpty:
                ProgressView("ui.messages.loading_private_messages")
            case .failed(let message) where messages.isEmpty:
                ConnectionUnavailableView(message: message) {
                    Task { await load() }
                }
            case .loaded where messages.isEmpty:
                ContentUnavailableView(
                    "ui.messages.no_messages",
                    systemImage: "bubble.left",
                    description: Text("ui.messages.no_messages.message")
                )
            default:
                EmptyView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            contactLink {
                HStack(spacing: 5) {
                    Text(contact.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if contact.id > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.horizontal, 44)
                .frame(minHeight: 44, alignment: .top)
                .offset(y: -6)
            }
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .task(id: contact.id) {
            await load()
        }
        .alert(
            "ui.messages.send_failed",
            isPresented: Binding(
                get: { sendError != nil },
                set: { if !$0 { sendError = nil } }
            )
        ) {
            Button("ui.common.retry") { send() }
            Button("ui.common.cancel", role: .cancel) {
                sendError = nil
            }
        } message: {
            Text(sendError ?? L10n.string("ui.error.netease_operation_incomplete"))
        }
    }

    @ViewBuilder
    private func contactLink<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        if contact.id > 0 {
            NavigationLink(value: AccountProfile(userID: contact.id, nickname: contact.nickname,
                                                 avatarURLString: contact.avatarURLString), label: label)
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.format("ui.account.profile_for_user", contact.displayName))
        } else {
            label()
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 4) {
            TextField("ui.messages.input_private_message", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.leading, 16)
                .padding(.vertical, 11)
                .disabled(isSending)
                .submitLabel(.send)
                .onSubmit(send)

            Button(action: send) {
                Group {
                    if isSending { ProgressView() }
                    else { Image(systemName: "arrow.up.circle.fill").font(.title) }
                }
                .frame(width: 44, height: 44)
            }
            .disabled(trimmedDraft.isEmpty || isSending)
            .accessibilityLabel("ui.common.send")
        }
        .padding(.trailing, 2)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func messageRow(_ message: NeteasePrivateMessage) -> some View {
        let isOutgoing = message.isOutgoing(currentUserID: currentUserID)
        return HStack {
            if isOutgoing {
                Spacer(minLength: 56)
            }

            VStack(
                alignment: isOutgoing ? .trailing : .leading,
                spacing: 5
            ) {
                messageContent(message.payload, isOutgoing: isOutgoing)

                if message.time > 0 {
                    Text(messageTime(message.time))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !isOutgoing {
                Spacer(minLength: 56)
            }
        }
    }

    @ViewBuilder
    private func messageContent(
        _ payload: NeteasePrivateMessagePayload,
        isOutgoing: Bool
    ) -> some View {
        if let resource = payload.resource {
            NavigationLink(value: resource.messageRoute) {
                VStack(alignment: .leading, spacing: 7) {
                    if !payload.text.isEmpty {
                        Text(payload.text)
                            .foregroundStyle(isOutgoing ? .white : .primary)
                    }

                    HStack(spacing: 9) {
                        ArtworkImage(
                            url: artworkURL(for: resource),
                            cornerRadius: 6
                        )
                        .id(artworkURL(for: resource))
                        .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(resource.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(resource.kindTitle)
                                .font(.caption)
                                .foregroundStyle(
                                    isOutgoing
                                        ? AnyShapeStyle(.white.opacity(0.75))
                                        : AnyShapeStyle(.secondary)
                                )
                        }
                    }
                }
                .padding(10)
                .background(
                    isOutgoing
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(.quaternary),
                    in: .rect(cornerRadius: 14)
                )
            }
            .buttonStyle(.plain)
        } else {
            Text(payload.summary)
                .foregroundStyle(isOutgoing ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    isOutgoing
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(.quaternary),
                    in: .rect(cornerRadius: 14)
                )
        }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func messageTime(_ milliseconds: Int64) -> String {
        Date(
            timeIntervalSince1970: TimeInterval(milliseconds) / 1_000
        )
        .formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(L10n.locale)
        )
    }

    private func artworkURL(for resource: NeteaseShareResource) -> URL? {
        guard case .song(let song) = resource else {
            return resource.artworkURL
        }
        return resolvedSongArtworkURLs[song.id] ?? resource.artworkURL
    }

    private func load() async {
        phase = .loading
        do {
            if let profileID = library.profile?.id {
                currentUserID = profileID
            } else {
                currentUserID = try await api.accountProfile().id
            }
            let loadedMessages = try await api.privateMessageHistory(
                userID: contact.id
            )
            messages = loadedMessages
            phase = .loaded
            onMarkedRead()
            await resolveSongArtwork(in: loadedMessages)
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func resolveSongArtwork(
        in messages: [NeteasePrivateMessage]
    ) async {
        let songIDs = Set(
            messages.compactMap { message -> Int? in
                guard case .song(let song) = message.payload.resource,
                      song.id > 0,
                      resolvedSongArtworkURLs[song.id] == nil else {
                    return nil
                }
                return song.id
            }
        )
        guard !songIDs.isEmpty else { return }

        do {
            let songs = try await api.songDetails(ids: Array(songIDs))
            guard !Task.isCancelled else { return }
            for song in songs {
                if let artworkURL = song.album?.artworkURL {
                    resolvedSongArtworkURLs[song.id] = artworkURL
                }
            }
        } catch is CancellationError {
            return
        } catch {
            // 封面补全失败不应影响私信正文和卡片本身的展示。
        }
    }

    private func send() {
        let content = trimmedDraft
        guard !content.isEmpty, !isSending else { return }

        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await api.sendPrivateText(content, to: [contact.id])
                draft = ""
                await load()
            } catch is CancellationError {
                return
            } catch {
                sendError = error.localizedDescription
            }
        }
    }
}

/// Keep the tab bar and its player accessory on the same push or pop transition.
private struct ConversationBarTransition: UIViewControllerRepresentable {
    @Environment(\.setTabViewBottomAccessorySuppressed) private var suppressPlayer

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.suppressPlayer = suppressPlayer
    }

    final class Controller: UIViewController {
        var suppressPlayer = SetTabViewBottomAccessorySuppressedAction()

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            updateBars(hidden: true, animated: animated)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            updateBars(hidden: false, animated: animated)
        }

        private func updateBars(hidden: Bool, animated: Bool) {
            guard let tabs = tabBarController else { return }
            let coordinator = transitionCoordinator
            let duration = coordinator?.transitionDuration ?? 0.3
            func settle(hidden: Bool) {
                tabs.setTabBarHidden(hidden, animated: false)
                suppressPlayer(hidden)
                tabs.tabBar.alpha = 1
                tabs.bottomAccessory?.contentView.alpha = 1
            }
            guard animated || coordinator != nil, !UIAccessibility.isReduceMotionEnabled else {
                settle(hidden: hidden)
                return
            }
            if !hidden {
                UIView.performWithoutAnimation {
                    tabs.setTabBarHidden(false, animated: false)
                    tabs.tabBar.alpha = 0
                    tabs.view.layoutIfNeeded()
                }
                withAnimation(.easeInOut(duration: duration)) { suppressPlayer(false) }
            }
            let fade = {
                tabs.tabBar.alpha = hidden ? 0 : 1
                tabs.bottomAccessory?.contentView.alpha = hidden ? 0 : 1
            }
            if let coordinator,
               coordinator.animate(alongsideTransition: { _ in fade() }, completion: { context in
                   settle(hidden: context.isCancelled ? !hidden : hidden)
               }) {
                return
            }
            UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                fade()
            } completion: { finished in
                if finished { settle(hidden: hidden) }
            }
        }
    }
}

extension NeteaseShareResource {
    var messageRoute: MusicRoute {
        switch self {
        case .song(let song):
            .song(song)
        case .playlist(let playlist):
            .playlist(playlist)
        case .album(let album):
            .album(album)
        }
    }
}
