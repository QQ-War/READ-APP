import Foundation
import UIKit

final class MangaImageService {
    static let shared = MangaImageService()
    private let logger = LogManager.shared
    
    private init() {}
    
    func resolveImageURL(_ original: String) -> URL? {
        if original.hasPrefix("http") {
            return URL(string: original)
        }
        let baseURL = ApiBackendResolver.stripApiBasePath(APIService.shared.baseURL)
        let resolved = original.hasPrefix("/") ? (baseURL + original) : (baseURL + "/" + original)
        return URL(string: resolved)
    }
    
    func fetchImageData(for url: URL, referer: String?) async -> Data? {
        if UserPreferences.shared.forceMangaProxy, let proxyURL = buildProxyURL(for: url) {
            return await fetchImageData(requestURL: proxyURL, referer: referer)
        }

        if let data = await fetchImageData(requestURL: url, referer: referer) {
            return data
        }

        if let proxyURL = buildProxyURL(for: url) {
            return await fetchImageData(requestURL: proxyURL, referer: referer)
        }

        return nil
    }

    private func fetchImageData(requestURL: URL, referer: String?) async -> Data? {
        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 15
        request.httpShouldHandleCookies = true
        request.cachePolicy = .returnCacheDataElseLoad
        
        // 1:1 模拟真实移动端浏览器请求头
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("image/webp,image/avif,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("no-cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("image", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")
        
        var finalReferer = "https://m.kuaikanmanhua.com/"
        if var customReferer = referer, !customReferer.isEmpty {
            if customReferer.hasPrefix("http://") {
                customReferer = customReferer.replacingOccurrences(of: "http://", with: "https://")
            }
            if !customReferer.hasSuffix("/") {
                customReferer += "/"
            }
            finalReferer = customReferer
        } else if let host = requestURL.host {
            finalReferer = "https://\(host)/"
        }
        request.setValue(finalReferer, forHTTPHeaderField: "Referer")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 200, !data.isEmpty {
                return data
            }
            if statusCode == 403 || statusCode == 401 {
                var retry = request
                retry.setValue("https://m.kuaikanmanhua.com/", forHTTPHeaderField: "Referer")
                let (retryData, retryResponse) = try await URLSession.shared.data(for: retry)
                let retryCode = (retryResponse as? HTTPURLResponse)?.statusCode ?? 0
                if retryCode == 200, !retryData.isEmpty {
                    return retryData
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    func buildProxyURL(for original: URL) -> URL? {
        let baseURL = APIService.shared.baseURL
        var components = URLComponents(string: "\(baseURL)/proxypng")
        components?.queryItems = [
            URLQueryItem(name: "url", value: original.absoluteString),
            URLQueryItem(name: "accessToken", value: UserPreferences.shared.accessToken)
        ]
        return components?.url
    }
}
