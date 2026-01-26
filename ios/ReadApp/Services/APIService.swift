import Foundation
import UIKit

struct ChapterContentFetchPolicy {
    let useDiskCache: Bool
    let useMemoryCache: Bool
    let saveToCache: Bool

    static let standard = ChapterContentFetchPolicy(useDiskCache: true, useMemoryCache: true, saveToCache: true)
    static let refresh = ChapterContentFetchPolicy(useDiskCache: false, useMemoryCache: false, saveToCache: true)
}

class APIService {
    static let shared = APIService()
    static let apiVersion = 5

    private let invalidCacheMarkers = ["加载失败:", "点击屏幕中心呼出菜单", "服务器错误", "获取章节内容失败"]
    
    private let client: APIClient
    private var ttsEngineCache: [String: HttpTTS] = [:]
    private let ttsCacheQueue = DispatchQueue(label: "com.readapp.tts.cache")
    private let authService: AuthService
    private let booksService: BooksService
    private let ttsService: TTSService
    private let replaceRuleService: ReplaceRuleService
    private let bookSourceService: BookSourceService
    private let cacheManagementService: CacheManagementService
    private let chapterCache: ChapterContentCache
    private let rssService: RssService
    
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
        self.rssService = RssService(client: client)
        
    }

    // MARK: - 登录
    func login(username: String, password: String) async throws -> String {
        try await authService.login(username: username, password: password)
    }
    
    func changePassword(oldPassword: String, newPassword: String) async throws {
        try await authService.changePassword(oldPassword: oldPassword, newPassword: newPassword)
    }

    // MARK: - 获取书架列表
    func fetchBookshelf() async throws -> [Book] {
        try await withTimeout(seconds: 5) { [weak self] in
            guard let self = self else { return [] }
            return try await self.booksService.fetchBookshelf()
        }
    }
    
    // MARK: - 获取章节列表
    func fetchChapterList(bookUrl: String, bookSourceUrl: String?) async throws -> [BookChapter] {
        // 1. 优先从本地缓存加载
        let cached = LocalCacheManager.shared.loadChapterList(bookUrl: bookUrl)
        
        // 如果有缓存，我们直接返回它，让阅读器先跑起来
        if let cachedList = cached, !cachedList.isEmpty {
            // 在后台静默更新目录，不阻塞主流程
            Task {
                try? await withTimeout(seconds: 5) { [weak self] in
                    guard let self = self else { return }
                    let freshList = try await self.booksService.fetchChapterList(bookUrl: bookUrl, bookSourceUrl: bookSourceUrl)
                    LocalCacheManager.shared.saveChapterList(bookUrl: bookUrl, chapters: freshList)
                }
            }
            return cachedList
        }
        
        // 2. 如果没有缓存，则执行带超时的强制加载
        return try await withTimeout(seconds: 5) { [weak self] in
            guard let self = self else { throw NSError(domain: "APIService", code: -1) }
            let list = try await self.booksService.fetchChapterList(bookUrl: bookUrl, bookSourceUrl: bookSourceUrl)
            LocalCacheManager.shared.saveChapterList(bookUrl: bookUrl, chapters: list)
            return list
        }
    }
    
    // MARK: - 获取章节内容
    func fetchChapterContent(bookUrl: String, bookSourceUrl: String?, index: Int, contentType: Int = 0, cachePolicy: ChapterContentFetchPolicy = .standard) async throws -> String {
        // 1. 优先尝试从本地磁盘缓存读取
        if cachePolicy.useDiskCache, let cachedContent = LocalCacheManager.shared.loadChapter(bookUrl: bookUrl, index: index) {
            if shouldUseCachedContent(cachedContent) {
                return cachedContent
            } else {
            }
        }
        
        return try await withTimeout(seconds: 5) { [weak self] in
            guard let self = self else { throw NSError(domain: "APIService", code: -1) }
            
            let cacheKey = "\(bookUrl)_\(index)_\(contentType)"
            if cachePolicy.useMemoryCache, let cachedContent = await self.chapterCache.value(for: cacheKey) {
                if shouldUseCachedContent(cachedContent) {
                    return cachedContent
                } else {
                }
            }

            var queryItems = [
                URLQueryItem(name: "accessToken", value: self.accessToken),
                URLQueryItem(name: "url", value: bookUrl),
                URLQueryItem(name: "index", value: "\(index)"),
                URLQueryItem(name: "type", value: "\(contentType)")
            ]
            if let bookSourceUrl = bookSourceUrl {
                queryItems.append(URLQueryItem(name: "bookSourceUrl", value: bookSourceUrl))
            }
            
            let endpoint = self.client.backend == .reader ? ApiEndpointsReader.getBookContent : ApiEndpoints.getBookContent
            let (data, httpResponse) = try await self.client.requestWithFailback(endpoint: endpoint, queryItems: queryItems)
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器错误"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
            if apiResponse.isSuccess, let content = apiResponse.data {
                let resolvedContent = try await resolveReaderLocalContentIfNeeded(content)
                if cachePolicy.saveToCache {
                    if shouldUseCachedContent(resolvedContent) {
                        await self.chapterCache.insert(resolvedContent, for: cacheKey)
                        let shouldCache = (contentType == 2) ? UserPreferences.shared.isMangaAutoCacheEnabled : UserPreferences.shared.isTextAutoCacheEnabled
                        if shouldCache {
                            LocalCacheManager.shared.saveChapter(bookUrl: bookUrl, index: index, content: resolvedContent)
                        }
                    } else {
                    }
                }
                return resolvedContent
            } else {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "获取章节内容失败"])
            }
        }
    }

    private func shouldUseCachedContent(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        for marker in invalidCacheMarkers {
            if trimmed.contains(marker) { return false }
        }
        return true
    }

    private func resolveReaderLocalContentIfNeeded(_ content: String) async throws -> String {
        guard client.backend == .reader else { return content }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return content }
        if trimmed.contains("<") { return content }
        let looksLikeAssetPath = trimmed.contains("/book-assets/")
        let looksLikeHtmlPath = trimmed.localizedCaseInsensitiveContains(".xhtml") || trimmed.localizedCaseInsensitiveContains(".html")
        if !looksLikeAssetPath && !looksLikeHtmlPath { return content }

        let base = ApiBackendResolver.stripApiBasePath(client.baseURL)
        let publicBase = client.publicBaseURL.map { ApiBackendResolver.stripApiBasePath($0) }
        var normalized = trimmed
        if normalized.hasPrefix("__API_ROOT__") {
            normalized = normalized.replacingOccurrences(of: "__API_ROOT__", with: "")
        }
        let path = normalized.hasPrefix("/") ? normalized : "/\(normalized)"

        var candidates: [String] = []
        if normalized.contains("://") {
            candidates.append(buildEncodedAbsoluteURL(normalized))
            if let publicBase = publicBase, normalized.hasPrefix(base) {
                let replaced = normalized.replacingOccurrences(of: base, with: publicBase)
                candidates.append(buildEncodedAbsoluteURL(replaced))
            }
        } else {
            candidates.append(base + customURLEncodePath(path))
            if let publicBase = publicBase {
                candidates.append(publicBase + customURLEncodePath(path))
            }
        }

        for urlString in candidates {
            if let text = await fetchTextContent(urlString: urlString) {
                return text
            }
        }
        return content
    }

    private func buildEncodedAbsoluteURL(_ urlString: String) -> String {
        guard let schemeRange = urlString.range(of: "://") else {
            return customURLEncodePath(urlString)
        }
        let scheme = urlString[..<schemeRange.upperBound]
        let rest = urlString[schemeRange.upperBound...]
        if let slashIndex = rest.firstIndex(of: "/") {
            let host = rest[..<slashIndex]
            let path = rest[slashIndex...]
            return "\(scheme)\(host)\(customURLEncodePath(String(path)))"
        }
        return urlString
    }

    private func customURLEncodePath(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)
        let allowed: Set<Unicode.Scalar> = {
            let symbols = "-._~,!*'()/?&=:@"
            var set = Set<Unicode.Scalar>()
            for scalar in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".unicodeScalars {
                set.insert(scalar)
            }
            for scalar in symbols.unicodeScalars {
                set.insert(scalar)
            }
            return set
        }()
        for scalar in input.unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                for byte in String(scalar).utf8 {
                    result += String(format: "%%%02X", byte)
                }
            }
        }
        return result
    }

    private func fetchTextContent(urlString: String) async -> String? {
        let url: URL?
        if let direct = URL(string: urlString) {
            url = direct
        } else if let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) {
            url = URL(string: encoded)
        } else {
            url = nil
        }
        guard let url = url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "APIService", code: 408, userInfo: [NSLocalizedDescriptionKey: "加载超时，请检查网络后重试"])
            }
            // 使用安全解包替代强制解包
            guard let result = try await group.next() else {
                throw NSError(domain: "APIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "请求任务异常中断"])
            }
            group.cancelAll()
            return result
        }
    }
    
    // MARK: - 保存阅读进度
    func saveBookProgress(bookUrl: String, index: Int, pos: Double, title: String?) async throws {
        try await booksService.saveBookProgress(bookUrl: bookUrl, index: index, pos: pos, title: title)
    }
    
    // MARK: - TTS 相关
    func fetchTTSList() async throws -> [HttpTTS] {
        let list = try await ttsService.fetchTTSList()
        updateTtsCache(with: list)
        return list
    }

    private func updateTtsCache(with list: [HttpTTS]) {
        ttsCacheQueue.sync {
            // 使用 uniquingKeysWith 处理重复 ID，防止崩溃
            ttsEngineCache = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    private func cachedTtsEngine(id: String) -> HttpTTS? {
        ttsCacheQueue.sync {
            ttsEngineCache[id]
        }
    }

    private func ensureTtsEngine(id: String) async throws -> HttpTTS? {
        if let cached = cachedTtsEngine(id: id) {
            return cached
        }
        let list = try await ttsService.fetchTTSList()
        updateTtsCache(with: list)
        return list.first { $0.id == id }
    }

    private func formatReaderSpeechRate(_ rate: Double) -> String {
        let normalized = max(0.2, min(rate / 100.0, 3.0))
        return String(format: "%.2f", normalized)
    }

    func fetchReaderTtsAudio(ttsId: String, text: String, speechRate: Double) async throws -> Data {
        guard let engine = try await ensureTtsEngine(id: ttsId), !engine.name.isEmpty else {
            throw NSError(domain: "APIService", code: 404, userInfo: [NSLocalizedDescriptionKey: "找不到指定的TTS引擎"])
        }
        let requestBody = ReaderTtsRequest(
            text: text,
            voice: engine.name,
            pitch: "1",
            rate: formatReaderSpeechRate(speechRate),
            accessToken: accessToken,
            type: "httpTTS",
            base64: "1"
        )
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken),
            URLQueryItem(name: "v", value: "\(timestamp)")
        ]
        let url = try client.buildURL(endpoint: ApiEndpointsReader.bookTts, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "TTS请求失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        guard apiResponse.isSuccess, let base64 = apiResponse.data, let decoded = Data(base64Encoded: base64) else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "TTS音频响应异常"])
        }
        return decoded
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
        try await bookSourceService.fetchBookSources()
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

    func fetchRssSources() async throws -> RssSourcesResponse {
        try await rssService.fetchRssSources()
    }

    func toggleRssSource(id: String, isEnabled: Bool) async throws {
        try await rssService.toggleSource(id: id, isEnabled: isEnabled)
    }

    func saveRssSource(_ source: RssSource, remoteId: String? = nil) async throws {
        try await rssService.saveRemoteSource(source, id: remoteId)
    }

    func deleteRssSource(id: String) async throws {
        try await rssService.deleteRemoteSource(id: id)
    }

    var canModifyRemoteRssSources: Bool {
        rssService.supportsRemoteEditing
    }
}
