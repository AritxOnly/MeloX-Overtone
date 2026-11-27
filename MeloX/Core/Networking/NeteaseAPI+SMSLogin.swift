import Foundation

private struct SMSLoginResponse: Decodable {
    let code: Int
    let message: String?
    let msg: String?

    func check() throws {
        guard code == 200 else {
            throw APIError.server(statusCode: code, message: message ?? msg ?? "")
        }
    }
}

extension NeteaseAPI {
    func sendLoginCode(phone: String, countryCode: String) async throws {
        let response: SMSLoginResponse = try await client.weapi(
            "/api/sms/captcha/sent",
            data: ["cellphone": phone, "ctcode": countryCode, "secrete": "music_middleuser_pclogin"],
            retryEmptyResponse: false
        )
        try response.check()
    }

    func signIn(phone: String, countryCode: String, code: String) async throws -> String {
        var cookies: [HTTPCookie] = []
        let response: SMSLoginResponse = try await client.weapi(
            "/api/w/login/cellphone",
            data: [
                "phone": phone, "countrycode": countryCode, "captcha": code,
                "type": "1", "https": "true", "remember": "true"
            ],
            retryEmptyResponse: false,
            receiveCookies: { cookies = $0 }
        )
        try response.check()
        guard let header = musicSessionHeader(from: cookies) else { throw APIError.invalidResponse }
        return header
    }
}

// Import only credentials that apply to the music site, including parent-domain cookies.
func musicSessionHeader(from cookies: [HTTPCookie]) -> String? {
    var values: [String: String] = [:]
    for cookie in cookies.sorted(by: { $0.domain.count < $1.domain.count }) {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard domain == "163.com" || domain == "music.163.com",
              cookie.name == "MUSIC_U" || cookie.name == "__csrf",
              cookie.expiresDate.map({ $0 > Date() }) ?? true,
              !cookie.value.isEmpty else { continue }
        values[cookie.name] = cookie.value
    }
    guard values["MUSIC_U"] != nil else { return nil }
    return ["MUSIC_U", "__csrf"].compactMap { name in
        values[name].map { "\(name)=\($0)" }
    }.joined(separator: "; ")
}
