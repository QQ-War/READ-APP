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
            if alreadyHasNext && nextCache.chapterUrl == chapters[nextIdx].url { return }
            if fetchingNextIndex == nextIdx { return }
            nextTask?.cancel()
            fetchingNextIndex = nextIdx
            nextTask = Task { [weak self] in
                guard let self = self else { return }
                defer { if self.fetchingNextIndex == nextIdx { self.fetchingNextIndex = nil } }
                let realIndex = chapters[nextIdx].index
                if let content = try? await APIService.shared.fetchChapterContent(
                    bookUrl: book.bookUrl ?? "",
                    bookSourceUrl: book.origin,
                    index: realIndex,
                    contentType: contentType
                ) {
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        _ = trimmed
                        let chapterUrl = chapters[nextIdx].url
                        let cache: ChapterCache
                        if isMangaMode {
                            cache = builder.buildMangaCache(rawContent: content, chapterUrl: chapterUrl)
                            // 预加载漫画图片
                            self.prefetchMangaImages(book: book, chapterIndex: chapters[nextIdx].index, sentences: cache.contentSentences, chapterUrl: chapterUrl)
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
            if alreadyHasPrev && prevCache.chapterUrl == chapters[prevIdx].url { return }
            if fetchingPrevIndex == prevIdx { return }
            prevTask?.cancel()
            fetchingPrevIndex = prevIdx
            prevTask = Task { [weak self] in
                guard let self = self else { return }
                defer { if self.fetchingPrevIndex == prevIdx { self.fetchingPrevIndex = nil } }
                let realIndex = chapters[prevIdx].index
                if let content = try? await APIService.shared.fetchChapterContent(
                    bookUrl: book.bookUrl ?? "",
                    bookSourceUrl: book.origin,
                    index: realIndex,
                    contentType: contentType
                ) {
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        _ = trimmed
                        let chapterUrl = chapters[prevIdx].url
                        let cache: ChapterCache
                        if isMangaMode {
                            cache = builder.buildMangaCache(rawContent: content, chapterUrl: chapterUrl)
                            // 预加载上一章漫画图片
                            self.prefetchMangaImages(book: book, chapterIndex: chapters[prevIdx].index, sentences: cache.contentSentences, chapterUrl: chapterUrl)
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

    private func prefetchMangaImages(book: Book, chapterIndex: Int, sentences: [String], chapterUrl: String?) {
        guard let bookUrl = book.bookUrl, UserPreferences.shared.isMangaPreloadEnabled else { return }
        Task {
            for sentence in sentences {
                let urlStr = sentence.replacingOccurrences(of: "__IMG__", with: "").trimmingCharacters(in: .whitespaces)
                guard let resolved = MangaImageService.shared.resolveImageURL(urlStr) else { continue }
                let absolute = resolved.absoluteString
                
                // 如果已在本地磁盘缓存中，跳过
                if LocalCacheManager.shared.isMangaImageCached(bookUrl: bookUrl, chapterIndex: chapterIndex, imageURL: absolute) {
                    continue
                }
                
                // 执行下载。注意：即使不存盘，fetchImageData 也会利用系统的 URLSession 内存/临时磁盘缓存，
                // 这样在阅读器真正显示时就能实现“秒开”。
                if let data = await MangaImageService.shared.fetchImageData(for: resolved, referer: chapterUrl) {
                    // 只有开启了“自动离线”才写入 LocalCacheManager 持久化
                    if UserPreferences.shared.isMangaAutoCacheEnabled {
                        LocalCacheManager.shared.saveMangaImage(bookUrl: bookUrl, chapterIndex: chapterIndex, imageURL: absolute, data: data)
                    }
                }
                
                // 适当延迟，避免请求过快
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
}