import Foundation

enum MangaImageNormalizer {
    static func sanitizeUrlString(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. 彻底纠正协议头畸形 (http// -> http://, https// -> https://, http:/ -> http:// 等)
        // 使用更稳健的正则表达式或前缀检查
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http//") {
            trimmed = "http://" + trimmed.dropFirst(6)
        } else if lower.hasPrefix("https//") {
            trimmed = "https://" + trimmed.dropFirst(7)
        } else if lower.hasPrefix("http:/") && !lower.hasPrefix("http://") {
            trimmed = "http://" + trimmed.dropFirst(6)
        } else if lower.hasPrefix("https:/") && !lower.hasPrefix("https://") {
            trimmed = "https://" + trimmed.dropFirst(7)
        }
        
        // 再次检查 lower 状态，防止多次 drop 导致的逻辑错误
        let finalLower = trimmed.lowercased()
        if finalLower.hasPrefix("http://") || finalLower.hasPrefix("https://") {
            // 已经是规范的了
        } else if finalLower.contains("//") && !finalLower.contains("://") {
            // 处理类似 custom:// 但写成 custom// 的情况，或者 http// 漏掉了的情况
            if finalLower.hasPrefix("http") {
                trimmed = trimmed.replacingOccurrences(of: "//", with: "://", options: .anchored, range: nil)
            }
        }
        
        // 2. 移除常见的末尾逗号及其后的 Legado 额外参数 (如 ,{...})
        let patterns = ["\\.jpg", "\\.jpeg", "\\.png", "\\.webp", "\\.gif", "\\.bmp"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length)) {
                let end = match.range.location + match.range.length
                let length = (trimmed as NSString).length
                if end >= length { return trimmed }
                let prefix = (trimmed as NSString).substring(to: end)
                let suffix = (trimmed as NSString).substring(from: end)
                if suffix.hasPrefix(",") {
                    return prefix
                }
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

    static func normalizeHost(_ url: URL) -> URL {
        guard let host = url.host?.lowercased() else { return url }
        for rule in MangaImageNormalizationRules.hostRewrites {
            let from = rule.fromSuffix.lowercased()
            if host == from {
                return replaceHost(url, newHost: rule.toSuffix)
            }
            if host.hasSuffix("." + from) {
                let dropCount = from.count + 1
                let prefix = host.dropLast(dropCount)
                let newHost = prefix + "." + rule.toSuffix
                return replaceHost(url, newHost: String(newHost))
            }
        }
        return url
    }

    static func shouldPreferSignedUrls(results: [String], text: String) -> Bool {
        guard !results.isEmpty else { return false }
        guard text.contains("sign=") else { return false }
        let anySigned = results.contains { $0.contains("sign=") }
        if anySigned { return false }
        let allMatch = results.allSatisfy { url in
            guard let host = URL(string: url)?.host?.lowercased() else { return false }
            return MangaImageNormalizationRules.preferSignedHosts.contains { ruleHost in
                host == ruleHost || host.hasSuffix("." + ruleHost)
            }
        }
        return allMatch
    }

    private static func replaceHost(_ url: URL, newHost: String) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = newHost
        return components?.url ?? url
    }
}
