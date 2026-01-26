import Foundation

// MARK: - Book Model
struct Book: Codable, Identifiable {
    // 使用持久的备用ID，避免在没有 bookUrl 时因 UUID 变化导致列表状态丢失
    private let fallbackId = UUID().uuidString

    var id: String { bookUrl ?? fallbackId }
    var name: String?
    var author: String?
    var bookUrl: String?
    var origin: String?
    var originName: String?
    var coverUrl: String?
    var intro: String?
    var durChapterTitle: String?
    var durChapterIndex: Int?
    var durChapterPos: Double?
    var totalChapterNum: Int?
    var latestChapterTitle: String?
    var kind: String?
    var type: Int?
    var durChapterTime: Int64?  // 最后阅读时间（时间戳）

    var sourceDisplayName: String? // For global search results

    enum CodingKeys: String, CodingKey {
        case name
        case author
        case bookUrl
        case origin
        case originName
        case coverUrl
        case intro
        case durChapterTitle
        case durChapterIndex
        case durChapterPos
        case totalChapterNum
        case latestChapterTitle
        case kind
        case type
        case durChapterTime
    }

    var displayCoverUrl: String? {
        if let url = coverUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty,
           url.lowercased() != "null", url.lowercased() != "nil", url.lowercased() != "undefined" {
            // 如果是相对路径，拼接完整URL
            if url.hasPrefix("baseurl/") {
                let baseURL = ApiBackendResolver.stripApiBasePath(APIService.shared.baseURL)
                return baseURL + "/" + url
            }
            if url.hasPrefix("/") {
                let baseURL = ApiBackendResolver.stripApiBasePath(APIService.shared.baseURL)
                return baseURL + url
            }
            if url.hasPrefix("assets/") || url.hasPrefix("book-assets/") {
                let baseURL = ApiBackendResolver.stripApiBasePath(APIService.shared.baseURL)
                return baseURL + "/" + url
            }
            return url
        }
        if let bookUrl = bookUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bookUrl.isEmpty,
           bookUrl.lowercased().hasSuffix(".pdf"),
           UserPreferences.shared.apiBackend == .read {
            let baseURL = ApiBackendResolver.stripApiBasePath(APIService.shared.baseURL)
            let decodedPath = bookUrl.removingPercentEncoding ?? bookUrl
            var components = URLComponents(string: "\(baseURL)/api/v\(APIService.apiVersion)/pdfImage")
            components?.queryItems = [
                URLQueryItem(name: "path", value: decodedPath),
                URLQueryItem(name: "page", value: "0")
            ]
            return components?.url?.absoluteString
        }
        return nil
    }
}

// MARK: - Chapter Model
struct BookChapter: Codable, Identifiable {
    var id: String { url }
    let title: String
    let url: String
    let index: Int
    let isVolume: Bool?
    let isPay: Bool?
}
