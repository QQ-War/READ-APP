import Foundation

enum MangaImageExtractor {
    private static let minExpectedImageCount = 3

    static func extractImageUrls(from rawContent: String) -> [String] {
        return extractInternal(from: rawContent, wrapToken: false)
    }

    static func extractImageTokens(from rawContent: String) -> [String] {
        return extractInternal(from: rawContent, wrapToken: true)
    }

    private static func extractInternal(from rawContent: String, wrapToken: Bool) -> [String] {
        var results: [String] = []
        var seen = Set<String>()

        let attrPatterns = [
            #"data-original=["']([^"']+)["']"#,
            #"data-src=["']([^"']+)["']"#,
            #"data-lazy=["']([^"']+)["']"#,
            #"data-echo=["']([^"']+)["']"#,
            #"data-img=["']([^"']+)["']"#,
            #"data-url=["']([^"']+)["']"#,
            #"src=["']([^"']+)["']"#
        ]

        let imgTagPattern = #"<img\s+([^>]+)>"#
        if let imgRegex = try? NSRegularExpression(pattern: imgTagPattern, options: [.caseInsensitive]) {
            let nsText = rawContent as NSString
            let matches = imgRegex.matches(in: rawContent, options: [], range: NSRange(location: 0, length: nsText.length))

            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let attributesString = nsText.substring(with: match.range(at: 1))
                if let url = firstMatch(in: attributesString, patterns: attrPatterns),
                   let normalized = normalizeUrlCandidate(url),
                   isLikelyImageUrl(normalized) {
                    append(normalized, wrapToken: wrapToken, results: &results, seen: &seen)
                }
            }
        }

        let tokenPattern = #"__IMG__(\S+)"#
        if let regex = try? NSRegularExpression(pattern: tokenPattern, options: []) {
            let nsText = rawContent as NSString
            let matches = regex.matches(in: rawContent, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let url = nsText.substring(with: match.range(at: 1))
                if let normalized = normalizeUrlCandidate(url),
                   isLikelyImageUrl(normalized) {
                    append(normalized, wrapToken: wrapToken, results: &results, seen: &seen)
                }
            }
        }

        if results.isEmpty || results.count < minExpectedImageCount {
            let fallbackText = normalizeEscapedText(rawContent)
            let patterns = [
                #"https?://[^\s"'<>]+(?:\?|&)(?:sign|t)=[^\s"'<>]+"#,
                #"https?://[^\s"'<>]+(?:\.(?:jpg|jpeg|png|webp|gif|bmp))(?:\?[^\"'\s<>]*)?"#
            ]
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    let nsText = fallbackText as NSString
                    let matches = regex.matches(in: fallbackText, options: [], range: NSRange(location: 0, length: nsText.length))
                    for match in matches {
                        let url = nsText.substring(with: match.range(at: 0))
                        if let normalized = normalizeUrlCandidate(url),
                           isLikelyImageUrl(normalized) {
                            append(normalized, wrapToken: wrapToken, results: &results, seen: &seen)
                        }
                    }
                }
            }
        }

        return results
    }

    private static func firstMatch(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let attrRegex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let nsText = text as NSString
                if let match = attrRegex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)),
                   match.numberOfRanges > 1 {
                    return nsText.substring(with: match.range(at: 1))
                }
            }
        }
        return nil
    }

    private static func normalizeUrlCandidate(_ url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let replaced = trimmed.replacingOccurrences(of: "&amp;", with: "&")
        return replaced
    }

    private static func normalizeEscapedText(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u003F", with: "?")
            .replacingOccurrences(of: "\\u0026", with: "&")
    }

    private static func isLikelyImageUrl(_ url: String) -> Bool {
        let lower = url.lowercased()
        if lower.contains("sign=") { return true }
        let suffixes = [".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"]
        return suffixes.contains { lower.contains($0) }
    }

    private static func append(_ url: String, wrapToken: Bool, results: inout [String], seen: inout Set<String>) {
        guard !seen.contains(url) else { return }
        seen.insert(url)
        results.append(wrapToken ? "__IMG__" + url : url)
    }
}
