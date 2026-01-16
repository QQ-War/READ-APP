import Foundation
import UIKit

final class MangaImageService {
    static let shared = MangaImageService()
    private let logger = LogManager.shared
    
    private init() {}
    
    func resolveImageURL(_ original: String) -> URL? {
        let cleaned = sanitizeImageURLString(original)
        if cleaned.hasPrefix("http") {
            return URL(string: cleaned)
        }
        let baseURL = ApiBackendResolver.stripApiBasePath(APIService.shared.baseURL)
        let resolved = cleaned.hasPrefix("/") ? (baseURL + cleaned) : (baseURL + "/" + cleaned)
        return URL(string: resolved)
    }
    
    func fetchImageData(for url: URL, referer: String?) async -> Data? {
        let verbose = UserPreferences.shared.isVerboseLoggingEnabled
        if verbose {
            logger.log("漫画图片请求: url=\(url.absoluteString)", category: "漫画调试")
        }
        if UserPreferences.shared.forceMangaProxy, let proxyURL = buildProxyURL(for: url) {
            if verbose { logger.log("强制代理模式: \(proxyURL.absoluteString)", category: "漫画调试") }
            return await fetchImageData(requestURL: proxyURL, referer: referer)
        }

        if let data = await fetchImageData(requestURL: url, referer: referer) {
            return data
        }
        return nil
    }

    private func fetchImageData(requestURL: URL, referer: String?) async -> Data? {
        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 15
        request.httpShouldHandleCookies = true
        request.cachePolicy = .returnCacheDataElseLoad
        let verbose = UserPreferences.shared.isVerboseLoggingEnabled
        
        // 1:1 模拟真实移动端浏览器请求头
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("image/webp,image/avif,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("no-cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("image", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")

        let normalizedReferer = normalizeReferer(referer, imageURL: requestURL)
        let antiScrapingProfile = MangaAntiScrapingService.shared.resolveProfile(imageURL: requestURL, referer: normalizedReferer)
        if let customUA = antiScrapingProfile?.userAgent {
            request.setValue(customUA, forHTTPHeaderField: "User-Agent")
        }
        if let extraHeaders = antiScrapingProfile?.extraHeaders, !extraHeaders.isEmpty {
            for (key, value) in extraHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        if verbose {
            let profileKey = antiScrapingProfile?.key ?? "none"
            logger.log("反爬匹配: profile=\(profileKey) referer=\(normalizedReferer ?? referer ?? "nil") requestHost=\(requestURL.host ?? "nil")", category: "漫画调试")
        }
        
        var finalReferer = antiScrapingProfile?.referer ?? "https://www.kuaikanmanhua.com/"
        if antiScrapingProfile?.key == "kuaikan", var customReferer = normalizedReferer, !customReferer.isEmpty {
            if customReferer.hasPrefix("http://") {
                customReferer = customReferer.replacingOccurrences(of: "http://", with: "https://")
            }
            if !customReferer.hasSuffix("/") {
                customReferer += "/"
            }
            finalReferer = customReferer
        } else if antiScrapingProfile == nil, var customReferer = normalizedReferer, !customReferer.isEmpty {
            if customReferer.hasPrefix("http://") {
                customReferer = customReferer.replacingOccurrences(of: "http://", with: "https://")
            }
            if !customReferer.hasSuffix("/") {
                customReferer += "/"
            }
            finalReferer = customReferer
        } else if antiScrapingProfile == nil, let host = requestURL.host {
            finalReferer = "https://\(host)/"
        }
        request.setValue(finalReferer, forHTTPHeaderField: "Referer")
        if verbose { logger.log("请求头Referer: \(finalReferer)", category: "漫画调试") }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 200, !data.isEmpty {
                if verbose { logger.log("图片请求成功: \(requestURL.lastPathComponent)", category: "漫画调试") }
                return data
            }
            if statusCode == 403 || statusCode == 401 {
                if verbose { logger.log("图片被拒绝(Code:\(statusCode))，降级Referer重试", category: "漫画调试") }
                var retry = request
                retry.setValue(antiScrapingProfile?.referer ?? "https://www.kuaikanmanhua.com/", forHTTPHeaderField: "Referer")
                let (retryData, retryResponse) = try await URLSession.shared.data(for: retry)
                let retryCode = (retryResponse as? HTTPURLResponse)?.statusCode ?? 0
                if retryCode == 200, !retryData.isEmpty {
                    if verbose { logger.log("重试成功: \(requestURL.lastPathComponent)", category: "漫画调试") }
                    return retryData
                }
                if verbose { logger.log("重试失败(Code:\(retryCode))", category: "漫画调试") }
            }
            if verbose { logger.log("图片请求失败(Code:\(statusCode))", category: "漫画调试") }
        } catch {
            if verbose { logger.log("图片请求异常: \(error.localizedDescription)", category: "漫画调试") }
            return nil
        }
        return nil
    }

    private func normalizeReferer(_ referer: String?, imageURL: URL) -> String? {
        guard var value = referer?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return value
        }
        guard let host = imageURL.host else { return value }
        if !value.hasPrefix("/") {
            value = "/" + value
        }
        return "https://\(host)\(value)"
    }

    private func sanitizeImageURLString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = ["\\.jpg", "\\.jpeg", "\\.png", "\\.webp", "\\.gif", "\\.bmp"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length)) {
                let end = match.range.location + match.range.length
                if end < (trimmed as NSString).length {
                    let prefix = (trimmed as NSString).substring(to: end)
                    return prefix
                }
                return trimmed
            }
        }
        if let idx = trimmed.range(of: ",%7B")?.lowerBound {
            return String(trimmed[..<idx])
        }
        if let idx = trimmed.range(of: ",{")?.lowerBound {
            return String(trimmed[..<idx])
        }
        return trimmed
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
