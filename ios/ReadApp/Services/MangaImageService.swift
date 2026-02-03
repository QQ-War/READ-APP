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
        if let assetURL = buildAssetURLIfNeeded(cleaned) {
            return assetURL
        }
        if isAssetPath(cleaned) {
            return nil
        }
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
        // 1. 优先处理特殊路径：本地上传的 PDF 图片缩略图
        if isPdfImageURL(url) {
            return await fetchPdfImageData(url)
        }
        
        // 2. 处理代理逻辑
        if UserPreferences.shared.forceMangaProxy, let proxyURL = buildProxyURL(for: url) {
            return await fetchImageData(requestURL: proxyURL, referer: referer)
        }

        // 3. 普通图像抓取
        return await fetchImageData(requestURL: url, referer: referer)
    }

    private func fetchImageData(requestURL: URL, referer: String?) async -> Data? {
        var request = URLRequest(url: requestURL)
        let timeout = max(5, UserPreferences.shared.mangaImageTimeout)
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = true
        request.cachePolicy = .returnCacheDataElseLoad
        
        // 统一移动端 User-Agent
        let defaultUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/604.1"
        request.setValue(defaultUA, forHTTPHeaderField: "User-Agent")
        request.setValue("image/webp,image/avif,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")

        let normalizedReferer = normalizeReferer(referer, imageURL: requestURL)
        let profile = MangaAntiScrapingService.shared.resolveProfile(imageURL: requestURL, referer: normalizedReferer)
        
        // 特殊站点热身逻辑（如快看）
        if profile?.key == "kuaikan" {
            let warmupReferer = normalizedReferer ?? profile?.referer ?? "https://www.kuaikanmanhua.com/"
            await warmupKuaikanCookies(referer: warmupReferer)
        }
        
        // 应用站点特定配置
        if let customUA = profile?.userAgent {
            request.setValue(customUA, forHTTPHeaderField: "User-Agent")
        }
        profile?.extraHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        // 智能推断最终 Referer
        let finalReferer: String
        if profile?.key == "dm5", let custom = normalizedReferer, !custom.isEmpty {
            finalReferer = custom.replacingOccurrences(of: "http://", with: "https://").appending(custom.hasSuffix("/") ? "" : "/")
        } else if let profileReferer = profile?.referer {
            finalReferer = profileReferer
        } else if let custom = normalizedReferer, !custom.isEmpty {
            finalReferer = custom.replacingOccurrences(of: "http://", with: "https://").appending(custom.hasSuffix("/") ? "" : "/")
        } else if let host = requestURL.host {
            finalReferer = "https://\(host)/"
        } else {
            finalReferer = "https://www.kuaikanmanhua.com/" // 最后的备选项
        }
        request.setValue(finalReferer, forHTTPHeaderField: "Referer")

        let startedAt = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 200, !data.isEmpty {
                return data
            }
            let elapsed = Date().timeIntervalSince(startedAt)
            logger.log("图片请求失败: status=\(statusCode) bytes=\(data.count) elapsed=\(String(format: "%.2f", elapsed))s url=\(requestURL.absoluteString)", category: "漫画调试")
            
            // 针对 403/401 的二次重试逻辑（使用更保守的站点主页作为 Referer）
            if (statusCode == 403 || statusCode == 401), let fallbackReferer = profile?.referer {
                var retryRequest = request
                retryRequest.setValue(fallbackReferer, forHTTPHeaderField: "Referer")
                let retryStartedAt = Date()
                let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)
                let retryStatus = (retryResponse as? HTTPURLResponse)?.statusCode ?? 0
                if retryStatus == 200, !retryData.isEmpty {
                    return retryData
                }
                let retryElapsed = Date().timeIntervalSince(retryStartedAt)
                logger.log("图片重试失败: status=\(retryStatus) bytes=\(retryData.count) elapsed=\(String(format: "%.2f", retryElapsed))s url=\(requestURL.absoluteString)", category: "漫画调试")
            }
        } catch {
            let elapsed = Date().timeIntervalSince(startedAt)
            let nsError = error as NSError
            logger.log("图片请求异常: \(nsError.domain)#\(nsError.code) \(nsError.localizedDescription) elapsed=\(String(format: "%.2f", elapsed))s url=\(requestURL.absoluteString)", category: "漫画调试")
            return nil
        }
        return nil
    }

    private func fetchPdfImageData(_ url: URL) async -> Data? {
        var requestURL = url
        if !requestURL.absoluteString.contains("accessToken=") {
            var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
            var items = components?.queryItems ?? []
            items.append(URLQueryItem(name: "accessToken", value: UserPreferences.shared.accessToken))
            components?.queryItems = items
            if let updated = components?.url {
                requestURL = updated
            }
        }
        var request = URLRequest(url: requestURL)
        request.timeoutInterval = max(8, UserPreferences.shared.mangaImageTimeout)
        request.httpShouldHandleCookies = true
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("image/png,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")

        let startedAt = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 200, !data.isEmpty {
                return data
            }
            let elapsed = Date().timeIntervalSince(startedAt)
            logger.log("PDF图片请求失败: status=\(statusCode) bytes=\(data.count) elapsed=\(String(format: "%.2f", elapsed))s url=\(requestURL.absoluteString)", category: "漫画调试")
        } catch {
            let elapsed = Date().timeIntervalSince(startedAt)
            let nsError = error as NSError
            logger.log("PDF图片请求异常: \(nsError.domain)#\(nsError.code) \(nsError.localizedDescription) elapsed=\(String(format: "%.2f", elapsed))s url=\(requestURL.absoluteString)", category: "漫画调试")
        }
        return nil
    }

    private func isPdfImageURL(_ url: URL) -> Bool {
        url.absoluteString.localizedCaseInsensitiveContains("/pdfImage")
    }

    private func warmupKuaikanCookies(referer: String) async {
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

    private func buildAssetURLIfNeeded(_ value: String) -> URL? {
        var path = value
        if value.hasPrefix("http://assets/") || value.hasPrefix("https://assets/") {
            path = "/assets/" + value.split(separator: "/", omittingEmptySubsequences: true).dropFirst(1).joined(separator: "/")
        } else if value.hasPrefix("../assets/") {
            path = "/assets/" + value.dropFirst("../assets/".count)
        } else if value.hasPrefix("../book-assets/") {
            path = "/book-assets/" + value.dropFirst("../book-assets/".count)
        } else if value.hasPrefix("assets/") {
            path = "/assets/" + value.dropFirst("assets/".count)
        } else if value.hasPrefix("book-assets/") {
            path = "/book-assets/" + value.dropFirst("book-assets/".count)
        } else if value.hasPrefix("/assets/") || value.hasPrefix("/book-assets/") {
            path = value
        } else if let absolute = URL(string: value) {
            let rawPath = absolute.path
            if rawPath.contains("/assets/") || rawPath.contains("/book-assets/") {
                var normalizedPath = rawPath.replacingOccurrences(of: "/../", with: "/")
                if !normalizedPath.hasPrefix("/") {
                    normalizedPath = "/" + normalizedPath
                }
                if let range = normalizedPath.range(of: "/assets/") {
                    path = String(normalizedPath[range.lowerBound...])
                } else if let range = normalizedPath.range(of: "/book-assets/") {
                    path = String(normalizedPath[range.lowerBound...])
                } else {
                    return nil
                }
            } else {
                return nil
            }
        } else {
            return nil
        }
        let baseURL = APIService.shared.baseURL
        let token = UserPreferences.shared.accessToken
        if token.isEmpty {
            return nil
        }
        var components = URLComponents(string: "\(baseURL)/assets")
        components?.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "accessToken", value: token)
        ]
        return components?.url
    }

    private func isAssetPath(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("/assets/")
            || lower.hasPrefix("assets/")
            || lower.hasPrefix("../assets/")
            || lower.hasPrefix("/book-assets/")
            || lower.hasPrefix("book-assets/")
            || lower.hasPrefix("../book-assets/")
            || lower.hasPrefix("http://assets/")
            || lower.hasPrefix("https://assets/")
    }

    /// 预解码图像，避免首次渲染时主线程解码卡顿
    func decodeImage(_ image: UIImage) -> UIImage {
        let size = image.size
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
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
