import Foundation

final class ReaderPrefetchCoordinator {
    private var nextTask: Task<Void, Never>?
    private var prevTask: Task<Void, Never>?
    private var fetchingNextIndex: Int?
    private var fetchingPrevIndex: Int?

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
            if alreadyHasNext || fetchingNextIndex == nextIdx { return }
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
            if alreadyHasPrev || fetchingPrevIndex == prevIdx { return }
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
                        onPrevCache(cache)
                    }
                }
            }
        } else {
            prevTask?.cancel()
            onResetPrev()
        }
    }
}
