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
        if isMangaMode { return }
        let nextIdx = index + 1
        if nextIdx < chapters.count {
            if nextCache.renderStore == nil && fetchingNextIndex != nextIdx {
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
                            let title = chapters[nextIdx].title
                            let cache = builder.buildTextCache(
                                rawContent: content,
                                title: title,
                                layoutSpec: layoutSpec,
                                reuseStore: nil
                            )
                            onNextCache(cache)
                        }
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
        if isMangaMode { return }
        let prevIdx = index - 1
        if prevIdx >= 0 {
            if prevCache.renderStore == nil && fetchingPrevIndex != prevIdx {
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
                            let title = chapters[prevIdx].title
                            let cache = builder.buildTextCache(
                                rawContent: content,
                                title: title,
                                layoutSpec: layoutSpec,
                                reuseStore: nil
                            )
                            onPrevCache(cache)
                        }
                    }
                }
            }
        } else {
            prevTask?.cancel()
            onResetPrev()
        }
    }
}
