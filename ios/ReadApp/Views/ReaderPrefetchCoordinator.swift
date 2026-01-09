import Foundation

final class ReaderPrefetchCoordinator {
    private var nextTask: Task<Void, Never>?
    private var prevTask: Task<Void, Never>?
    private var fetchingNextIndex: Int?
    private var fetchingPrevIndex: Int?
    private var lastNextSkipLogIndex: Int?
    private var lastPrevSkipLogIndex: Int?
    private var lastNextSkipLogDate: Date?
    private var lastPrevSkipLogDate: Date?
    private let skipLogInterval: TimeInterval = 5

    func cancel() {
        nextTask?.cancel()
        prevTask?.cancel()
        nextTask = nil
        prevTask = nil
        fetchingNextIndex = nil
        fetchingPrevIndex = nil
    }

    func prefetchAdjacent(
        book: Book,
        chapters: [BookChapter],
        index: Int,
        contentType: Int,
        layoutSpec: ReaderLayoutSpec,
        builder: ReaderChapterBuilder,
        nextCache: ChapterCache,
        prevCache: ChapterCache,
        isMangaMode: Bool,
        onNextCache: @escaping (ChapterCache) -> Void,
        onPrevCache: @escaping (ChapterCache) -> Void,
        onResetNext: @escaping () -> Void,
        onResetPrev: @escaping () -> Void
    ) {
        prefetchNextOnly(
            book: book,
            chapters: chapters,
            index: index,
            contentType: contentType,
            layoutSpec: layoutSpec,
            builder: builder,
            nextCache: nextCache,
            isMangaMode: isMangaMode,
            onNextCache: onNextCache,
            onResetNext: onResetNext
        )
        prefetchPrevOnly(
            book: book,
            chapters: chapters,
            index: index,
            contentType: contentType,
            layoutSpec: layoutSpec,
            builder: builder,
            prevCache: prevCache,
            isMangaMode: isMangaMode,
            onPrevCache: onPrevCache,
            onResetPrev: onResetPrev
        )
    }

    func prefetchNextOnly(
        book: Book,
        chapters: [BookChapter],
        index: Int,
        contentType: Int,
        layoutSpec: ReaderLayoutSpec,
        builder: ReaderChapterBuilder,
        nextCache: ChapterCache,
        isMangaMode: Bool,
        onNextCache: @escaping (ChapterCache) -> Void,
        onResetNext: @escaping () -> Void
    ) {
        let nextIdx = index + 1
        if nextIdx < chapters.count {
            let alreadyHasNext = isMangaMode ? !nextCache.contentSentences.isEmpty : nextCache.renderStore != nil
            if alreadyHasNext {
                if shouldLogSkip(index: nextIdx, lastIndex: &lastNextSkipLogIndex, lastDate: &lastNextSkipLogDate) {
                    LogManager.shared.log("预取下一章跳过: 已有缓存 index=\(nextIdx)", category: "阅读器")
                }
                return
            }
            if fetchingNextIndex == nextIdx {
                if shouldLogSkip(index: nextIdx, lastIndex: &lastNextSkipLogIndex, lastDate: &lastNextSkipLogDate) {
                    LogManager.shared.log("预取下一章跳过: 已在预取 index=\(nextIdx)", category: "阅读器")
                }
                return
            }
            nextTask?.cancel()
            fetchingNextIndex = nextIdx
            nextTask = Task { [weak self] in
                guard let self = self else { return }
                defer { if self.fetchingNextIndex == nextIdx { self.fetchingNextIndex = nil } }
                if let content = try? await APIService.shared.fetchChapterContent(
                    bookUrl: book.bookUrl ?? "",
                    bookSourceUrl: book.origin,
                    index: nextIdx,
                    contentType: contentType
                ) {
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            LogManager.shared.log("预取下一章为空: index=\(nextIdx)", category: "阅读器")
                        }
                        let chapterUrl = chapters[nextIdx].url
                        let cache: ChapterCache
                        if isMangaMode {
                            cache = builder.buildMangaCache(rawContent: content, chapterUrl: chapterUrl)
                        } else {
                            let title = chapters[nextIdx].title
                            cache = builder.buildTextCache(
                                rawContent: content,
                                title: title,
                                layoutSpec: layoutSpec,
                                reuseStore: nil,
                                chapterUrl: chapterUrl
                            )
                        }
                        LogManager.shared.log("预取下一章完成: index=\(nextIdx), pages=\(cache.pages.count), sentences=\(cache.contentSentences.count), len=\(cache.rawContent.count)", category: "阅读器")
                        onNextCache(cache)
                    }
                }
            }
        } else {
            nextTask?.cancel()
            onResetNext()
        }
    }

    func prefetchPrevOnly(
        book: Book,
        chapters: [BookChapter],
        index: Int,
        contentType: Int,
        layoutSpec: ReaderLayoutSpec,
        builder: ReaderChapterBuilder,
        prevCache: ChapterCache,
        isMangaMode: Bool,
        onPrevCache: @escaping (ChapterCache) -> Void,
        onResetPrev: @escaping () -> Void
    ) {
        let prevIdx = index - 1
        if prevIdx >= 0 {
            let alreadyHasPrev = isMangaMode ? !prevCache.contentSentences.isEmpty : prevCache.renderStore != nil
            if alreadyHasPrev {
                if shouldLogSkip(index: prevIdx, lastIndex: &lastPrevSkipLogIndex, lastDate: &lastPrevSkipLogDate) {
                    LogManager.shared.log("预取上一章跳过: 已有缓存 index=\(prevIdx)", category: "阅读器")
                }
                return
            }
            if fetchingPrevIndex == prevIdx {
                if shouldLogSkip(index: prevIdx, lastIndex: &lastPrevSkipLogIndex, lastDate: &lastPrevSkipLogDate) {
                    LogManager.shared.log("预取上一章跳过: 已在预取 index=\(prevIdx)", category: "阅读器")
                }
                return
            }
            prevTask?.cancel()
            fetchingPrevIndex = prevIdx
            prevTask = Task { [weak self] in
                guard let self = self else { return }
                defer { if self.fetchingPrevIndex == prevIdx { self.fetchingPrevIndex = nil } }
                if let content = try? await APIService.shared.fetchChapterContent(
                    bookUrl: book.bookUrl ?? "",
                    bookSourceUrl: book.origin,
                    index: prevIdx,
                    contentType: contentType
                ) {
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            LogManager.shared.log("预取上一章为空: index=\(prevIdx)", category: "阅读器")
                        }
                        let chapterUrl = chapters[prevIdx].url
                        let cache: ChapterCache
                        if isMangaMode {
                            cache = builder.buildMangaCache(rawContent: content, chapterUrl: chapterUrl)
                        } else {
                            let title = chapters[prevIdx].title
                            cache = builder.buildTextCache(
                                rawContent: content,
                                title: title,
                                layoutSpec: layoutSpec,
                                reuseStore: nil,
                                chapterUrl: chapterUrl
                            )
                        }
                        LogManager.shared.log("预取上一章完成: index=\(prevIdx), pages=\(cache.pages.count), sentences=\(cache.contentSentences.count), len=\(cache.rawContent.count)", category: "阅读器")
                        onPrevCache(cache)
                    }
                }
            }
        } else {
            prevTask?.cancel()
            onResetPrev()
        }
    }

    private func shouldLogSkip(index: Int, lastIndex: inout Int?, lastDate: inout Date?) -> Bool {
        let now = Date()
        if lastIndex != index || lastDate == nil || now.timeIntervalSince(lastDate!) > skipLogInterval {
            lastIndex = index
            lastDate = now
            return true
        }
        return false
    }
}
