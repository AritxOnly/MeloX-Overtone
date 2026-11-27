// Run with swiftc -parse-as-library MeloX/Core/Models/Music/SongCommentModels.swift
// and this file, then execute the resulting binary.
import Foundation

// The production model also exposes avatar URLs and localized deleted-user labels.
func makeArtworkURL(from: String?, dimension: Int) -> URL? { nil }
enum L10n { static func string(_ key: String) -> String { key } }

@main
struct SongCommentThreadChecks {
    static func main() throws {
        let payload = #"""
        {
          "code": 200,
          "data": {
            "time": 18, "hasMore": true,
            "comments": [
              {"commentId":11,"parentCommentId":0,"user":{"nickname":"A"},"showFloorComment":{"replyCount":3}},
              {"commentId":12,"parentCommentId":11,"user":{"nickname":"B"},"beReplied":[{"beRepliedCommentId":11,"user":{"nickname":"A"}}]},
              {"commentId":13,"parentCommentId":11,"user":{"nickname":"A"},"beReplied":[{"beRepliedCommentId":12,"user":{"nickname":"B"}}]},
              {"commentId":14,"parentCommentId":11,"user":{"nickname":"C"},"beReplied":[{"beRepliedCommentId":13}]}
            ]
          }
        }
        """#
        let page = try JSONDecoder().decode(SongCommentFloorResponse.self, from: Data(payload.utf8)).data
        let rows = page.comments
        let names = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.user.nickname) })
        precondition(rows.filter(\.isRoot).map(\.id) == [11])
        precondition(rows.map(\.replyCount) == [3, 0, 0, 0])
        precondition(rows[1].replyTarget(inFloor: 11, authors: names) == nil)
        precondition(rows[2].replyTarget(inFloor: 11, authors: [:]) == "B")
        precondition(rows[3].replyTarget(inFloor: 11, authors: names) == "A")
        let original = "[西西流汗][西西流汗]\n[西西心动][多多调皮]❤️ [副歌] [新表情] [未闭合"
        let data = try JSONSerialization.data(withJSONObject: ["content": original, "user": [:]])
        let comment = try JSONDecoder().decode(SongComment.self, from: data)
        precondition(comment.content == original)
        let author = SongCommentUser(id: 5, nickname: "A", avatarURLString: nil)
        let sentAt = Date(timeIntervalSince1970: 100)
        let receipt = try JSONDecoder().decode(SongCommentPostResponse.self, from: Data(
            #"{"code":200,"comment":{"commentId":12,"content":"[西西心动]"}}"#.utf8
        ))
        let posted = receipt.postedComment(content: original, author: author, sentAt: sentAt)
        var edits = SongCommentEdits()
        edits.add(posted)
        edits.reconcile(with: [])
        precondition(edits.posted.map(\.content) == ["[西西心动]"])
        precondition(CommentEmoticons.tiles["可爱"] != nil && CommentEmoticons.tiles["西西心动"] == nil)
        let target = CommentReplyTarget(rootID: 11, comment: rows[2])
        let nested = receipt.postedComment(content: original, author: author, sentAt: sentAt, replyingTo: target)
        precondition(!nested.isRoot && nested.parentCommentID == 11)
        precondition(nested.replyTarget(inFloor: 11, authors: [:]) == rows[2].user.nickname)
        edits.reconcile(with: [posted])
        precondition(edits.posted.isEmpty)
        edits.delete(posted.id)
        precondition(edits.deletedIDs == [12])

        let status = try JSONDecoder().decode(SongCommentPostResponse.self, from: Data(#"{"code":200}"#.utf8))
        let temporary = status.postedComment(content: "Hello", author: author, sentAt: sentAt)
        precondition(temporary.id < 0)
        edits.add(temporary)
        edits.reconcile(with: [SongComment(postedID: 20, user: author, content: "Hello", time: 50_000)])
        precondition(edits.posted == [temporary])
        edits.reconcile(with: [SongComment(postedID: 22, user: author, content: "Hello", time: 100_100)])
        precondition(edits.posted.isEmpty)
        print("Passed comment threads, emoticons, post receipts, reconciliation and deletion checks")
    }
}
