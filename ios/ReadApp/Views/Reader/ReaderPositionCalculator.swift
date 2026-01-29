import Foundation

enum ReaderPositionCalculator {
    struct TTSPagePositionContext {
        let readingMode: ReadingMode
        let currentChapterIndex: Int
        let paragraphStarts: [Int]
        let pageInfos: [TK2PageInfo]
        let paragraphIndentLength: Int
        let horizontalPageIndexForDisplay: () -> Int
        let newHorizontalCurrentPageIndex: () -> Int
        let isSentenceVisibleInVertical: (_ index: Int) -> Bool
    }

    struct TTSPagePositionSource {
        let readingMode: ReadingMode
        let currentChapterIndex: Int
        let paragraphStarts: [Int]
        let pageInfos: [TK2PageInfo]
        let paragraphIndentLength: Int
        let horizontalPageIndexForDisplay: () -> Int
        let newHorizontalCurrentPageIndex: () -> Int
        let isSentenceVisibleInVertical: (_ index: Int) -> Bool

        func makeContext() -> TTSPagePositionContext {
            TTSPagePositionContext(
                readingMode: readingMode,
                currentChapterIndex: currentChapterIndex,
                paragraphStarts: paragraphStarts,
                pageInfos: pageInfos,
                paragraphIndentLength: paragraphIndentLength,
                horizontalPageIndexForDisplay: horizontalPageIndexForDisplay,
                newHorizontalCurrentPageIndex: newHorizontalCurrentPageIndex,
                isSentenceVisibleInVertical: isSentenceVisibleInVertical
            )
        }
    }

    struct StartPositionContext {
        let readingMode: ReadingMode
        let currentCache: ChapterCache
        let currentChapterIndex: Int
        let currentPageIndex: Int
        let paragraphIndentLength: Int
        let horizontalPageIndexForDisplay: () -> Int
        let newHorizontalCurrentPageIndex: () -> Int
        let verticalCharOffset: () -> Int
        let verticalLastReportedIndex: () -> Int
    }

    static func currentStartPosition(
        context: StartPositionContext
    ) -> ReadingPosition {
        let readingMode = context.readingMode
        let currentCache = context.currentCache
        let currentChapterIndex = context.currentChapterIndex
        let currentPageIndex = context.currentPageIndex
        let paragraphIndentLength = context.paragraphIndentLength

        guard !currentCache.contentSentences.isEmpty else {
            return ReadingPosition(chapterIndex: currentChapterIndex, sentenceIndex: 0, sentenceOffset: 0, charOffset: 0)
        }
        let pageInfos = currentCache.pageInfos ?? []
        let starts = currentCache.paragraphStarts
        guard !starts.isEmpty else {
            return ReadingPosition(chapterIndex: currentChapterIndex, sentenceIndex: 0, sentenceOffset: 0, charOffset: 0)
        }

        var charOffset: Int = 0
        var sentenceIndex: Int = 0

        if readingMode == .horizontal || readingMode == .newHorizontal {
            let pageIndex = readingMode == .newHorizontal ? context.newHorizontalCurrentPageIndex() : context.horizontalPageIndexForDisplay()
            if pageIndex < pageInfos.count {
                let pageInfo = pageInfos[pageIndex]
                charOffset = pageInfo.range.location
                sentenceIndex = starts.lastIndex(where: { $0 <= charOffset }) ?? 0
            }
        } else if readingMode == .vertical {
            charOffset = context.verticalCharOffset()
            if charOffset < 0 {
                let fallbackIndex = max(0, context.verticalLastReportedIndex())
                sentenceIndex = min(fallbackIndex, starts.count - 1)
                charOffset = starts[sentenceIndex]
            } else {
                sentenceIndex = starts.lastIndex(where: { $0 <= charOffset }) ?? 0
            }
        }

        sentenceIndex = max(0, min(sentenceIndex, currentCache.contentSentences.count - 1))
        let sentenceStart = starts[sentenceIndex]
        let intra = max(0, charOffset - sentenceStart - paragraphIndentLength)
        let maxLen = currentCache.contentSentences[sentenceIndex].utf16.count
        let offsetInSentence = min(maxLen, intra)

        return ReadingPosition(
            chapterIndex: currentChapterIndex,
            sentenceIndex: sentenceIndex,
            sentenceOffset: offsetInSentence,
            charOffset: charOffset
        )
    }

    static func isTTSPositionInCurrentPage(
        context: TTSPagePositionContext,
        isReadingChapterTitle: Bool,
        hasChapterTitleInSentences: Bool,
        sentenceIndex: Int,
        sentenceOffset: Int
    ) -> Bool {
        if context.readingMode == .vertical {
            return context.isSentenceVisibleInVertical(sentenceIndex)
        }
        if isReadingChapterTitle {
            return context.horizontalPageIndexForDisplay() == 0
        }
        let pageIndex = context.readingMode == .newHorizontal ? context.newHorizontalCurrentPageIndex() : context.horizontalPageIndexForDisplay()
        guard pageIndex < context.pageInfos.count else { return true }
        let bodySentenceIdx = hasChapterTitleInSentences ? (sentenceIndex - 1) : sentenceIndex
        guard bodySentenceIdx >= 0 && bodySentenceIdx < context.paragraphStarts.count else { return false }
        let totalOffset = context.paragraphStarts[bodySentenceIdx] + sentenceOffset + context.paragraphIndentLength
        return NSLocationInRange(totalOffset, context.pageInfos[pageIndex].range)
    }
}
