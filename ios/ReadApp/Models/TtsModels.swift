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
}
