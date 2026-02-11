import Foundation

final class ReaderTTSBridge {
    struct SyncContext {
        let isMangaMode: Bool
        let currentReadingMode: ReadingMode
        let isInfiniteScrollEnabled: Bool
        let currentChapterIndex: Int
        let currentChapterUrl: String?
        let nextCacheHasRenderStore: Bool
        let chapters: [BookChapter]
        let currentCache: ChapterCache
        let currentPageIndex: Int
        let newHorizontalCurrentPageIndex: () -> Int
        let horizontalPageIndexForDisplay: () -> Int
        let verticalIsSentenceVisible: (Int) -> Bool
        let verticalEnsureSentenceVisible: (Int) -> Void
        let verticalSetHighlight: (Int?, Set<Int>, Bool, NSRange?) -> Void
        let newHorizontalSetHighlight: (Int?, Set<Int>, Bool, NSRange?) -> Void
        let horizontalSetHighlight: (Int?, Set<Int>, Bool, NSRange?) -> Void
        let scrollNewHorizontal: (Int, Bool) -> Void
        let scrollHorizontal: (Int, Bool) -> Void
        let requestChapterSwitchSeamless: (_ offset: Int) -> Void
        let paragraphIndentLength: Int
    }

    struct RestartContext {
        let currentChapterIndex: Int
        let chaptersCount: Int
        let startPosition: () -> ReadingPosition
        let startReading: (_ position: ReadingPosition) -> Void
    }

    struct StartContext {
        let text: String
        let sentences: [String]
        let chapters: [BookChapter]
        let currentIndex: Int
        let bookUrl: String
        let bookSourceUrl: String
        let bookTitle: String
        let coverUrl: String?
        let replaceRules: [ReplaceRule]?
        let textProcessor: (String) -> String
        let shouldSpeakChapterTitle: Bool
    }

    struct ChapterChangeStrategy {
        let handleChange: (_ newIndex: Int) -> Void
    }

    struct ChapterChangeBuilderSource {
        let currentReadingMode: ReadingMode
        let currentChapterIndex: () -> Int
        let isInfiniteScrollEnabled: () -> Bool
        let hasNextHorizontalPages: () -> Bool
        let hasPrevHorizontalPages: () -> Bool
        let prevHorizontalPageCount: () -> Int
        let animateToAdjacent: (_ offset: Int, _ targetPage: Int) -> Void
        let requestChapterSwitch: (_ index: Int) -> Void
        let requestChapterSwitchSeamless: (_ offset: Int) -> Void
        let suppressFollow: () -> Void

        func build() -> ChapterChangeStrategy {
            ChapterChangeStrategy { newIndex in
                let currentIndex = currentChapterIndex()
                if currentReadingMode == .horizontal && newIndex == currentIndex + 1 && hasNextHorizontalPages() {
                    animateToAdjacent(1, 0)
                    return
                }
                if currentReadingMode == .horizontal && newIndex == currentIndex - 1 && hasPrevHorizontalPages() {
                    animateToAdjacent(-1, max(0, prevHorizontalPageCount() - 1))
                    return
                }
                if currentReadingMode == .vertical && isInfiniteScrollEnabled() {
                    let offset = newIndex - currentIndex
                    suppressFollow()
                    requestChapterSwitchSeamless(offset)
                    return
                }
                requestChapterSwitch(newIndex)
            }
        }
    }

    struct SyncContextBuilderSource {
        let isMangaMode: Bool
        let currentReadingMode: ReadingMode
        let isInfiniteScrollEnabled: Bool
        let currentChapterIndex: Int
        let currentChapterUrl: String?
        let nextCacheHasRenderStore: Bool
        let chapters: [BookChapter]
        let currentCache: ChapterCache
        let currentPageIndex: Int
        let newHorizontalCurrentPageIndex: () -> Int
        let horizontalPageIndexForDisplay: () -> Int
        let verticalIsSentenceVisible: (Int) -> Bool
        let verticalEnsureSentenceVisible: (Int) -> Void
        let verticalSetHighlight: (Int?, Set<Int>, Bool, NSRange?) -> Void
        let newHorizontalSetHighlight: (Int?, Set<Int>, Bool, NSRange?) -> Void
        let horizontalSetHighlight: (Int?, Set<Int>, Bool, NSRange?) -> Void
        let scrollNewHorizontal: (Int, Bool) -> Void
        let scrollHorizontal: (Int, Bool) -> Void
        let requestChapterSwitchSeamless: (_ offset: Int) -> Void
        let paragraphIndentLength: Int

        func build() -> SyncContext {
            SyncContext(
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
            )
        }
    }

    private(set) var isUserInteracting = false
    private var pendingPositionSync = false
    private var suppressFollowUntil: TimeInterval = 0

    private let followCooldown: () -> TimeInterval
    private let scheduleCatchUp: (_ delay: TimeInterval) -> Void

    init(
        followCooldown: @escaping () -> TimeInterval,
        scheduleCatchUp: @escaping (_ delay: TimeInterval) -> Void
    ) {
        self.followCooldown = followCooldown
        self.scheduleCatchUp = scheduleCatchUp
    }

    func suppressFollow(for duration: TimeInterval) {
        suppressFollowUntil = Date().timeIntervalSince1970 + duration
    }

    func canFollow(now: TimeInterval) -> Bool {
        now >= suppressFollowUntil
    }

    func markUserNavigation() {
        suppressFollowUntil = Date().timeIntervalSince1970 + followCooldown()
    }

    func startUserInteraction() {
        isUserInteracting = true
        pendingPositionSync = true
        markUserNavigation()
    }

    func endUserInteraction() {
        guard isUserInteracting || pendingPositionSync else { return }
        isUserInteracting = false
        markUserNavigation()
        scheduleCatchUp(followCooldown())
    }

    func finalizeUserInteraction() {
        isUserInteracting = false
        markUserNavigation()
    }

    func requestPendingSync() {
        pendingPositionSync = true
    }

    func consumePendingSync() -> Bool {
        guard pendingPositionSync else { return false }
        pendingPositionSync = false
        return true
    }

    func hasPendingSync() -> Bool {
        pendingPositionSync
    }

    func syncState(ttsManager: TTSManager, context: SyncContext) {
        if context.isMangaMode { return }
        guard ttsManager.isReady else { return }

        if context.currentReadingMode == .vertical && context.isInfiniteScrollEnabled {
            if ttsManager.currentChapterIndex == context.currentChapterIndex + 1 && context.nextCacheHasRenderStore {
                let now = Date().timeIntervalSince1970
                if canFollow(now: now) {
                    suppressFollow(for: ReaderConstants.Interaction.ttsSuppressDuration)
                    context.requestChapterSwitchSeamless(1)
                    return
                }
            }
        }

        guard ttsManager.currentChapterIndex == context.currentChapterIndex else { return }
        if context.chapters.indices.contains(context.currentChapterIndex) {
            guard context.currentChapterUrl == context.chapters[context.currentChapterIndex].url else { return }
        }

        let sentenceIndex = ttsManager.currentSentenceIndex
        var highlightIdx: Int? = sentenceIndex
        var secondaryIdxs = Set(ttsManager.preloadedIndices)
        if ttsManager.hasChapterTitleInSentences {
            if ttsManager.isReadingChapterTitle {
                highlightIdx = nil
                secondaryIdxs = []
            } else {
                highlightIdx = sentenceIndex - 1
                secondaryIdxs = Set(ttsManager.preloadedIndices.compactMap { $0 > 0 ? ($0 - 1) : nil })
            }
        }

        if let hi = highlightIdx {
            secondaryIdxs = Set(secondaryIdxs.filter { $0 > hi })
        } else {
            secondaryIdxs = []
        }

        let highlightRange: NSRange?
        if let hi = highlightIdx,
           hi >= 0,
           hi < context.currentCache.contentSentences.count,
           !ttsManager.isReadingChapterTitle {
            highlightRange = Self.highlightRange(
                sentence: context.currentCache.contentSentences[hi],
                sentenceIndex: hi,
                sentenceOffset: ttsManager.currentSentenceOffset,
                paragraphStarts: context.currentCache.paragraphStarts,
                paragraphIndentLength: context.paragraphIndentLength,
                totalLength: context.currentCache.attributedText.length
            )
        } else {
            if let hi = highlightIdx, hi < 0 || hi >= context.currentCache.contentSentences.count {
                highlightIdx = nil
            }
            highlightRange = nil
        }

        if context.currentReadingMode == .vertical {
            context.verticalSetHighlight(highlightIdx, secondaryIdxs, ttsManager.isPlaying, highlightRange)
        } else if context.currentReadingMode == .newHorizontal {
            context.newHorizontalSetHighlight(highlightIdx, secondaryIdxs, ttsManager.isPlaying, highlightRange)
        } else if context.currentReadingMode == .horizontal {
            context.horizontalSetHighlight(highlightIdx, secondaryIdxs, ttsManager.isPlaying, highlightRange)
        }

        let now = Date().timeIntervalSince1970
        guard !isUserInteracting, ttsManager.isPlaying, canFollow(now: now) else { return }

        if context.currentReadingMode == .vertical {
            let isVisible = context.verticalIsSentenceVisible(sentenceIndex)
            if !isVisible {
                context.verticalEnsureSentenceVisible(sentenceIndex)
            } else {
                context.verticalEnsureSentenceVisible(sentenceIndex)
            }
        } else if context.currentReadingMode == .newHorizontal || context.currentReadingMode == .horizontal {
            if ttsManager.isReadingChapterTitle {
                if context.currentPageIndex != 0 {
                    if context.currentReadingMode == .newHorizontal {
                        context.scrollNewHorizontal(0, true)
                    } else {
                        context.scrollHorizontal(0, true)
                    }
                }
                return
            }

            let bodySentenceIdx = ttsManager.hasChapterTitleInSentences ? (sentenceIndex - 1) : sentenceIndex
            guard bodySentenceIdx >= 0 else { return }
            let sentenceOffset = ttsManager.currentSentenceOffset
            let starts = context.currentCache.paragraphStarts

            if bodySentenceIdx < starts.count {
                let realTimeOffset = starts[bodySentenceIdx] + sentenceOffset + context.paragraphIndentLength
                let currentIndex = context.currentReadingMode == .newHorizontal ? context.newHorizontalCurrentPageIndex() : context.horizontalPageIndexForDisplay()
                if currentIndex < context.currentCache.pages.count {
                    let currentRange = context.currentCache.pages[currentIndex].globalRange
                    if !NSLocationInRange(realTimeOffset, currentRange) {
                        if let targetPage = context.currentCache.pages.firstIndex(where: { NSLocationInRange(realTimeOffset, $0.globalRange) }) {
                            if targetPage != context.currentPageIndex {
                                if context.currentReadingMode == .newHorizontal {
                                    context.scrollNewHorizontal(targetPage, true)
                                } else {
                                    context.scrollHorizontal(targetPage, true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func restartFromCurrentPage(context: RestartContext) {
        guard context.currentChapterIndex < context.chaptersCount else { return }
        let startPos = context.startPosition()
        context.startReading(startPos)
    }

    func startReading(ttsManager: TTSManager, context: StartContext, startPos: ReadingPosition, chapterChange: ChapterChangeStrategy) {
        ttsManager.startReading(
            text: context.text,
            chapters: context.chapters,
            currentIndex: context.currentIndex,
            bookUrl: context.bookUrl,
            bookSourceUrl: context.bookSourceUrl,
            bookTitle: context.bookTitle,
            coverUrl: context.coverUrl,
            onChapterChange: { newIndex in chapterChange.handleChange(newIndex) },
            processedSentences: context.sentences,
            textProcessor: context.textProcessor,
            replaceRules: context.replaceRules,
            startAtSentenceIndex: startPos.sentenceIndex,
            startAtSentenceOffset: startPos.sentenceOffset,
            shouldSpeakChapterTitle: context.shouldSpeakChapterTitle
        )
    }

    static func highlightRange(
        sentence: String,
        sentenceIndex: Int,
        sentenceOffset: Int,
        paragraphStarts: [Int],
        paragraphIndentLength: Int,
        totalLength: Int
    ) -> NSRange? {
        let ns = sentence as NSString
        let len = ns.length
        if len == 0 { return nil }
        let offset = max(0, min(sentenceOffset, len - 1))

        func isDelimiter(_ c: unichar) -> Bool {
            switch c {
            case 0x3002, 0xFF01, 0xFF1F, 0xFF1B, 0x2026, 0x0021, 0x003F, 0x003B, 0x002E, 0x3001, 0xFF0C:
                return true
            default:
                return false
            }
        }

        var startInSentence = 0
        if offset > 0 {
            for i in stride(from: offset - 1, through: 0, by: -1) {
                if isDelimiter(ns.character(at: i)) {
                    startInSentence = i + 1
                    break
                }
            }
        }
        var endInSentence = len
        for i in offset..<len {
            if isDelimiter(ns.character(at: i)) {
                endInSentence = i + 1
                break
            }
        }

        if endInSentence <= startInSentence {
            startInSentence = 0
            endInSentence = len
        }

        guard sentenceIndex < paragraphStarts.count else { return nil }
        let sentenceStart = paragraphStarts[sentenceIndex] + paragraphIndentLength
        let absoluteStart = sentenceStart + startInSentence
        let absoluteLen = endInSentence - startInSentence
        guard absoluteStart < totalLength else { return nil }
        let clampedLen = min(absoluteLen, totalLength - absoluteStart)
        return NSRange(location: absoluteStart, length: max(1, clampedLen))
    }
}
