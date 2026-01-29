import Foundation

final class ReaderPrefetchCoordinator {
    private var nextTask: Task<Void, Never>?
    private var prevTask: Task<Void, Never>?

    func cancel() {
        nextTask?.cancel()
        prevTask?.cancel()
        nextTask = nil
        prevTask = nil
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
        cancel()

        if index + 1 < chapters.count {
            nextTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let content = try await APIService.shared.fetchChapterContent(
                        bookUrl: book.bookUrl ?? "",
                        bookSourceUrl: book.origin,
                        index: index + 1,
                        contentType: contentType
                    )
                    guard !(self.nextTask?.isCancelled ?? true) else { return }
                    let title = chapters[index + 1].title
                    let cache = isMangaMode
                        ? builder.buildMangaCache(rawContent: content, chapterUrl: chapters[index + 1].url)
                        : builder.buildTextCache(rawContent: content, title: title, layoutSpec: layoutSpec, reuseStore: nextCache.renderStore, chapterUrl: chapters[index + 1].url)
                    await MainActor.run { onNextCache(cache) }
                } catch {
                    await MainActor.run { onResetNext() }
                }
            }
        } else {
            onResetNext()
        }

        if index - 1 >= 0 {
            prevTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let content = try await APIService.shared.fetchChapterContent(
                        bookUrl: book.bookUrl ?? "",
                        bookSourceUrl: book.origin,
                        index: index - 1,
                        contentType: contentType
                    )
                    guard !(self.prevTask?.isCancelled ?? true) else { return }
                    let title = chapters[index - 1].title
                    let cache = isMangaMode
                        ? builder.buildMangaCache(rawContent: content, chapterUrl: chapters[index - 1].url)
                        : builder.buildTextCache(rawContent: content, title: title, layoutSpec: layoutSpec, reuseStore: prevCache.renderStore, chapterUrl: chapters[index - 1].url)
                    await MainActor.run { onPrevCache(cache) }
                } catch {
                    await MainActor.run { onResetPrev() }
                }
            }
        } else {
            onResetPrev()
        }
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
        nextTask?.cancel()
        nextTask = nil

        guard index + 1 < chapters.count else {
            onResetNext()
            return
        }

        nextTask = Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await APIService.shared.fetchChapterContent(
                    bookUrl: book.bookUrl ?? "",
                    bookSourceUrl: book.origin,
                    index: index + 1,
                    contentType: contentType
                )
                guard !(self.nextTask?.isCancelled ?? true) else { return }
                let title = chapters[index + 1].title
                let cache = isMangaMode
                    ? builder.buildMangaCache(rawContent: content, chapterUrl: chapters[index + 1].url)
                    : builder.buildTextCache(rawContent: content, title: title, layoutSpec: layoutSpec, reuseStore: nextCache.renderStore, chapterUrl: chapters[index + 1].url)
                await MainActor.run { onNextCache(cache) }
            } catch {
                await MainActor.run { onResetNext() }
            }
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
        prevTask?.cancel()
        prevTask = nil

        guard index - 1 >= 0 else {
            onResetPrev()
            return
        }

        prevTask = Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await APIService.shared.fetchChapterContent(
                    bookUrl: book.bookUrl ?? "",
                    bookSourceUrl: book.origin,
                    index: index - 1,
                    contentType: contentType
                )
                guard !(self.prevTask?.isCancelled ?? true) else { return }
                let title = chapters[index - 1].title
                let cache = isMangaMode
                    ? builder.buildMangaCache(rawContent: content, chapterUrl: chapters[index - 1].url)
                    : builder.buildTextCache(rawContent: content, title: title, layoutSpec: layoutSpec, reuseStore: prevCache.renderStore, chapterUrl: chapters[index - 1].url)
                await MainActor.run { onPrevCache(cache) }
            } catch {
                await MainActor.run { onResetPrev() }
            }
        }
    }
}
