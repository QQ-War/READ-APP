import UIKit

final class ReaderChapterBuilder {
    private var readerSettings: ReaderSettingsStore
    private var replaceRules: [ReplaceRule]?

    init(readerSettings: ReaderSettingsStore, replaceRules: [ReplaceRule]?) {
        self.readerSettings = readerSettings
        self.replaceRules = replaceRules
    }

    func updateSettings(_ settings: ReaderSettingsStore) {
        self.readerSettings = settings
    }

    func updateReplaceRules(_ rules: [ReplaceRule]?) {
        self.replaceRules = rules
    }

    func buildTextCache(
        rawContent: String,
        title: String,
        layoutSpec: ReaderLayoutSpec,
        reuseStore: TextKit2RenderStore?,
        chapterUrl: String? = nil,
        anchorOffset: Int = 0 // 新增锚点支持
    ) -> ChapterCache {
        let chunkLimit = UserPreferences.shared.ttsSentenceChunkLimit
        let sentences = ReadingTextProcessor.splitSentences(rawContent, rules: replaceRules, chunkLimit: chunkLimit)
        let attr = buildAttributedText(sentences: sentences, title: title)
        let width = max(100, layoutSpec.pageSize.width - layoutSpec.sideMargin * 2)
        let store: TextKit2RenderStore
        if let reuseStore = reuseStore {
            reuseStore.update(attributedString: attr, layoutWidth: width)
            store = reuseStore
        } else {
            store = TextKit2RenderStore(attributedString: attr, layoutWidth: width)
        }

        let prefixLen = title.isEmpty ? 0 : (title + "\n").utf16.count
        let paragraphStarts = paragraphStarts(for: sentences, prefixLen: prefixLen)
        
        // 使用新增的锚点分页方法
        let result = TextKit2Paginator.paginateFromAnchor(
            anchorOffset: anchorOffset,
            renderStore: store,
            pageSize: layoutSpec.pageSize,
            paragraphStarts: paragraphStarts,
            prefixLen: prefixLen,
            topInset: layoutSpec.topInset,
            bottomInset: layoutSpec.bottomInset
        )

        return ChapterCache(
            pages: result.pages,
            renderStore: store,
            pageInfos: result.pageInfos,
            contentSentences: sentences,
            rawContent: rawContent,
            attributedText: attr,
            paragraphStarts: paragraphStarts,
            chapterPrefixLen: prefixLen,
            isFullyPaginated: true,
            chapterUrl: chapterUrl,
            anchorPageIndex: result.anchorPageIndex
        )
    }

    func buildMangaCache(rawContent: String, chapterUrl: String? = nil) -> ChapterCache {
        let sentences = buildMangaSentences(rawContent: rawContent)
        return ChapterCache(
            pages: [],
            renderStore: nil,
            pageInfos: nil,
            contentSentences: sentences,
            rawContent: rawContent,
            attributedText: NSAttributedString(),
            paragraphStarts: [],
            chapterPrefixLen: 0,
            isFullyPaginated: false,
            chapterUrl: chapterUrl,
            anchorPageIndex: 0
        )
    }

    func buildMangaSentences(rawContent: String) -> [String] {
        let images = extractMangaImageSentences(from: rawContent)
        if !images.isEmpty { return images }
        let sanitized = stripHTMLAndSVG(rawContent)
        return sanitized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func buildAttributedText(sentences: [String], title: String) -> NSAttributedString {
        let fullAttr = NSMutableAttributedString()
        if !title.isEmpty {
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .center
            titleStyle.paragraphSpacing = readerSettings.fontSize * 1.5
            fullAttr.append(
                NSAttributedString(
                    string: title + "\n",
                    attributes: [
                        .font: UIFont.systemFont(ofSize: readerSettings.fontSize + 8, weight: .bold),
                        .foregroundColor: UIColor.label,
                        .paragraphStyle: titleStyle
                    ]
                )
            )
        }

        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineSpacing = readerSettings.lineSpacing
        bodyStyle.alignment = .justified

        let indentedText = sentences.map { String(repeating: "　", count: paragraphIndentLength) + $0 }.joined(separator: "\n")
        fullAttr.append(
            NSAttributedString(
                string: indentedText,
                attributes: [
                    .font: UIFont.systemFont(ofSize: readerSettings.fontSize),
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: bodyStyle
                ]
            )
        )
        return fullAttr
    }

    private func paragraphStarts(for sentences: [String], prefixLen: Int) -> [Int] {
        var starts: [Int] = []
        var current = prefixLen
        for (idx, sentence) in sentences.enumerated() {
            starts.append(current)
            current += (sentence.utf16.count + paragraphIndentLength)
            if idx < sentences.count - 1 {
                current += 1
            }
        }
        return starts
    }

    private func stripHTMLAndSVG(_ text: String) -> String {
        var result = text
        let patterns = ["<svg[^>]*>.*?</svg>", "<img[^>]*>", "<[^>]+>"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
            }
        }
        return result.replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private func extractMangaImageSentences(from text: String) -> [String] {
        return MangaImageExtractor.extractImageTokens(from: text)
    }
}
