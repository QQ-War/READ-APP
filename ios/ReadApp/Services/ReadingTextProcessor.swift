import Foundation

struct ReadingTextProcessor {
    static func prepareText(_ text: String, rules: [ReplaceRule]?) -> String {
        let stripped = stripHTMLAndSVG(text)
        return applyReplaceRules(to: stripped, rules: rules)
    }

    static func splitSentences(_ text: String, rules: [ReplaceRule]?) -> [String] {
        let processed = prepareText(text, rules: rules)
        let lines = processed.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.flatMap { splitIntoChunks($0, limit: 1800) }
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
