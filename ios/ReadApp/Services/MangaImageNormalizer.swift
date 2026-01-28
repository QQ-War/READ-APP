import Foundation

enum MangaImageNormalizer {
    static func sanitizeUrlString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
