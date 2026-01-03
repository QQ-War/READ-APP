import Foundation
import Combine
import UIKit

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

class APIService: ObservableObject {
    static let shared = APIService()
    static let apiVersion = 5
    
    @Published var books: [Book] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // 章节内容缓存
    private var contentCache: [String: String] = [:]
    
    var baseURL: String {
        let serverURL = UserPreferences.shared.serverURL
        if serverURL.isEmpty {
            return "http://127.0.0.1:8080/api/\(Self.apiVersion)"
        }
        return "\(serverURL)/api/\(Self.apiVersion)"
    }
    
    var publicBaseURL: String? {
        let publicServerURL = UserPreferences.shared.publicServerURL
        guard !publicServerURL.isEmpty else { return nil }
        return "\(publicServerURL)/api/\(Self.apiVersion)"
    }
    
    private var accessToken: String {
        UserPreferences.shared.accessToken
    }
    
    private init() {}
    
    // MARK: - Failback 请求方法
    private func requestWithFailback(endpoint: String, queryItems: [URLQueryItem], timeoutInterval: TimeInterval = 15) async throws -> (Data, HTTPURLResponse) {
        let localURL = "\(baseURL)/\(endpoint)"
        do {
            return try await performRequest(urlString: localURL, queryItems: queryItems, timeoutInterval: timeoutInterval)
        } catch let localError as NSError {
            if shouldTryPublicServer(error: localError), let publicBase = publicBaseURL {
                LogManager.shared.log("局域网连接失败，尝试公网服务器...", category: "网络")
                let publicURL = "\(publicBase)/\(endpoint)"
                do {
                    return try await performRequest(urlString: publicURL, queryItems: queryItems, timeoutInterval: timeoutInterval)
                } catch {
                    LogManager.shared.log("公网服务器也失败: \(error)", category: "网络错误")
                    throw localError
                }
            }
            throw localError
        }
    }
    
    private func shouldTryPublicServer(error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain {
            switch error.code {
            case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost:
                return true
            default:
                return false
            }
        }
        return false
    }
    
    private func performRequest(urlString: String, queryItems: [URLQueryItem], timeoutInterval: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(string: urlString) else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的URL: \(urlString)"])
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无法构建URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "无效的响应类型"])
        }
        return (data, httpResponse)
    }

    // MARK: - 登录
    func login(username: String, password: String) async throws -> String {
        let urlString = "\(baseURL)/login"
        guard var components = URLComponents(string: urlString) else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的URL: \(urlString)"])
        }
        let deviceModel = await MainActor.run { UIDevice.current.model }
        components.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "model", value: deviceModel)
        ]
        guard let url = components.url else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无法构建URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "无效的响应类型"])
            }
            if httpResponse.statusCode != 200 {
                throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "服务器错误(状态码: \(httpResponse.statusCode))"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<LoginResponse>.self, from: data)
            if apiResponse.isSuccess, let loginData = apiResponse.data {
                return loginData.accessToken
            } else {
                throw NSError(domain: "APIService", code: 401, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "登录失败"])
            }
        } catch let error as NSError {
            if error.domain == NSURLErrorDomain {
                throw NSError(domain: "APIService", code: error.code, userInfo: [NSLocalizedDescriptionKey: "网络连接失败: \(error.localizedDescription)"])
            }
            throw error
        }
    }
    
    // MARK: - 获取书架列表
    func fetchBookshelf() async throws {
        guard !accessToken.isEmpty else {
            throw NSError(domain: "APIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
        }
        let queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken),
            URLQueryItem(name: "version", value: "1.0.0")
        ]
        let (data, httpResponse) = try await requestWithFailback(endpoint: "getBookshelf", queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器错误"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<[Book]>.self, from: data)
        if apiResponse.isSuccess, let books = apiResponse.data {
            await MainActor.run {
                self.books = books
            }
        } else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "获取书架失败"])
        }
    }
    
    // MARK: - 获取章节列表
    func fetchChapterList(bookUrl: String, bookSourceUrl: String?) async throws -> [BookChapter] {
        var queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken),
            URLQueryItem(name: "url", value: bookUrl)
        ]
        if let bookSourceUrl = bookSourceUrl {
            queryItems.append(URLQueryItem(name: "bookSourceUrl", value: bookSourceUrl))
        }
        
        do {
            let (data, httpResponse) = try await requestWithFailback(endpoint: "getChapterList", queryItems: queryItems)
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器错误"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<[BookChapter]>.self, from: data)
            if apiResponse.isSuccess, let chapters = apiResponse.data {
                // 保存目录到本地缓存
                LocalCacheManager.shared.saveChapterList(bookUrl: bookUrl, chapters: chapters)
                return chapters
            } else {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "获取章节列表失败"])
            }
        } catch {
            // 如果网络失败，尝试从本地缓存读取
            if let cachedChapters = LocalCacheManager.shared.loadChapterList(bookUrl: bookUrl) {
                return cachedChapters
            }
            throw error
        }
    }
    
    // MARK: - 获取章节内容
    func fetchChapterContent(bookUrl: String, bookSourceUrl: String?, index: Int) async throws -> String {
        // 1. 优先尝试从本地磁盘缓存读取
        if let cachedContent = LocalCacheManager.shared.loadChapter(bookUrl: bookUrl, index: index) {
            return cachedContent
        }
        
        // 2. 尝试从内存缓存读取
        let cacheKey = "\(bookUrl)_\(index)"
        if let cachedContent = contentCache[cacheKey] {
            return cachedContent
        }
        
        // 3. 网络请求
        var queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken),
            URLQueryItem(name: "url", value: bookUrl),
            URLQueryItem(name: "index", value: "\(index)"),
            URLQueryItem(name: "type", value: "0")
        ]
        if let bookSourceUrl = bookSourceUrl {
            queryItems.append(URLQueryItem(name: "bookSourceUrl", value: bookSourceUrl))
        }
        
        let (data, httpResponse) = try await requestWithFailback(endpoint: "getBookContent", queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器错误"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if apiResponse.isSuccess, let content = apiResponse.data {
            // 存入内存缓存
            contentCache[cacheKey] = content
            // 同步存入磁盘缓存
            LocalCacheManager.shared.saveChapter(bookUrl: bookUrl, index: index, content: content)
            return content
        } else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "获取章节内容失败"])
        }
    }
    
    // MARK: - 保存阅读进度
    func saveBookProgress(bookUrl: String, index: Int, pos: Double, title: String?) async throws {
        guard var components = URLComponents(string: "\(baseURL)/saveBookProgress") else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的URL"])
        }
        var queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken),
            URLQueryItem(name: "url", value: bookUrl),
            URLQueryItem(name: "index", value: "\(index)"),
            URLQueryItem(name: "pos", value: "\(pos)")
        ]
        if let title = title {
            queryItems.append(URLQueryItem(name: "title", value: title))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, _) = try await URLSession.shared.data(for: request)
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            print("保存进度失败: \(apiResponse.errorMsg ?? "未知错误")")
        }
    }
    
    // MARK: - TTS 相关
    func fetchTTSList() async throws -> [HttpTTS] {
        let (data, httpResponse) = try await requestWithFailback(endpoint: "getalltts", queryItems: [URLQueryItem(name: "accessToken", value: accessToken)])
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器错误"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<[HttpTTS]>.self, from: data)
        if apiResponse.isSuccess, let ttsList = apiResponse.data {
            return ttsList
        } else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "获取TTS引擎列表失败"])
        }
    }
    
    func buildTTSAudioURL(ttsId: String, text: String, speechRate: Double) -> URL? {
        guard var components = URLComponents(string: "\(baseURL)/tts") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken),
            URLQueryItem(name: "id", value: ttsId),
            URLQueryItem(name: "speakText", value: text),
            URLQueryItem(name: "speechRate", value: "\(speechRate)")
        ]
        return components.url
    }

    // MARK: - TTS CRUD
    func saveTTS(tts: HttpTTS) async throws {
        guard var components = URLComponents(string: "\(baseURL)/addtts") else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的URL"])
        }
        components.queryItems = [URLQueryItem(name: "accessToken", value: accessToken)]
        guard let url = components.url else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无法构建URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(tts)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "保存TTS失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "保存TTS时发生未知错误"])
        }
    }

    func deleteTTS(id: String) async throws {
        let queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken),
            URLQueryItem(name: "id", value: id)
        ]
        let (data, httpResponse) = try await requestWithFailback(endpoint: "deltts", queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "删除TTS失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "删除TTS时发生未知错误"])
        }
    }
    
    // MARK: - 其他
    func clearLocalCache() {
        contentCache.removeAll()
    }

    // MARK: - 替换净化规则
    
    func fetchReplaceRules() async throws -> [ReplaceRule] {
        let pageInfo = try await fetchReplaceRulePageInfo()
        if pageInfo.page <= 0 || pageInfo.md5.isEmpty {
            return []
        }

        var allRules: [ReplaceRule] = []
        for page in 1...pageInfo.page {
            let (data, httpResponse) = try await requestWithFailback(
                endpoint: "getReplaceRulesNew",
                queryItems: [
                    URLQueryItem(name: "accessToken", value: accessToken),
                    URLQueryItem(name: "md5", value: pageInfo.md5),
                    URLQueryItem(name: "page", value: "\(page)")
                ]
            )
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取净化规则失败"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<[ReplaceRule]>.self, from: data)
            if apiResponse.isSuccess, let rules = apiResponse.data {
                allRules.append(contentsOf: rules)
            } else {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "解析净化规则失败"])
            }
        }
        return allRules
    }

    private func fetchReplaceRulePageInfo() async throws -> ReplaceRulePageInfo {
        let (data, httpResponse) = try await requestWithFailback(
            endpoint: "getReplaceRulesPage",
            queryItems: [URLQueryItem(name: "accessToken", value: accessToken)]
        )
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取净化规则页信息失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<ReplaceRulePageInfo>.self, from: data)
        if apiResponse.isSuccess, let info = apiResponse.data {
            return info
        } else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "解析净化规则页信息失败"])
        }
    }
    
    func saveReplaceRule(rule: ReplaceRule) async throws {
        guard var components = URLComponents(string: "\(baseURL)/addReplaceRule") else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的URL"])
        }
        components.queryItems = [URLQueryItem(name: "accessToken", value: accessToken)]
        
        guard let url = components.url else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无法构建URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(rule)

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "保存规则失败"])
        }
        
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "保存规则时发生未知错误"])
        }
    }
    
    func deleteReplaceRule(id: String) async throws {
        let queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken),
            URLQueryItem(name: "id", value: id)
        ]
        let (data, httpResponse) = try await requestWithFailback(endpoint: "delReplaceRule", queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "删除规则失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "删除规则时发生未知错误"])
        }
    }
    
    func toggleReplaceRule(id: String, isEnabled: Bool) async throws {
        let queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken),
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "st", value: isEnabled ? "1" : "0")
        ]
        let (data, httpResponse) = try await requestWithFailback(endpoint: "stopReplaceRules", queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "切换规则状态失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "切换规则状态时发生未知错误"])
        }
    }
    
    // MARK: - Book Import
    func importBook(from url: URL) async throws {
        guard !accessToken.isEmpty else {
            throw NSError(domain: "APIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
        }
        
        guard let serverURL = URL(string: "\(baseURL)/uploadBook") else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的上传URL"])
        }
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type") // Or appropriate content type
        request.setValue(accessToken, forHTTPHeaderField: "accessToken")
        
        do {
            let (data, response) = try await URLSession.shared.upload(for: request, fromFile: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "无效的响应类型"])
            }
            
            if httpResponse.statusCode != 200 {
                let errorMsg = String(data: data, encoding: .utf8) ?? "未知服务器错误"
                throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "上传失败: \(errorMsg)"])
            }
            
            let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
            if !apiResponse.isSuccess {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "导入书籍失败"])
            }
        } catch let error as NSError {
            throw NSError(domain: "APIService", code: error.code, userInfo: [NSLocalizedDescriptionKey: "上传书籍失败: \(error.localizedDescription)"])
        }
    }

    // MARK: - Book Sources
    func fetchBookSources() async throws -> [BookSource] {
        let pageInfo = try await fetchBookSourcePageInfo()
        if pageInfo.page <= 0 || pageInfo.md5.isEmpty {
            return []
        }

        var allSources: [BookSource] = []
        for page in 1...pageInfo.page {
            let (data, httpResponse) = try await requestWithFailback(
                endpoint: "getBookSourcesNew",
                queryItems: [
                    URLQueryItem(name: "accessToken", value: accessToken),
                    URLQueryItem(name: "md5", value: pageInfo.md5),
                    URLQueryItem(name: "page", value: "\(page)")
                ]
            )
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取书源失败"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<[BookSource]>.self, from: data)
            if apiResponse.isSuccess, let sources = apiResponse.data {
                allSources.append(contentsOf: sources)
            } else {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "解析书源失败"])
            }
        }
        return allSources
    }

    private func fetchBookSourcePageInfo() async throws -> BookSourcePageInfo {
        let (data, httpResponse) = try await requestWithFailback(
            endpoint: "getBookSourcesPage",
            queryItems: [URLQueryItem(name: "accessToken", value: accessToken)]
        )
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取书源页信息失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<BookSourcePageInfo>.self, from: data)
        if apiResponse.isSuccess, let info = apiResponse.data {
            return info
        } else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "解析书源页信息失败"])
        }
    }
    
    func saveBookSource(jsonContent: String) async throws {
        guard var components = URLComponents(string: "\(baseURL)/saveBookSource") else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的URL"])
        }
        components.queryItems = [URLQueryItem(name: "accessToken", value: accessToken)]
        
        guard let url = components.url else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无法构建URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Server expects the body to be the direct JSON string content
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonContent.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "保存书源失败"])
        }
        
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "保存书源时发生未知错误"])
        }
    }

    func deleteBookSource(id: String) async throws {
        let queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken),
            URLQueryItem(name: "id", value: id)
        ]
        let (data, httpResponse) = try await requestWithFailback(endpoint: "delbookSource", queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "删除书源失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "删除书源时发生未知错误"])
        }
    }

    func toggleBookSource(id: String, isEnabled: Bool) async throws {
        let queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken),
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "st", value: isEnabled ? "1" : "0")
        ]
        let (data, httpResponse) = try await requestWithFailback(endpoint: "stopbookSource", queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "切换书源状态失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "切换书源状态时发生未知错误"])
        }
    }
    
    func getBookSourceDetail(id: String) async throws -> String {
        let queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken),
            URLQueryItem(name: "id", value: id)
        ]
        let (data, httpResponse) = try await requestWithFailback(endpoint: "getbookSources", queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取书源详情失败"])
        }
        
        // Response data structure: {"json": "...", "enabled": true, ...}
        struct BookSourceDetailResponse: Codable {
            let json: String?
        }
        
        let apiResponse = try JSONDecoder().decode(APIResponse<BookSourceDetailResponse>.self, from: data)
        if apiResponse.isSuccess, let detail = apiResponse.data, let json = detail.json {
            return json
        } else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "获取书源详情内容失败"])
        }
    }
    
    // MARK: - Book Search
    func searchBook(keyword: String, bookSourceUrl: String, page: Int = 1) async throws -> [Book] {
        guard !accessToken.isEmpty else {
            throw NSError(domain: "APIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
        }
        
        let queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken),
            URLQueryItem(name: "bookSourceUrl", value: bookSourceUrl),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "key", value: keyword)
        ]
        
        let (data, httpResponse) = try await requestWithFailback(endpoint: "searchBook", queryItems: queryItems)
        
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "搜索书籍失败"])
        }
        
        let apiResponse = try JSONDecoder().decode(APIResponse<[Book]>.self, from: data)
        if apiResponse.isSuccess, let books = apiResponse.data {
            return books
        } else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "解析搜索结果失败"])
        }
    }
    
    // MARK: - Save Book to Bookshelf
    func saveBook(book: Book, useReplaceRule: Int = 0) async throws {
        guard !accessToken.isEmpty else {
            throw NSError(domain: "APIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
        }
        
        guard var components = URLComponents(string: "\(baseURL)/saveBook") else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的URL"])
        }
        // AccessToken and useReplaceRule are query parameters, not part of the book JSON body
        components.queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken),
            URLQueryItem(name: "useReplaceRule", value: "\(useReplaceRule)")
        ]
        
        guard let url = components.url else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无法构建URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(book)

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "保存书籍失败"])
        }
        
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "保存书籍时发生未知错误"])
        }
    }

    // MARK: - Delete Book from Bookshelf
    func deleteBook(bookUrl: String) async throws {
        guard !accessToken.isEmpty else {
            throw NSError(domain: "APIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
        }
        guard var components = URLComponents(string: "\(baseURL)/deleteBook") else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的URL"])
        }
        components.queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken)
        ]
        guard let url = components.url else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无法构建URL"])
        }

        struct DeleteBookRequest: Codable {
            let bookUrl: String
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DeleteBookRequest(bookUrl: bookUrl))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "删除书籍失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "删除书籍时发生未知错误"])
        }
    }
    
    // MARK: - Cache Management
    func clearAllRemoteCache() async throws {
        guard !accessToken.isEmpty else {
            throw NSError(domain: "APIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
        }
        let queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken)
        ]
        let (data, httpResponse) = try await requestWithFailback(endpoint: "clearAllRemoteCache", queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "清除远程缓存失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "清除远程缓存时发生未知错误"])
        }
    }
    
    // MARK: - Default TTS
    func fetchDefaultTTS() async throws -> String {
        guard !accessToken.isEmpty else {
            throw NSError(domain: "APIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
        }
        let queryItems = [
            URLQueryItem(name: "accessToken", value: accessToken)
        ]
        let (data, httpResponse) = try await requestWithFailback(endpoint: "getDefaultTTS", queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取默认TTS失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if apiResponse.isSuccess, let defaultTTSId = apiResponse.data {
            return defaultTTSId
        } else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "获取默认TTS时发生未知错误"])
        }
    }
}
