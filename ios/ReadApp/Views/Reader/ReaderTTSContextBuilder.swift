import Foundation

enum ReaderTTSContextBuilder {
    static func makeSyncContext(
        isMangaMode: Bool,
        currentReadingMode: ReadingMode,
        isInfiniteScrollEnabled: Bool,
        currentChapterIndex: Int,
        currentChapterUrl: String?,
        nextCacheHasRenderStore: Bool,
        chapters: [BookChapter],
        currentCache: ChapterCache,
        currentPageIndex: Int,
        newHorizontalCurrentPageIndex: @escaping () -> Int,
        horizontalPageIndexForDisplay: @escaping () -> Int,
        verticalIsSentenceVisible: @escaping (Int) -> Bool,
        verticalEnsureSentenceVisible: @escaping (Int) -> Void,
        verticalSetHighlight: @escaping (Int?, Set<Int>, Bool, NSRange?) -> Void,
        newHorizontalSetHighlight: @escaping (Int?, Set<Int>, Bool, NSRange?) -> Void,
        horizontalSetHighlight: @escaping (Int?, Set<Int>, Bool, NSRange?) -> Void,
        scrollNewHorizontal: @escaping (Int, Bool) -> Void,
        scrollHorizontal: @escaping (Int, Bool) -> Void,
        requestChapterSwitchSeamless: @escaping (_ offset: Int) -> Void,
        paragraphIndentLength: Int
    ) -> ReaderTTSBridge.SyncContext {
        ReaderTTSBridge.SyncContextBuilderSource(
            isMangaMode: isMangaMode,
            currentReadingMode: currentReadingMode,
            isInfiniteScrollEnabled: isInfiniteScrollEnabled,
            currentChapterIndex: currentChapterIndex,
            currentChapterUrl: currentChapterUrl,
            nextCacheHasRenderStore: nextCacheHasRenderStore,
            chapters: chapters,
            currentCache: currentCache,
            currentPageIndex: currentPageIndex,
            newHorizontalCurrentPageIndex: newHorizontalCurrentPageIndex,
            horizontalPageIndexForDisplay: horizontalPageIndexForDisplay,
            verticalIsSentenceVisible: verticalIsSentenceVisible,
            verticalEnsureSentenceVisible: verticalEnsureSentenceVisible,
            verticalSetHighlight: verticalSetHighlight,
            newHorizontalSetHighlight: newHorizontalSetHighlight,
            horizontalSetHighlight: horizontalSetHighlight,
            scrollNewHorizontal: scrollNewHorizontal,
            scrollHorizontal: scrollHorizontal,
            requestChapterSwitchSeamless: requestChapterSwitchSeamless,
            paragraphIndentLength: paragraphIndentLength
        ).build()
    }
}
