import Foundation

// MARK: - Book Model
struct Book: Codable, Identifiable {
    // 使用持久的备用ID，避免在没有 bookUrl 时因 UUID 变化导致列表状态丢失
    private let fallbackId = UUID().uuidString

    var id: String { bookUrl ?? fallbackId }
    let name: String?
    let author: String?
    let bookUrl: String?
    var origin: String?
    var originName: String?
    let coverUrl: String?
    let intro: String?
    let durChapterTitle: String?
    let durChapterIndex: Int?
    let durChapterPos: Double?
    let totalChapterNum: Int?
    let latestChapterTitle: String?
    let kind: String?
    let type: Int?
    let durChapterTime: Int64?  // 最后阅读时间（时间戳）

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
        if let url = coverUrl, !url.isEmpty {
            // 如果是相对路径，拼接完整URL
            if url.hasPrefix("baseurl/") {
                return APIService.shared.baseURL.replacingOccurrences(of: "/api/\(APIService.apiVersion)", with: "") + "/" + url
            }
            return url
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
