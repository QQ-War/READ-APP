import Foundation
import UIKit
import CryptoKit

final class ImageGatewayService {
    static let shared = ImageGatewayService()
    private let logger = LogManager.shared
    private var lastKuaikanWarmupReferer: String?
    private var lastKuaikanWarmupAt: Date?
    private let limiter = ImageDownloadLimiter()
    
    private init() {}

    func rewriteLocalEpubImageSourcesIfNeeded(_ rawContent: String, book: Book) -> String {
        guard APIClient.shared.backend == .read else { return rawContent }
        guard isLocalEpubBook(book) else { return rawContent }
        guard rawContent.localizedCaseInsensitiveContains("<img") else { return rawContent }
        guard let bookUrl = book.bookUrl, !bookUrl.isEmpty else { return rawContent }

        var result = rawContent

        // 1) rewrite img src="..."
        let srcPattern = "(?i)\\bsrc\\s*=\\s*(['\"])(.*?)\\1"
        if let regex = try? NSRegularExpression(pattern: srcPattern, options: []) {
            let nsText = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                guard match.numberOfRanges >= 3 else { continue }
                let valueRange = match.range(at: 2)
                let original = nsText.substring(with: valueRange)
                let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if shouldSkipLocalEpubRewrite(trimmed) { continue }
                if !looksLikeImagePath(trimmed) { continue }

                let md5 = md5Encode16(bookUrl + trimmed)
                let rewritten = "/assets?path=/assets/covers/\(md5).jpg"
                result = (result as NSString).replacingCharacters(in: valueRange, with: rewritten)
            }
        }

        // 2) rewrite plain relative image paths (not in src attr)
        let plainPattern = #"(?i)(\.\./|\./|/)?[^\s"'<>]+\.(jpg|jpeg|png|webp|gif|bmp)"#
        if let regex = try? NSRegularExpression(pattern: plainPattern, options: []) {
            let nsText = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                guard match.numberOfRanges >= 1 else { continue }
                let valueRange = match.range(at: 0)
                let original = nsText.substring(with: valueRange)
                let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if shouldSkipLocalEpubRewrite(trimmed) { continue }
                if !looksLikeImagePath(trimmed) { continue }

                let md5 = md5Encode16(bookUrl + trimmed)
                let rewritten = "/assets?path=/assets/covers/\(md5).jpg"
                result = (result as NSString).replacingCharacters(in: valueRange, with: rewritten)
            }
        }

        return result
    }

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

        // reader 后端：EPUB 解压资源实际挂在 /epub 下，避免使用 /assets/.../index/...
        if APIClient.shared.backend == .reader,
           let rewritten = rewriteReaderEpubAssetURLIfNeeded(cleaned),
           rewritten != cleaned {
            if let url = URL(string: rewritten) {
                return normalizeSchemeIfNeeded(MangaImageNormalizer.normalizeHost(url))
            }
        }
        
        // 1. 优先尝试将其作为后端资产路径处理（会补全域名和 Token）
        if let assetURL = buildAssetURLIfNeeded(cleaned) {
            return assetURL
        }
        
        // 2. 如果识别为资产路径但转换失败（例如配置缺失或 baseURL 异常），不再尝试作为普通 URL 加载
        if isAssetPath(cleaned) {
            return nil
        }
        
        // 3. 处理带协议的绝对 URL
        if cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://") {
            if let url = URL(string: cleaned) {
                return normalizeSchemeIfNeeded(MangaImageNormalizer.normalizeHost(url))
            }
            if let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: encoded) {
                return normalizeSchemeIfNeeded(MangaImageNormalizer.normalizeHost(url))
            }
        }
        
        // 4. 补全后端 Base URL（处理相对路径）
        // 严格拦截：如果依然包含 // 但没有 ://，说明 sanitize 没能修复它，这通常是无法使用的 URL
        if cleaned.contains("//") && !cleaned.contains("://") {
            return nil
        }

        let baseURL = APIService.shared.baseURL
        guard !baseURL.isEmpty, baseURL.hasPrefix("http") else {
            return nil // 基础域名配置无效时，无法补全相对路径
        }

        // 如果已经是 /api/... 开头，使用根域名拼接，避免 /api/5/api/v5 重复
        if cleaned.hasPrefix("/api/") {
            let rootBase = ApiBackendResolver.stripApiBasePath(baseURL)
            let resolved = rootBase + cleaned
            if let url = URL(string: resolved) {
                return normalizeSchemeIfNeeded(MangaImageNormalizer.normalizeHost(url))
            }
            if let encoded = resolved.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: encoded) {
                return normalizeSchemeIfNeeded(MangaImageNormalizer.normalizeHost(url))
            }
        }
        
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

    private func rewriteReaderEpubAssetURLIfNeeded(_ value: String) -> String? {
        let lower = value.lowercased()
        guard lower.contains("/assets/"), lower.contains("/index/"), lower.contains(".epub") else {
            return nil
        }
        if let url = URL(string: value) {
            var path = url.path
            if path.hasPrefix("/assets/") {
                path = path.replacingOccurrences(of: "/assets/", with: "/epub/")
            }
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.path = path
            return components?.url?.absoluteString ?? value
        }
        return value.replacingOccurrences(of: "/assets/", with: "/epub/")
    }

    private func rewriteReaderEpubAssetURLIfNeeded(_ url: URL) -> URL {
        guard APIClient.shared.backend == .reader else { return url }
        let lowerPath = url.path.lowercased()
        guard lowerPath.contains("/assets/"),
              lowerPath.contains("/index/"),
              lowerPath.contains(".epub") else {
            return url
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if var path = components?.path, path.hasPrefix("/assets/") {
            path = path.replacingOccurrences(of: "/assets/", with: "/epub/")
            components?.path = path
        }
        return components?.url ?? url
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

    private func isLocalEpubBook(_ book: Book) -> Bool {
        let urlLower = book.bookUrl?.lowercased() ?? ""
        if !urlLower.hasSuffix(".epub") { return false }
        if let origin = book.origin?.lowercased(), origin == "local" { return true }
        if let originName = book.originName?.lowercased(), originName.hasSuffix(".epub") { return true }
        return false
    }

    private func shouldSkipLocalEpubRewrite(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return true }
        if lower.hasPrefix("data:") || lower.hasPrefix("about:") || lower.hasPrefix("mailto:") { return true }
        if lower.hasPrefix("tel:") || lower.hasPrefix("javascript:") || lower.hasPrefix("blob:") { return true }
        if lower.hasPrefix("__api_root__") { return true }
        if lower.hasPrefix("/assets/") || lower.hasPrefix("assets/") { return true }
        if lower.hasPrefix("/book-assets/") || lower.hasPrefix("book-assets/") { return true }
        if lower.contains("/assets?path=") || lower.contains("/api/5/assets?path=") || lower.contains("/api/v5/assets?path=") {
            return true
        }
        if lower.hasPrefix("/api/") { return true }
        return false
    }

    private func looksLikeImagePath(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains(".jpg") || lower.contains(".jpeg") || lower.contains(".png")
            || lower.contains(".webp") || lower.contains(".gif") || lower.contains(".bmp")
    }

    private func md5Encode16(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = Insecure.MD5.hash(data: data)
        let full = digest.map { String(format: "%02hhx", $0) }.joined()
        guard full.count >= 24 else { return full }
        let start = full.index(full.startIndex, offsetBy: 8)
        let end = full.index(full.startIndex, offsetBy: 24)
        return String(full[start..<end])
    }
    
    func fetchImageData(for url: URL, referer: String?) async -> Data? {
        let rewrittenURL = rewriteReaderEpubAssetURLIfNeeded(url)
        // 1. 优先处理特殊路径：本地上传的 PDF 图片缩略图
        if isPdfImageURL(rewrittenURL) {
            return await fetchPdfImageData(rewrittenURL)
        }

        // 2. 本地资源永远直连 /assets（忽略 proxypng 开关）
        if isLocalAssetURL(rewrittenURL) {
            return await fetchImageData(requestURL: rewrittenURL, referer: referer)
        }
        
        // 3. 处理代理逻辑
        if UserPreferences.shared.forceMangaProxy, let proxyURL = buildProxyURL(for: rewrittenURL) {
            return await fetchImageData(requestURL: proxyURL, referer: referer)
        }

        // 4. 普通图像抓取
        return await fetchImageData(requestURL: rewrittenURL, referer: referer)
    }

    private func fetchImageData(requestURL: URL, referer: String?) async -> Data? {
        var request = URLRequest(url: requestURL)
        let timeout = max(5, UserPreferences.shared.mangaImageTimeout)
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = true
        request.cachePolicy = .returnCacheDataElseLoad
        
        // 注入认证信息 (仅对自家后端)
        if let base = URL(string: APIService.shared.baseURL),
           let baseHost = base.host?.lowercased(),
           let host = requestURL.host?.lowercased(),
           host == baseHost {
            let token = UserPreferences.shared.accessToken
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }

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
                logger.log("图片重试失败: status=\(retryStatus) bytes=\(retryData.count) elapsed=\(String(format: "%.2f", retryElapsed))s url=\(request.url?.absoluteString ?? "unknown")", category: "漫画调试")
            }
        } catch {
            let elapsed = Date().timeIntervalSince(startedAt)
            let nsError = error as NSError
            logger.log("图片请求异常: \(nsError.domain)#\(nsError.code) \(nsError.localizedDescription) elapsed=\(String(format: "%.2f", elapsed))s url=\(request.url?.absoluteString ?? "unknown")", category: "漫画调试")
            return nil
        }
        return nil
    }

    private func fetchPdfImageData(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = max(8, UserPreferences.shared.mangaImageTimeout)
        request.httpShouldHandleCookies = true
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("image/png,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
        
        let token = UserPreferences.shared.accessToken
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let startedAt = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 200, !data.isEmpty {
                return data
            }
            let elapsed = Date().timeIntervalSince(startedAt)
            logger.log("PDF图片请求失败: status=\(statusCode) bytes=\(data.count) elapsed=\(String(format: "%.2f", elapsed))s url=\(request.url?.absoluteString ?? "unknown")", category: "漫画调试")
        } catch {
            let elapsed = Date().timeIntervalSince(startedAt)
            let nsError = error as NSError
            logger.log("PDF图片请求异常: \(nsError.domain)#\(nsError.code) \(nsError.localizedDescription) elapsed=\(String(format: "%.2f", elapsed))s url=\(request.url?.absoluteString ?? "unknown")", category: "漫画调试")
        }
        return nil
    }

    private func isPdfImageURL(_ url: URL) -> Bool {
        url.absoluteString.localizedCaseInsensitiveContains("/pdfImage")
    }

    private func isLocalAssetURL(_ url: URL) -> Bool {
        let raw = url.absoluteString.lowercased()
        if raw.contains("/api/5/assets") || raw.contains("/api/v5/assets") {
            return true
        }
        if let host = url.host, host.lowercased() == "assets" {
            return true
        }
        return url.path.lowercased().contains("/assets/") || url.path.lowercased().contains("/book-assets/")
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
            URLQueryItem(name: "url", value: original.absoluteString)
        ]
        return components?.url
    }

    private func buildAssetURLIfNeeded(_ value: String) -> URL? {
        var path = value
        let lower = value.lowercased()

        // 已经是 /assets?path= 或 /api/v5/assets?path= 形式，直接解析并规范化 path
        if lower.contains("/assets?path=") || lower.contains("/api/5/assets?path=") || lower.contains("/api/v5/assets?path=") {
            if let components = URLComponents(string: value),
               let rawPath = components.queryItems?.first(where: { $0.name == "path" })?.value,
               !rawPath.isEmpty {
                path = rawPath
            } else if let range = value.range(of: "path=") {
                path = String(value[range.upperBound...])
            }
        }
        
        if lower.hasPrefix("http://assets/") || lower.hasPrefix("https://assets/") || lower.hasPrefix("http//assets/") || lower.hasPrefix("https//assets/") {
            let components = value.split(separator: "/", omittingEmptySubsequences: true)
            if components.count > 2 {
                // components[0] 是 http: 或 http, components[1] 是 assets
                // 我们需要剩下的是 path
                path = components.dropFirst(2).joined(separator: "/")
            } else {
                return nil
            }
        } else if lower.hasPrefix("http:/assets/") {
            path = String(value.dropFirst("http:/assets/".count))
        } else if lower.hasPrefix("https:/assets/") {
            path = String(value.dropFirst("https:/assets/".count))
        } else if value.hasPrefix("../assets/") {
            path = String(value.dropFirst("../assets/".count))
        } else if value.hasPrefix("../book-assets/") {
            path = "/book-assets/" + value.dropFirst("../book-assets/".count)
        } else if value.hasPrefix("assets/") {
            path = String(value.dropFirst("assets/".count))
        } else if value.hasPrefix("book-assets/") {
            path = "/book-assets/" + value.dropFirst("book-assets/".count)
        } else if value.hasPrefix("/assets/") {
            path = String(value.dropFirst("/assets/".count))
        } else if value.hasPrefix("/book-assets/") {
            path = value
        } else if let absolute = URL(string: value) {
            let rawPath = absolute.path
            if rawPath.contains("/assets/") || rawPath.contains("/book-assets/") {
                var normalizedPath = rawPath.replacingOccurrences(of: "/../", with: "/")
                if !normalizedPath.hasPrefix("/") {
                    normalizedPath = "/" + normalizedPath
                }
                if let range = normalizedPath.range(of: "/assets/") {
                    path = String(normalizedPath[range.upperBound...])
                } else if let range = normalizedPath.range(of: "/book-assets/") {
                    path = String(normalizedPath[range.lowerBound...])
                } else {
                    return nil
                }
            } else {
                return nil
            }
        } else if value.contains("/assets/") || value.contains("/book-assets/") {
            var normalized = value.replacingOccurrences(of: "/../", with: "/")
            if let range = normalized.range(of: "/assets/") {
                path = String(normalized[range.upperBound...])
            } else if let range = normalized.range(of: "/book-assets/") {
                path = String(normalized[range.lowerBound...])
            } else {
                return nil
            }
        } else {
            return nil
        }
        
        // 彻底清理 path：去除开头可能存在的 assets/ 或 /assets/
        while path.hasPrefix("/") { path = String(path.dropFirst()) }
        if path.hasPrefix("assets/") { path = String(path.dropFirst(7)) }
        if path.hasPrefix("book-assets/") { path = String(path.dropFirst(12)) }
        while path.hasPrefix("/") { path = String(path.dropFirst()) }
        
        if path.isEmpty { return nil }
        if path.hasPrefix("covers/") {
            path = "assets/" + path
        } else if !path.hasPrefix("assets/") && !path.hasPrefix("book-assets/") {
            path = "assets/" + path
        }
        
        let baseURL = APIService.shared.baseURL
        guard !baseURL.isEmpty else { return nil }
        if APIClient.shared.backend == .reader {
            let assetBase = ApiBackendResolver.stripApiBasePath(baseURL)
            let normalized = path.hasPrefix("/") ? String(path.dropFirst()) : path
            let resolved = assetBase.hasSuffix("/") ? (assetBase + normalized) : (assetBase + "/" + normalized)
            return URL(string: resolved)
        } else {
            let assetBase = baseURL
            var components = URLComponents(string: "\(assetBase)/assets")
            components?.queryItems = [
                URLQueryItem(name: "path", value: "/" + path)
            ]
            return components?.url
        }
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
            || lower.hasPrefix("http//assets/")
            || lower.hasPrefix("https//assets/")
            || lower.contains("/assets?path=")
            || lower.contains("/api/5/assets?path=")
            || lower.contains("/api/v5/assets?path=")
            || lower.contains("/assets/")
            || lower.contains("/book-assets/")
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
