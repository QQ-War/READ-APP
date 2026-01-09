import Foundation
import Combine
import UIKit

struct ChapterContentFetchPolicy {
    let useDiskCache: Bool
    let useMemoryCache: Bool
    let saveToCache: Bool

    static let standard = ChapterContentFetchPolicy(useDiskCache: true, useMemoryCache: true, saveToCache: true)
    static let refresh = ChapterContentFetchPolicy(useDiskCache: false, useMemoryCache: false, saveToCache: true)
}

class APIService: ObservableObject {
    static let shared = APIService()
    static let apiVersion = 5
    
    @Published var books: [Book] = []
    @Published var availableSources: [BookSource] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let client: APIClient
    private let authService: AuthService
    private let booksService: BooksService
    private let ttsService: TTSService
    private let replaceRuleService: ReplaceRuleService
    private let bookSourceService: BookSourceService
    private let cacheManagementService: CacheManagementService
    private let chapterCache: ChapterContentCache
    
    // ... rest of property declarations ...
    
    var baseURL: String {
        client.baseURL
    }
    
    var publicBaseURL: String? {
        client.publicBaseURL
    }
    
    private var accessToken: String {
        client.accessToken
    }
    
    private init() {
        let client = APIClient.shared
        self.client = client
        self.authService = AuthService(client: client)
        self.booksService = BooksService(client: client)
        self.ttsService = TTSService(client: client)
        self.replaceRuleService = ReplaceRuleService(client: client)
        self.bookSourceService = BookSourceService(client: client)
        self.cacheManagementService = CacheManagementService(client: client)
        self.chapterCache = ChapterContentCache(maxEntries: 50)
    }

    // MARK: - 登录
    func login(username: String, password: String) async throws -> String {
        try await authService.login(username: username, password: password)
    }
    
    func changePassword(oldPassword: String, newPassword: String) async throws {
        try await authService.changePassword(oldPassword: oldPassword, newPassword: newPassword)
    }

    // MARK: - 获取书架列表
    func fetchBookshelf() async throws {
        let books = try await booksService.fetchBookshelf()
        await MainActor.run {
            self.books = books
        }
    }
    
    // MARK: - 获取章节列表
    func fetchChapterList(bookUrl: String, bookSourceUrl: String?) async throws -> [BookChapter] {
        try await booksService.fetchChapterList(bookUrl: bookUrl, bookSourceUrl: bookSourceUrl)
    }
    
    // MARK: - 获取章节内容
    func fetchChapterContent(bookUrl: String, bookSourceUrl: String?, index: Int, contentType: Int = 0, cachePolicy: ChapterContentFetchPolicy = .standard) async throws -> String {
        // 1. 优先尝试从本地磁盘缓存读取
        if cachePolicy.useDiskCache, let cachedContent = LocalCacheManager.shared.loadChapter(bookUrl: bookUrl, index: index) {
            return cachedContent
        }
        
        // 2. 尝试从内存缓存读取
        let cacheKey = "\(bookUrl)_\(index)_\(contentType)"
        if cachePolicy.useMemoryCache, let cachedContent = await chapterCache.value(for: cacheKey) {
            return cachedContent
        }
        
        // 3. 网络请求
        var queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken),
            URLQueryItem(name: "url", value: bookUrl),
            URLQueryItem(name: "index", value: "\(index)"),
            URLQueryItem(name: "type", value: "\(contentType)")
        ]
        if let bookSourceUrl = bookSourceUrl {
            queryItems.append(URLQueryItem(name: "bookSourceUrl", value: bookSourceUrl))
        }
        
        let (data, httpResponse) = try await client.requestWithFailback(endpoint: ApiEndpoints.getBookContent, queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器错误"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if apiResponse.isSuccess, let content = apiResponse.data {
            if cachePolicy.saveToCache {
                await chapterCache.insert(content, for: cacheKey)
                // 同步存入磁盘缓存
                LocalCacheManager.shared.saveChapter(bookUrl: bookUrl, index: index, content: content)
            }
            return content
        } else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "获取章节内容失败"])
        }
    }
    
    // MARK: - 保存阅读进度
    func saveBookProgress(bookUrl: String, index: Int, pos: Double, title: String?) async throws {
        try await booksService.saveBookProgress(bookUrl: bookUrl, index: index, pos: pos, title: title)
    }
    
    // MARK: - TTS 相关
    func fetchTTSList() async throws -> [HttpTTS] {
        try await ttsService.fetchTTSList()
    }
    
    func buildTTSAudioURL(ttsId: String, text: String, speechRate: Double) -> URL? {
        ttsService.buildTTSAudioURL(ttsId: ttsId, text: text, speechRate: speechRate)
    }

    // MARK: - TTS CRUD
    func saveTTS(tts: HttpTTS) async throws {
        try await ttsService.saveTTS(tts: tts)
    }

    func deleteTTS(id: String) async throws {
        try await ttsService.deleteTTS(id: id)
    }
    
    func saveTTSBatch(jsonContent: String) async throws {
        try await ttsService.saveTTSBatch(jsonContent: jsonContent)
    }
    
    // MARK: - 其他
    func clearLocalCache() {
        Task { await chapterCache.removeAll() }
    }

    // MARK: - 替换净化规则
    
    func fetchReplaceRules() async throws -> [ReplaceRule] {
        try await replaceRuleService.fetchReplaceRules()
    }
    
    func saveReplaceRule(rule: ReplaceRule) async throws {
        try await replaceRuleService.saveReplaceRule(rule: rule)
    }
    
    func deleteReplaceRule(rule: ReplaceRule) async throws {
        try await replaceRuleService.deleteReplaceRule(rule: rule)
    }
    
    func toggleReplaceRule(rule: ReplaceRule, isEnabled: Bool) async throws {
        try await replaceRuleService.toggleReplaceRule(rule: rule, isEnabled: isEnabled)
    }
    
    func saveReplaceRules(jsonContent: String) async throws {
        try await replaceRuleService.saveReplaceRules(jsonContent: jsonContent)
    }
    
    // MARK: - Book Import
    func importBook(from url: URL) async throws {
        try await booksService.importBook(from: url)
    }

    // MARK: - Book Sources
    func fetchBookSources() async throws -> [BookSource] {
        let sources = try await bookSourceService.fetchBookSources()
        await MainActor.run {
            self.availableSources = sources
        }
        return sources
    }
    
    func saveBookSource(jsonContent: String) async throws {
        try await bookSourceService.saveBookSource(jsonContent: jsonContent)
    }

    func deleteBookSource(id: String) async throws {
        try await bookSourceService.deleteBookSource(id: id)
    }

    func toggleBookSource(id: String, isEnabled: Bool) async throws {
        try await bookSourceService.toggleBookSource(id: id, isEnabled: isEnabled)
    }
    
    func getBookSourceDetail(id: String) async throws -> String {
        try await bookSourceService.getBookSourceDetail(id: id)
    }
    
    // MARK: - Book Search
    func searchBook(keyword: String, bookSourceUrl: String, page: Int = 1) async throws -> [Book] {
        try await booksService.searchBook(keyword: keyword, bookSourceUrl: bookSourceUrl, page: page)
    }
    
    // MARK: - Explore / Discovery
    func fetchExploreKinds(bookSourceUrl: String) async throws -> [BookSource.ExploreKind] {
        try await booksService.fetchExploreKinds(bookSourceUrl: bookSourceUrl)
    }
    
    func exploreBook(bookSourceUrl: String, ruleFindUrl: String, page: Int = 1) async throws -> [Book] {
        try await booksService.exploreBook(bookSourceUrl: bookSourceUrl, ruleFindUrl: ruleFindUrl, page: page)
    }
    
    // MARK: - Save Book to Bookshelf
    func saveBook(book: Book, useReplaceRule: Int = 0) async throws {
        try await booksService.saveBook(book: book, useReplaceRule: useReplaceRule)
    }
    
    // MARK: - Change Book Source
    func changeBookSource(oldBookUrl: String, newBookUrl: String, newBookSourceUrl: String) async throws {
        try await booksService.changeBookSource(oldBookUrl: oldBookUrl, newBookUrl: newBookUrl, newBookSourceUrl: newBookSourceUrl)
    }

    // MARK: - Delete Book from Bookshelf
    func deleteBook(bookUrl: String) async throws {
        try await booksService.deleteBook(bookUrl: bookUrl)
    }
    
    // MARK: - Cache Management
    func clearAllRemoteCache() async throws {
        try await cacheManagementService.clearAllRemoteCache()
    }
    
    // MARK: - Default TTS
    func fetchDefaultTTS() async throws -> String {
        try await ttsService.fetchDefaultTTS()
    }
}
