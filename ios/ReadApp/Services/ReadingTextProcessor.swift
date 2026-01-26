import Foundation

struct ReadingTextProcessor {
    enum Segment {
        case text(String)
        case image(String)
    }

    static let imagePlaceholder = "\u{FFFC}"

    static func prepareText(_ text: String, rules: [ReplaceRule]?) -> String {
        let stripped = stripHTMLAndSVG(text)
        return applyReplaceRules(to: stripped, rules: rules)
    }

    static func splitSentences(_ text: String, rules: [ReplaceRule]?, chunkLimit: Int) -> [String] {
        let segments = splitSegments(text, rules: rules, chunkLimit: chunkLimit)
        return segments.map { segment in
            switch segment {
            case .text(let value): return value
            case .image: return imagePlaceholder
            }
        }
    }

    static func splitSegments(_ text: String, rules: [ReplaceRule]?, chunkLimit: Int) -> [Segment] {
        let processed = stripHTMLAndSVG(replaceImgTagsWithTokens(text))
        let lines = processed.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var segments: [Segment] = []
        for line in lines {
            if line.hasPrefix("__IMG__") {
                let url = String(line.dropFirst("__IMG__".count))
                if !url.isEmpty {
                    segments.append(.image(url))
                }
                continue
            }

            let applied = applyReplaceRules(to: line, rules: rules)
            let chunks = splitIntoChunks(applied, limit: chunkLimit)
            for chunk in chunks where !chunk.isEmpty {
                segments.append(.text(chunk))
            }
        }
        return segments
    }

    private static func splitIntoChunks(_ text: String, limit: Int) -> [String] {
        guard !text.isEmpty else { return [] }
        guard text.utf16.count > limit else { return [text] }

        var chunks: [String] = []
        var remaining = text
        let breakCharacters: Set<Character> = [" ", "，", "。", "！", "？", "、", ",", ".", "!", "?"]

        while remaining.utf16.count > limit {
            let limitIndex = remaining.index(remaining.startIndex, offsetBy: limit, limitedBy: remaining.endIndex) ?? remaining.endIndex
            var splitIndex = limitIndex
            while splitIndex > remaining.startIndex {
                let prevIndex = remaining.index(before: splitIndex)
                let char = remaining[prevIndex]
                if breakCharacters.contains(char) {
                    splitIndex = remaining.index(after: prevIndex)
                    break
                }
                splitIndex = prevIndex
            }

            if splitIndex == remaining.startIndex {
                splitIndex = limitIndex
            }

            let chunk = remaining[..<splitIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(String(chunk))
            }
            remaining = remaining[splitIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !remaining.isEmpty {
            chunks.append(remaining)
        }
        return chunks
    }

    private static func applyReplaceRules(to text: String, rules: [ReplaceRule]?) -> String {
        guard let rules = rules else { return text }
        var result = text
        for rule in rules where rule.isEnabled == true {
            if rule.isRegex == true {
                if let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                    result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: rule.replacement)
                }
            } else {
                result = result.replacingOccurrences(of: rule.pattern, with: rule.replacement)
            }
        }
        return result
    }

    private static func replaceImgTagsWithTokens(_ text: String) -> String {
        let imgTagPattern = #"<img\s+[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: imgTagPattern, options: [.caseInsensitive]) else {
            return text
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var lastIndex = 0
        for match in matches {
            let range = match.range(at: 0)
            if range.location > lastIndex {
                result += nsText.substring(with: NSRange(location: lastIndex, length: range.location - lastIndex))
            }
            let tag = nsText.substring(with: range)
            if let url = extractFirstImageUrl(fromImgTag: tag) {
                result += "\n__IMG__\(url)\n"
            }
            lastIndex = range.location + range.length
        }
        if lastIndex < nsText.length {
            result += nsText.substring(from: lastIndex)
        }
        return result
    }

    private static func extractFirstImageUrl(fromImgTag tag: String) -> String? {
        let attrPatterns = [
            #"data-original=["']([^"']+)["']"#,
            #"data-src=["']([^"']+)["']"#,
            #"data-lazy=["']([^"']+)["']"#,
            #"data-echo=["']([^"']+)["']"#,
            #"data-img=["']([^"']+)["']"#,
            #"data-url=["']([^"']+)["']"#,
            #"src=["']([^"']+)["']"#
        ]
        for pattern in attrPatterns {
            if let attrRegex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let nsText = tag as NSString
                if let match = attrRegex.firstMatch(in: tag, options: [], range: NSRange(location: 0, length: nsText.length)),
                   match.numberOfRanges > 1 {
                    let url = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !url.isEmpty {
                        return url.replacingOccurrences(of: "&amp;", with: "&")
                    }
                }
            }
        }
        return nil
    }

    private static func stripHTMLAndSVG(_ text: String) -> String {
        var result = text
        let patterns = ["<svg[^>]*>.*?</svg>", "<img[^>]*>", "<[^>]+>"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
            }
        }
        return result.replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
