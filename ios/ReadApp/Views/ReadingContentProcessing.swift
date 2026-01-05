import SwiftUI
import Foundation

// MARK: - Content Processing
extension ReadingView {
    func updateProcessedContent(from rawText: String) {
        let processedContent = applyReplaceRules(to: rawText)
        let trimmedContent = processedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEffectivelyEmpty = trimmedContent.isEmpty
        let content = isEffectivelyEmpty ? "章节内容为空" : processedContent
        currentContent = content
        contentSentences = splitIntoParagraphs(content)
        updateMangaModeState() // 更新模式

        if shouldApplyResumeOnce && !didApplyResumePos {
            applyResumeProgressIfNeeded(sentences: contentSentences)
            shouldApplyResumeOnce = false
        }
    }

    func applyReplaceRules(to content: String) -> String {
        var processedContent = content
        for rule in replaceRuleViewModel.rules where rule.isEnabled == true {
            if let regex = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) {
                processedContent = regex.stringByReplacingMatches(in: processedContent, range: NSRange(location: 0, length: processedContent.utf16.count), withTemplate: rule.replacement)
            }
        }
        return processedContent
    }

    func applyResumeProgressIfNeeded(sentences: [String]) {
        guard !didApplyResumePos else { return }
        let hasLocalResume = pendingResumeLocalBodyIndex != nil && pendingResumeLocalChapterIndex == currentChapterIndex
        let pos = pendingResumePos ?? 0
        if !hasLocalResume && pos <= 0 { return }

        let chapterTitle = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : nil
        let prefixLen = (chapterTitle?.isEmpty ?? true) ? 0 : (chapterTitle! + "\n").utf16.count
        let paragraphStarts = TextKitPaginator.paragraphStartIndices(sentences: sentences)
        let bodyLength = (paragraphStarts.last ?? 0) + (sentences.last?.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count ?? 0)
        guard bodyLength > 0 else { return }

        let bodyIndex: Int
        if let localIndex = pendingResumeLocalBodyIndex, pendingResumeLocalChapterIndex == currentChapterIndex {
            bodyIndex = localIndex
            pendingResumeLocalBodyIndex = nil; pendingResumeLocalChapterIndex = nil; pendingResumeLocalPageIndex = nil
        } else {
            bodyIndex = pos > 1.0 ? Int(pos) : Int(Double(bodyLength) * min(max(pos, 0.0), 1.0))
        }
        let clampedBodyIndex = max(0, min(bodyIndex, max(0, bodyLength - 1)))
        pendingResumeCharIndex = clampedBodyIndex + prefixLen
        lastTTSSentenceIndex = paragraphStarts.lastIndex(where: { $0 <= clampedBodyIndex }) ?? 0
        pendingScrollToSentenceIndex = lastTTSSentenceIndex
        handlePendingScroll()
        didApplyResumePos = true
    }

    func presentReplaceRuleEditor(selectedText: String) {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let shortName = trimmed.count > 12 ? String(trimmed.prefix(12)) + "..." : trimmed
        pendingReplaceRule = ReplaceRule(id: nil, name: "正文净化-\(shortName)", groupname: "", pattern: NSRegularExpression.escapedPattern(for: trimmed), replacement: "", scope: book.name ?? "", scopeTitle: false, scopeContent: true, excludeScope: "", isEnabled: true, isRegex: true, timeoutMillisecond: 3000, ruleorder: 0)
        showAddReplaceRule = true
    }

    func removeHTMLAndSVG(_ text: String) -> String {
        if preferences.isVerboseLoggingEnabled {
            logger.log("开始处理内容，原始长度: \(text.count)", category: "漫画调试")
        }

        var result = text
        // 移除干扰标签
        result = result.replacingOccurrences(of: "<script[^>]*>.*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: "<style[^>]*>.*?</style>", with: "", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: "<svg[^>]*>.*?</svg>", with: "", options: [.regularExpression, .caseInsensitive])

        // 1. 使用较宽松的正则提取所有 src
        let imgPattern = "<img[^>]+(?:src|data-src)\\s*=\\s*[\"']?([^\"'\\s>]+)[\"']?[^>]*>"

        if let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))

            // 倒序替换，防止偏移量失效
            for match in matches.reversed() {
                if let urlRange = Range(match.range(at: 1), in: result) {
                    let url = String(result[urlRange])

                    // 2. 严格过滤：排除网页链接，保留图片链接
                    let lowerUrl = url.lowercased()
                    let isWebPage = lowerUrl.contains("/mobile/comics/") || lowerUrl.contains("/chapter/") || lowerUrl.contains("/comics/")
                    let isImageHost = lowerUrl.contains("image") || lowerUrl.contains("img") || lowerUrl.contains("tn1")
                    let isImageExt = lowerUrl.contains(".webp") || lowerUrl.contains(".jpg") || lowerUrl.contains(".png") || lowerUrl.contains(".jpeg") || lowerUrl.contains(".gif")

                    // 特殊逻辑：如果是主站域名但完全不含 image/img/tn1 标识，且没有图片后缀，基本确定是网页
                    let isKuaikanPage = lowerUrl.contains("kuaikanmanhua.com") && !isImageHost && !isImageExt

                    if !isWebPage && !isKuaikanPage && (isImageExt || url.contains("?")) {
                        // 有效图片：替换为占位符
                        if let fullRange = Range(match.range, in: result) {
                            result.replaceSubrange(fullRange, with: "\n__IMG__\(url)\n")
                        }
                    } else {
                        // 无效图片/网页链接：直接删除该标签
                        if let fullRange = Range(match.range, in: result) {
                            result.removeSubrange(fullRange)
                        }
                    }
                }
            }

            if preferences.isVerboseLoggingEnabled {
                logger.log("完成图片标签清洗，保留了有效的图片占位符", category: "漫画调试")
            }
        }

        // 移除所有其他 HTML 标签
        result = result.replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)

        return result
    }

    func splitIntoParagraphs(_ text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        var finalParagraphs: [String] = []

        // 启发式判断：如果全文包含图片且文本较少，极可能是漫画，开启更强过滤
        let likelyManga = text.contains("__IMG__") && text.count < 5000

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // 过滤：如果一段内容仅仅是 URL 且没有识别标记，说明是 HTML 剥离后的杂质
            let lowerTrimmed = trimmed.lowercased()
            let isRawUrl = lowerTrimmed.hasPrefix("http") || lowerTrimmed.hasPrefix("//")
            // 高熵文本拦截：很长的连续字母数字串（无空格）通常是杂质
            // 在可能为漫画的章节中，开启更严格的拦截（长度 > 30 且无空格）
            let isHighEntropy = likelyManga && trimmed.count > 30 && !trimmed.contains(" ")

            if (isRawUrl || isHighEntropy) && !trimmed.contains("__IMG__") {
                continue
            }

            // 进一步拆分，确保 __IMG__ 独立成行
            let parts = trimmed.components(separatedBy: "__IMG__")
            if parts.count > 1 {
                for (i, part) in parts.enumerated() {
                    let p = part.trimmingCharacters(in: .whitespaces)
                    if i == 0 {
                        if !p.isEmpty { finalParagraphs.append(p) }
                    } else {
                        let urlAndText = part
                        let urlParts = urlAndText.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
                        let url = String(urlParts[0]).trimmingCharacters(in: .whitespaces)
                        if !url.isEmpty { finalParagraphs.append("__IMG__" + url) }
                        if urlParts.count > 1 {
                            let remaining = String(urlParts[1]).trimmingCharacters(in: .whitespaces)
                            if !remaining.isEmpty { finalParagraphs.append(remaining) }
                        }
                    }
                }
            } else {
                finalParagraphs.append(trimmed)
            }
        }
        return finalParagraphs
    }
}
