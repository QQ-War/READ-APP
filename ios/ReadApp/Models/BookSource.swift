import Foundation

struct BookSource: Codable, Identifiable {
    var id: String { bookSourceUrl }
    let bookSourceName: String
    let bookSourceGroup: String?
    let bookSourceUrl: String
    let bookSourceType: Int?
    let customOrder: Int?
    let enabled: Bool
    let enabledExplore: Bool?
    let lastUpdateTime: Int64?
    let weight: Int?
    let bookSourceComment: String?
    let respondTime: Int64?
    
    enum CodingKeys: String, CodingKey {
        case bookSourceName
        case bookSourceGroup
        case bookSourceUrl
        case bookSourceType
        case customOrder
        case enabled
        case enabledExplore
        case lastUpdateTime
        case weight
        case bookSourceComment
        case respondTime
    }
}

// For preview and testing purposes
extension BookSource {
    static func mock() -> BookSource {
        return BookSource(
            bookSourceName: "示例书源",
            bookSourceGroup: "默认分组",
            bookSourceUrl: "https://example.com/source/1",
            bookSourceType: 0,
            customOrder: 0,
            enabled: true,
            enabledExplore: true,
            lastUpdateTime: Date().timeIntervalSince1970.toInt64(),
            weight: 100,
            bookSourceComment: "这是一个用于测试的示例书源。",
            respondTime: 120
        )
    }
    
    static func mocks() -> [BookSource] {
        return [
            BookSource(
                bookSourceName: "测试书源A",
                bookSourceGroup: "分组1",
                bookSourceUrl: "https://example.com/source/a",
                bookSourceType: 0,
                customOrder: 1,
                enabled: true,
                enabledExplore: true,
                lastUpdateTime: Date().timeIntervalSince1970.toInt64(),
                weight: 10,
                bookSourceComment: "Comment A",
                respondTime: 150
            ),
            BookSource(
                bookSourceName: "禁用的书源B",
                bookSourceGroup: "分组2",
                bookSourceUrl: "https://example.com/source/b",
                bookSourceType: 0,
                customOrder: 2,
                enabled: false,
                enabledExplore: true,
                lastUpdateTime: Date().timeIntervalSince1970.toInt64() - 10000,
                weight: 20,
                bookSourceComment: "Comment B",
                respondTime: 300
            ),
            BookSource(
                bookSourceName: "音频书源C",
                bookSourceGroup: "分组1",
                bookSourceUrl: "https://example.com/source/c",
                bookSourceType: 1,
                customOrder: 3,
                enabled: true,
                enabledExplore: false,
                lastUpdateTime: Date().timeIntervalSince1970.toInt64() - 20000,
                weight: 30,
                bookSourceComment: "Comment C",
                respondTime: 80
            )
        ]
    }
}

extension Double {
    func toInt64() -> Int64 {
        return Int64(self)
    }
}
