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
        let segments = ReadingTextProcessor.splitSegments(rawContent, rules: replaceRules, chunkLimit: chunkLimit)
        let built = buildAttributedText(segments: segments, title: title, layoutWidth: layoutSpec.pageSize.width - layoutSpec.sideMargin * 2)
        let sentences = built.sentences
        let attr = built.attributedText
        let width = max(100, layoutSpec.pageSize.width - layoutSpec.sideMargin * 2)
        let store: TextKit2RenderStore
        if let reuseStore = reuseStore {
            reuseStore.update(attributedString: attr, layoutWidth: width)
            store = reuseStore
        } else {
            store = TextKit2RenderStore(attributedString: attr, layoutWidth: width)
        }

        let prefixLen = built.prefixLen
        let paragraphStarts = built.paragraphStarts
        
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
        buildAttributedText(segments: sentences.map { .text($0) }, title: title, layoutWidth: 0).attributedText
    }

    private func buildAttributedText(segments: [ReadingTextProcessor.Segment], title: String, layoutWidth: CGFloat) -> (attributedText: NSAttributedString, paragraphStarts: [Int], sentences: [String], prefixLen: Int) {
        let fullAttr = NSMutableAttributedString()
        var paragraphStarts: [Int] = []
        var sentences: [String] = []

        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineSpacing = readerSettings.lineSpacing
        bodyStyle.alignment = .justified

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: ReaderFontProvider.bodyFont(size: readerSettings.fontSize),
            .foregroundColor: readerSettings.readingTheme.textColor,
            .paragraphStyle: bodyStyle
        ]

        if !title.isEmpty {
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .center
            titleStyle.paragraphSpacing = readerSettings.fontSize * 1.5
            fullAttr.append(
                NSAttributedString(
                    string: title + "\n",
                    attributes: [
                        .font: ReaderFontProvider.titleFont(size: readerSettings.fontSize + 8),
                        .foregroundColor: readerSettings.readingTheme.textColor,
                        .paragraphStyle: titleStyle
                    ]
                )
            )
        }
        let prefixLen = fullAttr.length

        var currentOffset = prefixLen
        let indent = String(repeating: "　", count: paragraphIndentLength)
        for segment in segments {
            paragraphStarts.append(currentOffset)
            switch segment {
            case .text(let value):
                sentences.append(value)
                let paragraph = indent + value
                fullAttr.append(NSAttributedString(string: paragraph, attributes: bodyAttributes))
                currentOffset += paragraph.utf16.count
            case .image(let urlString):
                sentences.append(ReadingTextProcessor.imagePlaceholder)
                fullAttr.append(NSAttributedString(string: indent, attributes: bodyAttributes))
                currentOffset += indent.utf16.count
                if let url = URL(string: urlString) {
                    let attachment = InlineImageAttachment(imageURL: url, maxWidth: max(100, layoutWidth))
                    fullAttr.append(NSAttributedString(attachment: attachment))
                } else {
                    fullAttr.append(NSAttributedString(string: ReadingTextProcessor.imagePlaceholder, attributes: bodyAttributes))
                }
                currentOffset += 1
            }
            fullAttr.append(NSAttributedString(string: "\n", attributes: bodyAttributes))
            currentOffset += 1
        }

        return (fullAttr, paragraphStarts, sentences, prefixLen)
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
