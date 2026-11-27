import Foundation

enum QRLoginStatus {
    case waiting, scanned, expired
    case authorized(cookie: String)
}

extension NeteaseAPI {
    func loginQRCodeURL() async throws -> (key: String, url: URL) {
        struct Response: Decodable {
            struct Payload: Decodable { let unikey: String? }
            let code: Int
            let unikey: String?
            let data: Payload?
        }
        let response: Response = try await client.eapi("/api/login/qrcode/unikey", data: ["type": 3])
        guard response.code == 200, let key = response.unikey ?? response.data?.unikey, !key.isEmpty
        else { throw APIError.invalidResponse }
        var link = URLComponents()
        link.scheme = "https"
        link.host = "music.163.com"
        link.path = "/login"
        link.queryItems = [URLQueryItem(name: "codekey", value: key)]
        guard let url = link.url else { throw APIError.invalidResponse }
        return (key, url)
    }

    func qrLoginStatus(key: String) async throws -> QRLoginStatus {
        struct Response: Decodable {
            let code: Int
            let cookie: String?
        }
        var cookies: [HTTPCookie] = []
        let response: Response = try await client.eapi(
            "/api/login/qrcode/client/login", data: ["key": key, "type": 3],
            receiveCookies: { cookies = $0 }
        )
        switch response.code {
        case 800: return .expired
        case 801: return .waiting
        case 802: return .scanned
        case 803:
            var values: [String: String] = [:]
            for part in (response.cookie ?? "").components(separatedBy: ";") {
                let pair = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
                if pair.count == 2 { values[String(pair[0])] = String(pair[1]) }
            }
            for cookie in cookies where cookie.expiresDate.map({ $0 > Date() }) ?? true {
                values[cookie.name] = cookie.value
            }
            guard let token = values["MUSIC_U"], !token.isEmpty else { throw APIError.invalidResponse }
            let header = ["MUSIC_U", "__csrf"].compactMap { name in
                values[name].map { "\(name)=\($0)" }
            }.joined(separator: "; ")
            return .authorized(cookie: header)
        default: throw APIError.invalidResponse
        }
    }
}
