import Foundation
import UIKit

final class MangaImageService {
    static let shared = MangaImageService()
    private let logger = LogManager.shared
    private var lastKuaikanWarmupReferer: String?
    private var lastKuaikanWarmupAt: Date?
    private let limiter = ImageDownloadLimiter()
    
    private init() {}

    func acquireDownloadPermit() async {
        let maxConcurrent = max(1, UserPreferences.shared.mangaImageMaxConcurrent)
        await limiter.updateMax(maxConcurrent)
        await limiter.acquire()
    }

    func releaseDownloadPermit() {
        Task { await limiter.release() }
    }
    
    func resolveImageURL(_ original: String) -> URL? {
        let cleaned = MangaImageNormalizer.sanitizeUrlString(original)
        if cleaned.hasPrefix("http") {
            if let url = URL(string: cleaned) {
                return normalizeSchemeIfNeeded(MangaImageNormalizer.normalizeHost(url))
            }
            if let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: encoded) {
                return normalizeSchemeIfNeeded(MangaImageNormalizer.normalizeHost(url))
            }
            return nil
        }
        let baseURL = ApiBackendResolver.stripApiBasePath(APIService.shared.baseURL)
        let resolved = cleaned.hasPrefix("/") ? (baseURL + cleaned) : (baseURL + "/" + cleaned)
        if let url = URL(string: resolved) {
            return normalizeSchemeIfNeeded(MangaImageNormalizer.normalizeHost(url))
        }
        if let encoded = resolved.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded) {
            return normalizeSchemeIfNeeded(MangaImageNormalizer.normalizeHost(url))
        }
        return nil
    }

    private func normalizeSchemeIfNeeded(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http" else { return url }
        guard let base = URL(string: APIService.shared.baseURL),
              let baseHost = base.host?.lowercased(),
              let host = url.host?.lowercased(),
              host == baseHost
        else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url ?? url
    }
    
    func fetchImageData(for url: URL, referer: String?) async -> Data? {
        let verbose = UserPreferences.shared.isVerboseLoggingEnabled
        if isPdfImageURL(url) {
            return await fetchPdfImageData(url)
        }
        if UserPreferences.shared.forceMangaProxy, let proxyURL = buildProxyURL(for: url) {
            return await fetchImageData(requestURL: proxyURL, referer: referer)
        }

        if let data = await fetchImageData(requestURL: url, referer: referer) {
            return data
        }
        return nil
    }

    private func fetchImageData(requestURL: URL, referer: String?) async -> Data? {
        var request = URLRequest(url: requestURL)
        let timeout = max(5, UserPreferences.shared.mangaImageTimeout)
        request.timeoutInterval = timeout
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
        if antiScrapingProfile?.key == "kuaikan" {
            let warmupReferer = normalizedReferer ?? antiScrapingProfile?.referer ?? "https://www.kuaikanmanhua.com/"
            await warmupKuaikanCookies(referer: warmupReferer, verbose: verbose)
        }
        if let customUA = antiScrapingProfile?.userAgent {
            request.setValue(customUA, forHTTPHeaderField: "User-Agent")
        }
        if let extraHeaders = antiScrapingProfile?.extraHeaders, !extraHeaders.isEmpty {
            for (key, value) in extraHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        var finalReferer = antiScrapingProfile?.referer ?? "https://www.kuaikanmanhua.com/"
        if antiScrapingProfile?.key == "dm5", var customReferer = normalizedReferer, !customReferer.isEmpty {
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

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 200, !data.isEmpty {
                return data
            }
            if requestURL.absoluteString.localizedCaseInsensitiveContains("/pdfImage") {
                logger.log("PDF图片请求失败: code=\(statusCode) url=\(requestURL.absoluteString)", category: "漫画调试")
            }
            if statusCode == 403 || statusCode == 401 {
                var retry = request
                retry.setValue(antiScrapingProfile?.referer ?? "https://www.kuaikanmanhua.com/", forHTTPHeaderField: "Referer")
                let (retryData, retryResponse) = try await URLSession.shared.data(for: retry)
                let retryCode = (retryResponse as? HTTPURLResponse)?.statusCode ?? 0
                if retryCode == 200, !retryData.isEmpty {
                    return retryData
                }
                if requestURL.absoluteString.localizedCaseInsensitiveContains("/pdfImage") {
                    logger.log("PDF图片重试失败: code=\(retryCode) url=\(requestURL.absoluteString)", category: "漫画调试")
                }
            }
        } catch {
            if requestURL.absoluteString.localizedCaseInsensitiveContains("/pdfImage") {
                logger.log("PDF图片请求异常: \(error.localizedDescription) url=\(requestURL.absoluteString)", category: "漫画调试")
            }
            return nil
        }
        return nil
    }

    private func fetchPdfImageData(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        let timeout = max(8, UserPreferences.shared.mangaImageTimeout)
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = true
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("image/png,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 200, !data.isEmpty {
                return data
            }
            logger.log("PDF图片请求失败: code=\(statusCode) url=\(url.absoluteString)", category: "漫画调试")
        } catch {
            logger.log("PDF图片请求异常: \(error.localizedDescription) url=\(url.absoluteString)", category: "漫画调试")
        }
        return nil
    }

    private func isPdfImageURL(_ url: URL) -> Bool {
        url.absoluteString.localizedCaseInsensitiveContains("/pdfImage")
    }

    private func warmupKuaikanCookies(referer: String, verbose: Bool) async {
        let now = Date()
        if let lastReferer = lastKuaikanWarmupReferer,
           let lastAt = lastKuaikanWarmupAt,
           lastReferer == referer,
           now.timeIntervalSince(lastAt) < 300 {
            return
        }
        guard let url = URL(string: referer) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.httpShouldHandleCookies = true
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        do {
            _ = try await URLSession.shared.data(for: request)
            lastKuaikanWarmupReferer = referer
            lastKuaikanWarmupAt = now
        } catch {
        }
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

actor ImageDownloadLimiter {
    private var maxConcurrent: Int = 2
    private var running: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func updateMax(_ value: Int) {
        maxConcurrent = max(1, value)
        while running < maxConcurrent && !waiters.isEmpty {
            running += 1
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }

    func acquire() async {
        if running < maxConcurrent {
            running += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if running > 0 {
            running -= 1
        }
        if running < maxConcurrent && !waiters.isEmpty {
            running += 1
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }
}
