import Foundation

// MARK: - HttpTTS Model
struct HttpTTS: Codable, Identifiable {
    let id: String
    let userid: String?
    let name: String
    let url: String
    let contentType: String?
    let concurrentRate: String?
    let loginUrl: String?
    let loginUi: String?
    let header: String?
    let enabledCookieJar: Bool?
    let loginCheckJs: String?
    let lastUpdateTime: Int64?

    init(
        id: String,
        userid: String? = nil,
        name: String,
        url: String,
        contentType: String? = nil,
        concurrentRate: String? = nil,
        loginUrl: String? = nil,
        loginUi: String? = nil,
        header: String? = nil,
        enabledCookieJar: Bool? = nil,
        loginCheckJs: String? = nil,
        lastUpdateTime: Int64? = nil
    ) {
        self.id = id
        self.userid = userid
        self.name = name
        self.url = url
        self.contentType = contentType
        self.concurrentRate = concurrentRate
        self.loginUrl = loginUrl
        self.loginUi = loginUi
        self.header = header
        self.enabledCookieJar = enabledCookieJar
        self.loginCheckJs = loginCheckJs
        self.lastUpdateTime = lastUpdateTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringId = try? container.decode(String.self, forKey: .id) {
            id = stringId
        } else if let intId = try? container.decode(Int64.self, forKey: .id) {
            id = String(intId)
        } else if let doubleId = try? container.decode(Double.self, forKey: .id) {
            id = String(Int64(doubleId))
        } else {
            id = UUID().uuidString
        }
        userid = try? container.decode(String.self, forKey: .userid)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        url = (try? container.decode(String.self, forKey: .url)) ?? ""
        contentType = try? container.decode(String.self, forKey: .contentType)
        concurrentRate = try? container.decode(String.self, forKey: .concurrentRate)
        loginUrl = try? container.decode(String.self, forKey: .loginUrl)
        loginUi = try? container.decode(String.self, forKey: .loginUi)
        header = try? container.decode(String.self, forKey: .header)
        if let boolValue = try? container.decode(Bool.self, forKey: .enabledCookieJar) {
            enabledCookieJar = boolValue
        } else if let intValue = try? container.decode(Int.self, forKey: .enabledCookieJar) {
            enabledCookieJar = intValue != 0
        } else if let stringValue = try? container.decode(String.self, forKey: .enabledCookieJar) {
            enabledCookieJar = (stringValue as NSString).boolValue
        } else {
            enabledCookieJar = nil
        }
        loginCheckJs = try? container.decode(String.self, forKey: .loginCheckJs)
        lastUpdateTime = try? container.decode(Int64.self, forKey: .lastUpdateTime)
    }
}

struct ReaderTtsRequest: Encodable {
    let text: String
    let voice: String
    let pitch: String
    let rate: String
    let accessToken: String
    let type: String
    let base64: String
}
