import SwiftUI
import Foundation

// MARK: - Pagination & Cache
extension ReadingView {
    func repaginateContent(in size: CGSize, with newContentSentences: [String]? = nil) {
        let sentences = newContentSentences ?? contentSentences
        let chapterTitle = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : nil

        // 如果是漫画模式，每张图片（或每段文字）作为一页
        if currentChapterIsManga {
            var pages: [PaginatedPage] = []
            var currentOffset = 0
            for (idx, sentence) in sentences.enumerated() {
                let len = sentence.utf16.count
                pages.append(PaginatedPage(globalRange: NSRange(location: currentOffset, length: len), startSentenceIndex: idx))
                currentOffset += len + 1
            }

            if pendingJumpToLastPage { currentPageIndex = max(0, pages.count - 1) }
            else if pendingJumpToFirstPage { currentPageIndex = 0 }
            else if currentPageIndex >= pages.count { currentPageIndex = 0 }

            pendingJumpToLastPage = false
            pendingJumpToFirstPage = false

            // 确保此处传入了 chapterUrl
            let currentUrl = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].url : nil
            currentCache = ChapterCache(pages: pages, renderStore: nil, pageInfos: nil, contentSentences: sentences, rawContent: rawContent, attributedText: NSAttributedString(string: sentences.joined(separator: "\n")), paragraphStarts: [], chapterPrefixLen: 0, isFullyPaginated: true, chapterUrl: currentUrl)
            hasInitialPagination = true
            return
        }

        let newAttrText = TextKitPaginator.createAttributedText(sentences: sentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, chapterTitle: chapterTitle)
        let newPStarts = TextKitPaginator.paragraphStartIndices(sentences: sentences)
        let newPrefixLen = (chapterTitle?.isEmpty ?? true) ? 0 : (chapterTitle! + "\n").utf16.count

        guard newAttrText.length > 0, size.width > 0, size.height > 0 else {
            currentCache = .empty
            return
        }

        let resumeCharIndex = pendingResumeCharIndex
        let shouldJumpToFirst = pendingJumpToFirstPage
        let shouldJumpToLast = pendingJumpToLastPage
        let focusCharIndex: Int? = (shouldJumpToFirst || shouldJumpToLast)
            ? nil
            : (currentCache.pages.indices.contains(currentPageIndex) ? currentCache.pages[currentPageIndex].globalRange.location : resumeCharIndex)

        let tk2Store: TextKit2RenderStore
        if let existingStore = currentCache.renderStore, existingStore.layoutWidth == size.width {
            existingStore.update(attributedString: newAttrText, layoutWidth: size.width)
            tk2Store = existingStore
        } else {
            tk2Store = TextKit2RenderStore(attributedString: newAttrText, layoutWidth: size.width)
        }

        let inset = max(8, min(18, preferences.fontSize * 0.6))
        let result = TextKit2Paginator.paginate(renderStore: tk2Store, pageSize: size, paragraphStarts: newPStarts, prefixLen: newPrefixLen, contentInset: inset)

        if shouldJumpToLast {
            currentPageIndex = max(0, result.pages.count - 1)
        } else if shouldJumpToFirst {
            currentPageIndex = 0
        } else if let targetCharIndex = focusCharIndex, let pageIndex = pageIndexForChar(targetCharIndex, in: result.pages) {
            currentPageIndex = pageIndex
        } else if currentCache.pages.isEmpty {
            currentPageIndex = 0
        }
        pendingJumpToLastPage = false
        pendingJumpToFirstPage = false

        if result.pages.isEmpty { currentPageIndex = 0 }
        else if currentPageIndex >= result.pages.count { currentPageIndex = result.pages.count - 1 }

        currentCache = ChapterCache(pages: result.pages, renderStore: tk2Store, pageInfos: result.pageInfos, contentSentences: sentences, rawContent: rawContent, attributedText: newAttrText, paragraphStarts: newPStarts, chapterPrefixLen: newPrefixLen, isFullyPaginated: true, chapterUrl: chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].url : nil)
        if !hasInitialPagination, !result.pages.isEmpty { hasInitialPagination = true }

        if let localPage = pendingResumeLocalPageIndex, pendingResumeLocalChapterIndex == currentChapterIndex, result.pages.indices.contains(localPage) {
            currentPageIndex = localPage
            pendingResumeLocalPageIndex = nil
        }
        if resumeCharIndex != nil { pendingResumeCharIndex = nil }
        triggerAdjacentPrefetchIfNeeded(force: true)
    }

    private func pageIndexForChar(_ index: Int, in pages: [PaginatedPage]) -> Int? {
        guard index >= 0 else { return nil }
        return pages.firstIndex(where: { NSLocationInRange(index, $0.globalRange) })
    }

    func triggerAdjacentPrefetchIfNeeded(force: Bool = false) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        let now = Date().timeIntervalSince1970
        if !force, now - lastAdjacentPrepareAt < 1.0 { return }
        if (currentChapterIndex > 0 && prevCache.pages.isEmpty) || (currentChapterIndex < chapters.count - 1 && nextCache.pages.isEmpty) {
            lastAdjacentPrepareAt = now
            prepareAdjacentChapters(for: currentChapterIndex)
        }
    }

    func ensurePagesForCharIndex(_ index: Int) -> Int? {
        return pageIndexForChar(index, in: currentCache.pages)
    }

    func scheduleRepaginate(in size: CGSize) {
        pageSize = size
        let key = PaginationKey(width: Int(size.width * 100), height: Int(size.height * 100), fontSize: Int(preferences.fontSize * 10), lineSpacing: Int(preferences.lineSpacing * 10), margin: Int(preferences.pageHorizontalMargin * 10), sentenceCount: contentSentences.count, chapterIndex: currentChapterIndex, resumeCharIndex: pendingResumeCharIndex ?? -1, resumePageIndex: pendingResumeLocalPageIndex ?? -1)

        if suppressRepaginateOnce {
            suppressRepaginateOnce = false
            lastPaginationKey = key
            return
        }

        if key == lastPaginationKey { return }
        lastPaginationKey = key
        if isRepaginateQueued { return }

        isRepaginateQueued = true
        DispatchQueue.main.async {
            self.repaginateContent(in: size)
            self.isRepaginateQueued = false
        }
    }

    func pageRange(for pageIndex: Int) -> NSRange? {
        guard currentCache.pages.indices.contains(pageIndex) else { return nil }
        return currentCache.pages[pageIndex].globalRange
    }

    func pageStartSentenceIndex(for pageIndex: Int) -> Int? {
        if currentCache.pages.indices.contains(pageIndex) {
            return currentCache.pages[pageIndex].startSentenceIndex
        }

        guard let range = pageRange(for: pageIndex) else { return nil }
        let adjustedLocation = max(0, range.location - currentCache.chapterPrefixLen)
        return currentCache.paragraphStarts.lastIndex(where: { $0 <= adjustedLocation }) ?? 0
    }

    func prepareAdjacentChapters(for chapterIndex: Int) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }

        let nextIndex = chapterIndex + 1
        if nextIndex < chapters.count {
            Task { if let cache = await paginateChapter(at: nextIndex, forGate: true) { await MainActor.run { self.nextCache = cache } } }
        } else { nextCache = .empty }

        let prevIndex = chapterIndex - 1
        if prevIndex >= 0 {
            Task { if let cache = await paginateChapter(at: prevIndex, forGate: true, fromEnd: true) { await MainActor.run { self.prevCache = cache } } }
        } else { prevCache = .empty }
    }

    func prepareAdjacentChaptersIfNeeded(for chapterIndex: Int) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }

        let nextIndex = chapterIndex + 1
        if nextIndex < chapters.count, nextCache.pages.isEmpty {
            Task { if let cache = await paginateChapter(at: nextIndex, forGate: true) { await MainActor.run { self.nextCache = cache } } }
        }

        let prevIndex = chapterIndex - 1
        if prevIndex >= 0, prevCache.pages.isEmpty {
            Task { if let cache = await paginateChapter(at: prevIndex, forGate: true, fromEnd: true) { await MainActor.run { self.prevCache = cache } } }
        }
    }

    func switchChapterUsingCacheIfAvailable(targetIndex: Int, jumpToFirst: Bool, jumpToLast: Bool) -> Bool {
        if targetIndex == currentChapterIndex + 1, !nextCache.pages.isEmpty {
            let cached = nextCache
            prevCache = currentCache
            nextCache = .empty
            applyCachedChapter(cached, chapterIndex: targetIndex, jumpToFirst: jumpToFirst, jumpToLast: jumpToLast)
            ttsBaseIndex = 0
            prepareAdjacentChaptersIfNeeded(for: currentChapterIndex)
            return true
        }
        if targetIndex == currentChapterIndex - 1, !prevCache.pages.isEmpty {
            let cached = prevCache
            nextCache = currentCache
            prevCache = .empty
            applyCachedChapter(cached, chapterIndex: targetIndex, jumpToFirst: jumpToFirst, jumpToLast: jumpToLast)
            ttsBaseIndex = 0
            prepareAdjacentChaptersIfNeeded(for: currentChapterIndex)
            return true
        }
        return false
    }

    func continuePaginatingCurrentChapterIfNeeded() {
        guard !currentCache.isFullyPaginated,
              let store = currentCache.renderStore,
              let lastPage = currentCache.pages.last,
              pageSize.width > 0, pageSize.height > 0 else { return }

        let startOffset = NSMaxRange(lastPage.globalRange)
        let inset = currentCache.pageInfos?.first?.contentInset ?? max(8, min(18, preferences.fontSize * 0.6))
        let result = TextKit2Paginator.paginate(
            renderStore: store,
            pageSize: pageSize,
            paragraphStarts: currentCache.paragraphStarts,
            prefixLen: currentCache.chapterPrefixLen,
            contentInset: inset,
            maxPages: Int.max,
            startOffset: startOffset
        )

        if result.pages.isEmpty {
            currentCache = ChapterCache(
                pages: currentCache.pages,
                renderStore: store,
                pageInfos: currentCache.pageInfos,
                contentSentences: currentCache.contentSentences,
                rawContent: currentCache.rawContent,
                attributedText: currentCache.attributedText,
                paragraphStarts: currentCache.paragraphStarts,
                chapterPrefixLen: currentCache.chapterPrefixLen,
                isFullyPaginated: result.reachedEnd,
                chapterUrl: currentCache.chapterUrl
            )
            return
        }

        let newPages = currentCache.pages + result.pages
        let newInfos = (currentCache.pageInfos ?? []) + result.pageInfos
        currentCache = ChapterCache(
            pages: newPages,
            renderStore: store,
            pageInfos: newInfos,
            contentSentences: currentCache.contentSentences,
            rawContent: currentCache.rawContent,
            attributedText: currentCache.attributedText,
            paragraphStarts: currentCache.paragraphStarts,
            chapterPrefixLen: currentCache.chapterPrefixLen,
            isFullyPaginated: result.reachedEnd,
            chapterUrl: currentCache.chapterUrl
        )
    }

    func repaginateCurrentChapterWindow(sentences: [String]? = nil) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }

        if let sentences = sentences, !sentences.isEmpty {
            repaginateContent(in: pageSize, with: sentences)
            return
        }
        guard !rawContent.isEmpty else { return }
        repaginateContent(in: pageSize, with: splitIntoParagraphs(applyReplaceRules(to: rawContent)))
    }

    func paginateChapter(at index: Int, forGate: Bool, fromEnd: Bool = false) async -> ChapterCache? {
        let effectiveType = (book.bookUrl.map { preferences.manualMangaUrls.contains($0) } == true) ? 2 : (book.type ?? 0)
        guard let content = try? await apiService.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index, contentType: effectiveType) else { return nil }

        let cleaned = removeHTMLAndSVG(content)
        let processed = applyReplaceRules(to: cleaned)
        let sentences = splitIntoParagraphs(processed)
        let title = chapters[index].title

        let attrText = TextKitPaginator.createAttributedText(sentences: sentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, chapterTitle: title)
        let pStarts = TextKitPaginator.paragraphStartIndices(sentences: sentences)
        let prefixLen = (title.isEmpty) ? 0 : (title + "\n").utf16.count

        let tk2Store = TextKit2RenderStore(attributedString: attrText, layoutWidth: pageSize.width)
        let limit = Int.max

        let inset = max(8, min(18, preferences.fontSize * 0.6))
        let result = TextKit2Paginator.paginate(renderStore: tk2Store, pageSize: pageSize, paragraphStarts: pStarts, prefixLen: prefixLen, contentInset: inset, maxPages: limit)

        return ChapterCache(pages: result.pages, renderStore: tk2Store, pageInfos: result.pageInfos, contentSentences: sentences, rawContent: cleaned, attributedText: attrText, paragraphStarts: pStarts, chapterPrefixLen: prefixLen, isFullyPaginated: result.reachedEnd, chapterUrl: chapters[index].url)
    }
}
