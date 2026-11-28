import Foundation

@main
struct MusicDeepLinkChecks {
    static func main() {
        func parse(_ raw: String) -> MusicDeepLink? {
            URL(string: raw).flatMap(MusicDeepLink.init)
        }

        func expects(
            _ raw: String,
            _ resource: MusicDeepLink.Resource?,
            _ id: Int?
        ) -> Bool {
            let link = parse(raw)
            return link?.resource == resource && link?.id == id
        }

        precondition(expects("overtone://song/1234567", .song, 1234567))
        precondition(expects("overtone://playlist/9876", .playlist, 9876))
        precondition(expects("overtone://album/42", .album, 42))
        precondition(expects("overtone://artist/7", .artist, 7))
        precondition(expects("OVERTONE://SONG/9", .song, 9))
        precondition(expects("overtone://song/123/", .song, 123))
        precondition(expects("overtone://song/0", nil, nil))
        precondition(expects("overtone://song/-3", nil, nil))
        precondition(expects("overtone://song/abc", nil, nil))
        precondition(expects("overtone://track/1", nil, nil))
        precondition(expects("overtone://song/1/extra", nil, nil))
        precondition(expects("overtone://", nil, nil))
        precondition(expects("melox://song/1", nil, nil))
        precondition(expects("https://music.163.com/song/1", nil, nil))
        print("Music deep link: 14 checks passed")
    }
}
