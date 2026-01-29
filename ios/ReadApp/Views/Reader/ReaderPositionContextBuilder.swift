import Foundation

enum ReaderPositionContextBuilder {
    static func makeTTSPagePositionContext(
        readingMode: ReadingMode,
        currentChapterIndex: Int,
        paragraphStarts: [Int],
        pageInfos: [TK2PageInfo],
        paragraphIndentLength: Int,
        horizontalPageIndexForDisplay: @escaping () -> Int,
        newHorizontalCurrentPageIndex: @escaping () -> Int,
        isSentenceVisibleInVertical: @escaping (_ index: Int) -> Bool
    ) -> ReaderPositionCalculator.TTSPagePositionContext {
        ReaderPositionCalculator.TTSPagePositionSource(
            readingMode: readingMode,
            currentChapterIndex: currentChapterIndex,
            paragraphStarts: paragraphStarts,
            pageInfos: pageInfos,
            paragraphIndentLength: paragraphIndentLength,
            horizontalPageIndexForDisplay: horizontalPageIndexForDisplay,
            newHorizontalCurrentPageIndex: newHorizontalCurrentPageIndex,
            isSentenceVisibleInVertical: isSentenceVisibleInVertical
        ).makeContext()
    }
}
