import Foundation

struct FullBookSource: Codable, Identifiable {
    var id: String { bookSourceUrl }
    var bookSourceName: String = ""
    var bookSourceGroup: String?
    var bookSourceUrl: String = ""
    var bookSourceType: Int = 0
    var bookUrlPattern: String?
    var customOrder: Int = 0
    var enabled: Bool = true
    var enabledExplore: Bool = true
    var concurrentRate: String?
    var header: String?
    var loginUrl: String?
    var loginCheckJs: String?
    var lastUpdateTime: Long = 0
    var weight: Int = 0
    var exploreUrl: String?
    var ruleExplore: ExploreRule?
    var searchUrl: String?
    var ruleSearch: SearchRule?
    var ruleBookInfo: BookInfoRule?
    var ruleToc: TocRule?
    var ruleContent: ContentRule?
    var bookSourceComment: String?
    var respondTime: Long = 180000
    var enabledCookieJar: Bool? = false
}

struct SearchRule: Codable {
    var bookList: String?
    var name: String?
    var author: String?
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var updateTime: String?
    var bookUrl: String?
    var coverUrl: String?
    var wordCount: String?
}

struct ExploreRule: Codable {
    var bookList: String?
    var name: String?
    var author: String?
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var updateTime: String?
    var bookUrl: String?
    var coverUrl: String?
    var wordCount: String?
}

struct BookInfoRule: Codable {
    var name: String?
    var author: String?
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var updateTime: String?
    var coverUrl: String?
    var tocUrl: String?
    var wordCount: String?
}

struct TocRule: Codable {
    var chapterList: String?
    var chapterName: String?
    var chapterUrl: String?
    var isVolume: String?
    var isVip: String?
    var updateTime: String?
    var nextTocUrl: String?
}

struct ContentRule: Codable {
    var content: String?
    var nextContentUrl: String?
    var sourceRegex: String?
    var replaceRegex: String?
    var imageDecode: String?
}
