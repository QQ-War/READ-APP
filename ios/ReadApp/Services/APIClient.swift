import Foundation

final class APIClient {
    static let shared = APIClient()

    var baseURL: String {
        let serverURL = UserPreferences.shared.serverURL
        let rawServerURL = serverURL.isEmpty ? "http://127.0.0.1:8080" : serverURL
        let backend = UserPreferences.shared.apiBackend
        return ApiBackendResolver.normalizeBaseURL(rawServerURL, backend: backend, apiVersion: APIService.apiVersion)
    }

    var publicBaseURL: String? {
        let publicServerURL = UserPreferences.shared.publicServerURL
        guard !publicServerURL.isEmpty else { return nil }
        let backend = UserPreferences.shared.apiBackend
        return ApiBackendResolver.normalizeBaseURL(publicServerURL, backend: backend, apiVersion: APIService.apiVersion)
    }

    var accessToken: String {
        UserPreferences.shared.accessToken
    }

    var backend: ApiBackend {
        return UserPreferences.shared.apiBackend
    }

    private init() {}

    func requestWithFailback(endpoint: String, queryItems: [URLQueryItem], timeoutInterval: TimeInterval = 15) async throws -> (Data, HTTPURLResponse) {
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

    func buildURL(endpoint: String, queryItems: [URLQueryItem]? = nil) throws -> URL {
        guard var components = URLComponents(string: "\(baseURL)/\(endpoint)") else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的URL: \(baseURL)/\(endpoint)"])
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无法构建URL"])
        }
        return url
    }

    func buildURL(urlString: String, queryItems: [URLQueryItem]? = nil) throws -> URL {
        guard var components = URLComponents(string: urlString) else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的URL: \(urlString)"])
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw NSError(domain: "APIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无法构建URL"])
        }
        return url
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
        let url = try buildURL(urlString: urlString, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        
        // 自动注入 Authorization Header
        if !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if UserPreferences.shared.isVerboseLoggingEnabled, urlString.contains("getChapterList") {
            let hasAuth = request.value(forHTTPHeaderField: "Authorization") != nil
            LogManager.shared.log("目录Header: hasAuth=\(hasAuth) url=\(url.absoluteString)", category: "阅读诊断")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "APIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "无效的响应类型"])
        }
        return (data, httpResponse)
    }
}
