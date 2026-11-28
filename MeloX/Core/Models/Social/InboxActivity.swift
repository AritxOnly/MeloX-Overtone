import Foundation

enum InboxFeed: String, CaseIterable, Identifiable {
    case followers, comments, mentions, notices
    var id: Self { self }
    var title: String { L10n.string("ui.messages.feed." + rawValue) }
}

struct InboxCounts: Decodable {
    let code: Int
    let follow: Int?
    let comment: Int?
    let forward: Int?
    let notice: Int?

    func count(for feed: InboxFeed) -> Int {
        switch feed {
        case .followers: follow ?? 0
        case .comments: (comment ?? 0) + (forward ?? 0)
        case .mentions: forward ?? 0
        case .notices: notice ?? 0
        }
    }
}

struct InboxActivity: Identifiable {
    let id: String
    let author: NeteaseMessageContact?
    let text: String
    let time: Int64
    var threadID: String?
    var commentID: Int64?
    var resource: NeteaseShareResource?
    var followed: Bool?
    var quotedText: String?
    var parentCommentID: Int64?
    var originalComment: SongComment?

    var eventURL: URL? {
        guard let threadID, threadID.hasPrefix("A_EV_2_") else { return nil }
        let ids = threadID.dropFirst("A_EV_2_".count).split(separator: "_")
        guard ids.count == 2, let event = Int64(ids[0]), event > 0,
              let owner = Int64(ids[1]), owner > 0 else { return nil }
        return URL(string: "https://music.163.com/event?id=\(event)&uid=\(owner)")
    }

}

// Notice and event messages wrap their actual payload in a serialized JSON string.
private struct InboxPayload: Decodable {
    let user: NeteaseMessageContact?
    let event: InboxActivityWire.Event?
    let threadId: String?
    let commentThread: InboxThread?
    let resourceInfo: InboxResourceReference?
    let track: Song?
    let playlist: Playlist?
    let album: Album?
    let comment: InboxComment?
    let song: Song?
    let msg: String?

    var resource: NeteaseShareResource? {
        if let track = track ?? song, track.id > 0 { return .song(track) }
        if let playlist, playlist.id > 0 { return .playlist(playlist) }
        if let album, album.id > 0 { return .album(album) }
        return nil
    }
}

struct InboxThread: Decodable {
    let id: String?
}

private struct InboxNumber: Decodable {
    let value: Int?
    init(from decoder: Decoder) throws {
        let field = try decoder.singleValueContainer()
        value = (try? field.decode(Int.self)) ?? (try? field.decode(String.self)).flatMap(Int.init)
    }
}

private struct InboxResourceReference: Decodable {
    let threadID: String?

    enum CodingKeys: String, CodingKey { case threadId, commentThreadId, resourceId, resourceType, id }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        if let thread = (try? fields.decode(String.self, forKey: .threadId))
            ?? (try? fields.decode(String.self, forKey: .commentThreadId)), !thread.isEmpty {
            threadID = thread
            return
        }
        func integer(_ key: CodingKeys) -> Int? {
            (try? fields.decode(InboxNumber.self, forKey: key))?.value
        }
        let prefixes = [4: "R_SO_4_", 3: "R_AL_3_", 0: "A_PL_0_", 5: "R_MV_5_", 1: "A_DJ_1_"]
        if let type = integer(.resourceType), let prefix = prefixes[type],
           let id = integer(.resourceId) ?? integer(.id), id > 0 {
            threadID = prefix + String(id)
        } else { threadID = nil }
    }
}

private struct InboxComment: Decodable {
    let parentCommentId: Int64?
    let original: SongComment?

    enum CodingKeys: CodingKey { case parentCommentId, commentThreadId, commentThread, commentId, threadId, content, resourceInfo }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        parentCommentId = try fields.decodeIfPresent(Int64.self, forKey: .parentCommentId)
        commentThreadId = try fields.decodeIfPresent(String.self, forKey: .commentThreadId)
        commentThread = try fields.decodeIfPresent(InboxThread.self, forKey: .commentThread)
        commentId = try fields.decodeIfPresent(Int64.self, forKey: .commentId)
        threadId = try fields.decodeIfPresent(String.self, forKey: .threadId)
            ?? (try? fields.decode(InboxResourceReference.self, forKey: .resourceInfo))?.threadID
        content = try fields.decodeIfPresent(String.self, forKey: .content)
        original = try? SongComment(from: decoder)
    }

    let commentThreadId: String?
    let commentThread: InboxThread?
    let commentId: Int64?
    let threadId: String?
    let content: String?
}

struct InboxActivityWire: Decodable {
    private let resourceId: InboxNumber?
    private let resourceType: InboxNumber?
    let parentCommentId: Int64?
    let id: Int64?
    let commentId: Int64?
    let threadId: String?
    let time: Int64?
    let lasttime: Int64?
    let user: NeteaseMessageContact?
    let content: String?
    let beRepliedContent: String?
    let notice: String?
    let json: String?
    let resourceJson: String?
    let eventId: Int64?
    let eventTime: Int64?
    let commentThreadId: String?
    let info: Event.Info?
    let event: Event?

    struct Event: Decodable {
        struct Info: Decodable { let commentThread: InboxThread? }
        let id: Int64?
        let info: Info?
        let threadId: String?

        let user: NeteaseMessageContact?
        let json: String?
        let eventTime: Int64?
    }

    func activity(in feed: InboxFeed) -> InboxActivity {
        let embedded = [notice, event?.json, json, resourceJson].compactMap { $0 }.compactMap {
            try? JSONDecoder().decode(InboxPayload.self, from: Data($0.utf8))
        }
        let original = event ?? embedded.compactMap(\.event).first
        let author = user ?? original?.user ?? embedded.compactMap(\.user).first
        let comment = embedded.compactMap(\.comment).first
        let nestedIDs = [comment?.threadId, comment?.commentThreadId, comment?.commentThread?.id]
        let reference = resourceJson.flatMap { try? JSONDecoder().decode(InboxResourceReference.self, from: Data($0.utf8)) }
        let resourceIDs = embedded.map(\.threadId) + embedded.map { $0.commentThread?.id }
            + embedded.map { $0.resourceInfo?.threadID } + [reference?.threadID]
        let eventIDs = [original?.threadId, original?.info?.commentThread?.id, info?.commentThread?.id]
        let candidates = [threadId, commentThreadId] + nestedIDs + resourceIDs + eventIDs
        var target = candidates.compactMap { $0 }.first { !$0.isEmpty }
        if target == nil, resourceType?.value == 4, let resourceId = resourceId?.value, resourceId > 0 { target = "R_SO_4_\(resourceId)" }
        let originalID = original?.id ?? eventId ?? (feed == .mentions && eventTime != nil ? id : nil)
        if target == nil, let originalID, originalID > 0,
           let owner = original?.user?.id ?? (feed == .mentions ? user?.id : nil), owner > 0 {
            target = "A_EV_2_\(originalID)_\(owner)"
        }
        let timestamp = time ?? lasttime ?? original?.eventTime ?? eventTime ?? 0
        let text = [content] + embedded.map(\.msg) + embedded.map { $0.comment?.content }
        let resource = embedded.compactMap(\.resource).first ?? directResource(threadID: target)
        if target == nil, let resource {
            switch resource {
            case .song(let song): target = "R_SO_4_\(song.id)"
            case .album(let album): target = "R_AL_3_\(album.id)"
            case .playlist(let playlist): target = "A_PL_0_\(playlist.id)"
            }
        }
        let summary = text.compactMap { $0 }.first { !$0.isEmpty } ?? resource?.title ?? feed.title
        let key = (id ?? commentId).map(String.init) ?? "\(timestamp)-\(author?.id ?? 0)-\(summary)"
        return InboxActivity(id: "\(feed.rawValue)-\(key)", author: author, text: summary,
                             time: timestamp, threadID: target, commentID: commentId ?? comment?.commentId,
                             resource: resource, quotedText: beRepliedContent,
                             parentCommentID: comment?.parentCommentId ?? parentCommentId, originalComment: comment?.original)
    }

    private func directResource(threadID: String?) -> NeteaseShareResource? {
        guard let resourceJson, let threadId = threadID else { return nil }
        let decoder = JSONDecoder(), data = Data(resourceJson.utf8)
        if threadId.hasPrefix("R_SO_4_"), let song = try? decoder.decode(Song.self, from: data), song.id > 0 {
            return .song(song)
        }
        if threadId.hasPrefix("A_PL_0_"), let playlist = try? decoder.decode(Playlist.self, from: data), playlist.id > 0 {
            return .playlist(playlist)
        }
        if threadId.hasPrefix("R_AL_3_"), let album = try? decoder.decode(Album.self, from: data), album.id > 0 {
            return .album(album)
        }
        return nil
    }
}

struct InboxActivityResponse: Decodable {
    struct Follower: Decodable {
        let contact: NeteaseMessageContact
        let followed: Bool?
        enum CodingKeys: CodingKey { case followed }

        init(from decoder: Decoder) throws {
            contact = try NeteaseMessageContact(from: decoder)
            followed = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Bool.self, forKey: .followed)
        }
    }

    let code: Int
    let message: String?
    let followeds: [Follower]?
    let comments: [InboxActivityWire]?
    let forwards: [InboxActivityWire]?
    let notices: [InboxActivityWire]?
    let more: Bool?

    func activities(for feed: InboxFeed) throws -> [InboxActivity] {
        switch feed {
        case .followers:
            guard let followeds else { throw APIError.invalidResponse }
            return followeds.map {
                InboxActivity(id: "fan-\($0.contact.id)", author: $0.contact,
                              text: L10n.string("ui.messages.followed_you"), time: 0, followed: $0.followed)
            }
        case .comments, .mentions, .notices:
            let records = feed == .comments ? comments : (feed == .mentions ? forwards : notices)
            guard let records else { throw APIError.invalidResponse }
            return records.map { $0.activity(in: feed) }
        }
    }
}
