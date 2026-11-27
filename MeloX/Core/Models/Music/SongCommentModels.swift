import Foundation

// Row-major positions in the NetEase desktop client's classic emote artwork atlas.
enum CommentEmoticons {
    static let names = [
        "大笑", "可爱", "憨笑", "色", "亲亲", "惊恐", "流泪", "亲",
        "呆", "哀伤", "呲牙", "吐舌", "撇嘴", "怒", "奸笑", "汗",
        "痛苦", "惶恐", "生病", "口罩", "大哭", "晕", "发怒", "开心",
        "鬼脸", "皱眉", "流感", "爱心", "心碎", "钟情", "星星", "生气",
        "便便", "强", "弱", "拜", "牵手", "跳舞", "禁止", "这边",
        "爱意", "示爱", "嘴唇", "狗", "猫", "猪", "兔子", "小鸡",
        "公鸡", "幽灵", "圣诞", "外星", "钻石", "礼物", "男孩", "女孩",
        "蛋糕", "18", "圈", "叉",
    ]
    static let tiles = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
}

struct CommentReplyTarget: Equatable {
    let rootID: Int64
    let comment: SongComment
    let focusRequest = UUID()
}

struct SongCommentUser: Decodable, Hashable, Identifiable {
    let id: Int
    let nickname: String
    let avatarURLString: String?

    var artworkURL: URL? {
        makeArtworkURL(from: avatarURLString, dimension: 96)
    }

    enum CodingKeys: String, CodingKey {
        case id = "userId"
        case nickname
        case avatarURLString = "avatarUrl"
    }

    init(id: Int, nickname: String, avatarURLString: String?) {
        self.id = id
        self.nickname = nickname
        self.avatarURLString = avatarURLString
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
            ?? L10n.string("ui.metadata.netease_user")
        avatarURLString = try container.decodeIfPresent(String.self, forKey: .avatarURLString)
    }
}

struct SongCommentReply: Decodable, Hashable {
    let id: Int64?
    let user: SongCommentUser?

    enum CodingKeys: String, CodingKey {
        case id = "beRepliedCommentId"
        case user
    }
}

struct SongCommentIPLocation: Decodable, Hashable {
    let location: String?
}

struct SongCommentFloorSummary: Decodable, Hashable {
    let replyCount: Int

    enum CodingKeys: String, CodingKey {
        case replyCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        replyCount = try container.decodeIfPresent(Int.self, forKey: .replyCount) ?? 0
    }
}

struct SongComment: Decodable, Hashable, Identifiable {
    let id: Int64
    let user: SongCommentUser
    let content: String
    let time: Double?
    let timeDescription: String?
    let likedCount: Int
    let isLiked: Bool
    let replies: [SongCommentReply]
    let ipLocation: SongCommentIPLocation?
    let parentCommentID: Int64
    let replyCount: Int

    var isRoot: Bool { parentCommentID == 0 && replies.isEmpty }

    init(postedID: Int64, user: SongCommentUser, content: String, time: Double, replyingTo target: CommentReplyTarget? = nil) {
        id = postedID
        self.user = user
        self.content = content
        self.time = time
        timeDescription = nil
        likedCount = 0
        isLiked = false
        replies = target.map { [SongCommentReply(id: $0.comment.id, user: $0.comment.user)] } ?? []
        ipLocation = nil
        parentCommentID = target?.rootID ?? 0
        replyCount = 0
    }

    func replyTarget(inFloor rootID: Int64, authors: [Int64: String]) -> String? {
        // In a floor, parentCommentId can identify the root even for a reply to a reply.
        let target = replies.first
        let targetID = target?.id ?? parentCommentID
        guard targetID > 0, targetID != rootID else { return nil }
        return target?.user?.nickname ?? authors[targetID] ?? L10n.string("ui.metadata.netease_user")
    }

    enum CodingKeys: String, CodingKey {
        case id = "commentId"
        case user, content, time
        case timeDescription = "timeStr"
        case likedCount
        case isLiked = "liked"
        case replies = "beReplied"
        case ipLocation
        case parentCommentID = "parentCommentId"
        case replyCount
        case floorSummary = "showFloorComment"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int64.self, forKey: .id) ?? 0
        user = try container.decode(SongCommentUser.self, forKey: .user)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        time = try container.decodeIfPresent(Double.self, forKey: .time)
        timeDescription = try container.decodeIfPresent(String.self, forKey: .timeDescription)
        likedCount = try container.decodeIfPresent(Int.self, forKey: .likedCount) ?? 0
        isLiked = try container.decodeIfPresent(Bool.self, forKey: .isLiked) ?? false
        replies = try container.decodeIfPresent([SongCommentReply].self, forKey: .replies) ?? []
        ipLocation = try container.decodeIfPresent(SongCommentIPLocation.self, forKey: .ipLocation)
        parentCommentID = try container.decodeIfPresent(Int64.self, forKey: .parentCommentID) ?? 0
        let summary = try container.decodeIfPresent(
            SongCommentFloorSummary.self,
            forKey: .floorSummary
        )
        replyCount = max(summary?.replyCount ?? 0, try container.decodeIfPresent(Int.self, forKey: .replyCount) ?? 0)
    }
}

struct SongCommentPostResponse: Decodable {
    struct Receipt: Decodable {
        let commentId: Int64?
        let user: SongCommentUser?
        let content: String?
        let time: Double?
    }

    let code: Int
    let message: String?
    let commentId: Int64?
    let comment: Receipt?

    func postedComment(content: String, author: SongCommentUser, sentAt: Date, replyingTo target: CommentReplyTarget? = nil) -> SongComment {
        let serverID = comment?.commentId ?? commentId ?? 0
        return SongComment(
            postedID: serverID > 0 ? serverID : Int64.random(in: Int64.min ... -1),
            user: comment?.user.flatMap { $0.id > 0 ? $0 : nil } ?? author,
            content: comment?.content ?? content,
            time: comment?.time ?? sentAt.timeIntervalSince1970 * 1000,
            replyingTo: target
        )
    }
}

struct SongCommentEdits {
    private(set) var posted: [SongComment] = []
    private(set) var deletedIDs: Set<Int64> = []

    mutating func add(_ comment: SongComment) {
        posted.removeAll { $0.id == comment.id }
        posted.insert(comment, at: 0)
    }

    mutating func delete(_ id: Int64) {
        deletedIDs.insert(id)
        posted.removeAll { $0.id == id }
    }

    mutating func reconcile(with roots: [SongComment]) {
        // A status-only write has a temporary ID until the first read that includes it.
        for root in roots {
            if let index = posted.firstIndex(where: { $0.id == root.id }) {
                posted.remove(at: index)
            } else if let index = posted.firstIndex(where: {
                $0.id < 0 && $0.user.id == root.user.id && $0.content == root.content
                    && $0.parentCommentID == root.parentCommentID && $0.replies.first?.id == root.replies.first?.id
                    && abs(($0.time ?? 0) - (root.time ?? 0)) < 15_000
            }) {
                posted.remove(at: index)
            }
        }
    }
}

struct SongCommentFloorResponse: Decodable {
    let code: Int
    let data: SongCommentFloorData
}

struct SongCommentFloorData: Decodable {
    let time: Int64?
    let bestComments: [SongComment]
    let comments: [SongComment]
    let totalCount: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case time, bestComments, comments, totalCount, hasMore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decodeIfPresent(Int64.self, forKey: .time)
        bestComments = try container.decodeIfPresent([SongComment].self, forKey: .bestComments) ?? []
        comments = try container.decodeIfPresent([SongComment].self, forKey: .comments) ?? []
        totalCount = try container.decodeIfPresent(Int.self, forKey: .totalCount) ?? comments.count
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }
}

enum SongCommentSort: Int {
    case popular = 2
    case latest = 3
}

struct SongCommentsResponse: Decodable {
    let code: Int
    let data: Page

    struct Page: Decodable {
        let comments: [SongComment]?
        let cursor: String?
        let hasMore: Bool
        let totalCount: Int
    }
}
