import Foundation

final class BooksService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    private func applyAuthHeader(to request: inout URLRequest) {
        let token = client.accessToken
        guard !token.isEmpty else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    func fetchBookshelf() async throws -> [Book] {
        guard !client.accessToken.isEmpty else {
            throw NSError(domain: "APIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
        }
        let queryItems = [
            URLQueryItem(name: "version", value: "1.0.0")
        ]
        let endpoint = client.backend == .reader ? ApiEndpointsReader.getBookshelf : ApiEndpoints.getBookshelf
        let (data, httpResponse) = try await client.requestWithFailback(endpoint: endpoint, queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器错误"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<[Book]>.self, from: data)
        if apiResponse.isSuccess, let books = apiResponse.data {
            return books
        } else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "获取书架失败"])
        }
    }

    func fetchChapterList(bookUrl: String, bookSourceUrl: String?) async throws -> [BookChapter] {
        
        var queryItems = [
            URLQueryItem(name: "url", value: bookUrl)
        ]
        if let bookSourceUrl = bookSourceUrl {
            queryItems.append(URLQueryItem(name: "bookSourceUrl", value: bookSourceUrl))
        }

        do {
            let endpoint = client.backend == .reader ? ApiEndpointsReader.getChapterList : ApiEndpoints.getChapterList
            let (data, httpResponse) = try await client.requestWithFailback(endpoint: endpoint, queryItems: queryItems)
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器错误"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<[BookChapter]>.self, from: data)
            if apiResponse.isSuccess, let chapters = apiResponse.data {
                LocalCacheManager.shared.saveChapterList(bookUrl: bookUrl, chapters: chapters)
                return chapters
            } else {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "获取章节列表失败"])
            }
        } catch {
            if let cachedChapters = LocalCacheManager.shared.loadChapterList(bookUrl: bookUrl) {
                return cachedChapters
            }
            throw error
        }
    }

    func saveBookProgress(bookUrl: String, index: Int, pos: Double, title: String?) async throws {
        switch client.backend {
        case .read:
            let queryItems: [URLQueryItem] = {
                var items = [
                    URLQueryItem(name: "url", value: bookUrl),
                    URLQueryItem(name: "index", value: "\(index)"),
                    URLQueryItem(name: "pos", value: "\(pos)")
                ]
                if let title = title {
                    items.append(URLQueryItem(name: "title", value: title))
                }
                return items
            }()
            let url = try client.buildURL(endpoint: ApiEndpoints.saveBookProgress, queryItems: queryItems)
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            applyAuthHeader(to: &request)
            let (data, _) = try await URLSession.shared.data(for: request)
            let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
            if !apiResponse.isSuccess {
                print("保存进度失败: \(apiResponse.errorMsg ?? "未知错误")")
            }
        case .reader:
            let queryItems: [URLQueryItem] = []
            let url = try client.buildURL(endpoint: ApiEndpointsReader.saveBookProgress, queryItems: queryItems)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            applyAuthHeader(to: &request)
            struct SaveProgressPayload: Codable {
                let url: String
                let index: Int
                let pos: Double?
                let title: String?
            }
            request.httpBody = try JSONEncoder().encode(SaveProgressPayload(url: bookUrl, index: index, pos: pos, title: title))
            let (data, _) = try await URLSession.shared.data(for: request)
            let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
            if !apiResponse.isSuccess {
                print("保存进度失败: \(apiResponse.errorMsg ?? "未知错误")")
            }
        }
    }

    func searchBook(keyword: String, bookSourceUrl: String, page: Int = 1) async throws -> [Book] {
        guard !client.accessToken.isEmpty else {
            throw NSError(domain: "APIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
        }

        let queryItems = [
            URLQueryItem(name: "bookSourceUrl", value: bookSourceUrl),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "key", value: keyword)
        ]

        let endpoint = client.backend == .reader ? ApiEndpointsReader.searchBook : ApiEndpoints.searchBook
        let (data, httpResponse) = try await client.requestWithFailback(endpoint: endpoint, queryItems: queryItems)

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

    func fetchExploreKinds(bookSourceUrl: String) async throws -> [BookSource.ExploreKind] {
        switch client.backend {
        case .read:
            let queryItems = [
                URLQueryItem(name: "accessToken", value: client.accessToken),
                URLQueryItem(name: "bookSourceUrl", value: bookSourceUrl),
                URLQueryItem(name: "need", value: "true")
            ]

            let (data, httpResponse) = try await client.requestWithFailback(endpoint: ApiEndpoints.getExploreUrl, queryItems: queryItems)
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "获取发现配置失败"])
            }

            struct ExploreUrlResponse: Codable {
                let found: String?
            }

            let apiResponse = try JSONDecoder().decode(APIResponse<ExploreUrlResponse>.self, from: data)
            if apiResponse.isSuccess, let found = apiResponse.data?.found {
                if let foundData = found.data(using: .utf8) {
                    return try JSONDecoder().decode([BookSource.ExploreKind].self, from: foundData)
                }
            }
            return []
        case .reader:
            let queryItems = [
                URLQueryItem(name: "accessToken", value: client.accessToken),
                URLQueryItem(name: "bookSourceUrl", value: bookSourceUrl)
            ]
            let (data, httpResponse) = try await client.requestWithFailback(endpoint: ApiEndpointsReader.getBookSource, queryItems: queryItems)
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "获取发现配置失败"])
            }
            let apiResponse = try JSONDecoder().decode(APIResponse<BookSource>.self, from: data)
            if apiResponse.isSuccess, let source = apiResponse.data {
                return parseExploreKinds(from: source.exploreUrl)
            }
            return []
        }
    }

    func exploreBook(bookSourceUrl: String, ruleFindUrl: String, page: Int = 1) async throws -> [Book] {
        let queryItems = [
            URLQueryItem(name: "accessToken", value: client.accessToken),
            URLQueryItem(name: "bookSourceUrl", value: bookSourceUrl),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "ruleFindUrl", value: ruleFindUrl)
        ]

        let endpoint = client.backend == .reader ? ApiEndpointsReader.exploreBook : ApiEndpoints.exploreBook
        let (data, httpResponse) = try await client.requestWithFailback(endpoint: endpoint, queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "浏览书源失败"])
        }

        let apiResponse = try JSONDecoder().decode(APIResponse<[Book]>.self, from: data)
        if apiResponse.isSuccess, let books = apiResponse.data {
            return books
        } else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "解析发现结果失败"])
        }
    }

    func saveBook(book: Book, useReplaceRule: Int = 0) async throws {
        guard !client.accessToken.isEmpty else {
            throw NSError(domain: "APIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
        }

        let queryItems = [
            URLQueryItem(name: "accessToken", value: client.accessToken),
            URLQueryItem(name: "useReplaceRule", value: "\(useReplaceRule)")
        ]
        let endpoint = client.backend == .reader ? ApiEndpointsReader.saveBook : ApiEndpoints.saveBook
        let url = try client.buildURL(endpoint: endpoint, queryItems: queryItems)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        applyAuthHeader(to: &request)

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

    func changeBookSource(oldBookUrl: String, newBookUrl: String, newBookSourceUrl: String) async throws {
        let queryItems = [
            URLQueryItem(name: "accessToken", value: client.accessToken),
            URLQueryItem(name: "bookUrl", value: oldBookUrl),
            URLQueryItem(name: "newUrl", value: newBookUrl),
            URLQueryItem(name: "bookSourceUrl", value: newBookSourceUrl)
        ]

        let endpoint = client.backend == .reader ? ApiEndpointsReader.setBookSource : ApiEndpoints.setBookSource
        let (data, httpResponse) = try await client.requestWithFailback(endpoint: endpoint, queryItems: queryItems)
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "换源请求失败"])
        }

        let apiResponse = try JSONDecoder().decode(APIResponse<Book>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "后端换源逻辑执行失败"])
        }
    }

    func deleteBook(bookUrl: String) async throws {
        guard !client.accessToken.isEmpty else {
            throw NSError(domain: "APIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
        }
        let queryItems = [
            URLQueryItem(name: "accessToken", value: client.accessToken)
        ]
        let endpoint = client.backend == .reader ? ApiEndpointsReader.deleteBook : ApiEndpoints.deleteBook
        let url = try client.buildURL(endpoint: endpoint, queryItems: queryItems)

        struct DeleteBookRequest: Codable {
            let bookUrl: String
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DeleteBookRequest(bookUrl: bookUrl))
        applyAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIService", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "删除书籍失败"])
        }
        let apiResponse = try JSONDecoder().decode(APIResponse<String>.self, from: data)
        if !apiResponse.isSuccess {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "删除书籍时发生未知错误"])
        }
    }

    func importBook(from url: URL) async throws {
        guard !client.accessToken.isEmpty else {
            throw NSError(domain: "APIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
        }

        let urlString = "\(client.baseURL)/importBookPreview"
        guard let serverURL = URL(string: urlString) else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的上传URL"])
        }

        do {
            var headers: [String: String] = [:]
            headers["Authorization"] = "Bearer \(client.accessToken)"
            let (data, httpResponse) = try await BookUploadService.shared.uploadBook(fileURL: url, serverURL: serverURL, headers: headers)

            if httpResponse.statusCode != 200 {
                let errorMsg = String(data: data, encoding: .utf8) ?? "未知服务器错误"
                throw NSError(domain: "APIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "上传失败: \(errorMsg)"])
            }

            let apiResponse = try JSONDecoder().decode(APIResponse<BookImportResponse>.self, from: data)
            if !apiResponse.isSuccess {
                throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: apiResponse.errorMsg ?? "导入书籍失败"])
            }
        } catch let error as NSError {
            throw NSError(domain: "APIService", code: error.code, userInfo: [NSLocalizedDescriptionKey: "上传书籍失败: \(error.localizedDescription)"])
        }
    }

    private func parseExploreKinds(from exploreUrl: String?) -> [BookSource.ExploreKind] {
        guard let exploreUrl, !exploreUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let trimmed = exploreUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") {
            if let data = trimmed.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([BookSource.ExploreKind].self, from: data) {
                return decoded
            }
            return []
        }
        let separators = ["::", "##", "："]
        let entries = trimmed
            .components(separatedBy: "\n")
            .flatMap { $0.components(separatedBy: "&&") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return entries.map { entry in
            let parts = separators.first { entry.contains($0) }.map { entry.components(separatedBy: $0) }
            let rawTitle = parts?.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (rawTitle?.isEmpty == false) ? rawTitle! : entry
            let rawUrl = parts?.dropFirst().joined(separator: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let url = (rawUrl?.isEmpty == false) ? rawUrl! : entry
            return BookSource.ExploreKind(title: title, url: url)
        }
    }
}
