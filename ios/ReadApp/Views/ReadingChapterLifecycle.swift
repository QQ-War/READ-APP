import SwiftUI
import Foundation

// MARK: - Chapter Lifecycle
extension ReadingView {
    func handlePendingScroll() {
        guard preferences.readingMode != .horizontal, let index = pendingScrollToSentenceIndex, let proxy = scrollProxy else { return }
        withAnimation { proxy.scrollTo(index, anchor: .center) }
        pendingScrollToSentenceIndex = nil
    }

    func applyCachedChapter(_ cache: ChapterCache, chapterIndex: Int, jumpToFirst: Bool, jumpToLast: Bool, animated: Bool = false) {
        suppressRepaginateOnce = true
        currentChapterIndex = chapterIndex
        currentCache = cache
        rawContent = cache.rawContent
        currentContent = cache.contentSentences.joined(separator: "\n")
        contentSentences = cache.contentSentences
        currentVisibleSentenceIndex = nil
        pendingScrollToSentenceIndex = nil

        let targetIdx = jumpToLast ? max(0, cache.pages.count - 1) : 0
        self.pageTurnRequest = PageTurnRequest(direction: jumpToLast ? .reverse : .forward, animated: animated, targetIndex: targetIdx)
        self.currentPageIndex = targetIdx

        pendingJumpToFirstPage = false
        pendingJumpToLastPage = false
    }

    func loadChapterContent() {
        guard chapters.indices.contains(currentChapterIndex) else { return }

        let chapterIndex = currentChapterIndex
        let chapterTitle = chapters[chapterIndex].title
        let targetPageSize = pageSize
        let fontSize = preferences.fontSize
        let lineSpacing = preferences.lineSpacing
        let margin = preferences.pageHorizontalMargin

        // 判断是否为漫画模式（考虑手动标记）
        let effectiveType = (book.bookUrl.map { preferences.manualMangaUrls.contains($0) } == true) ? 2 : (book.type ?? 0)

        // Capture all necessary resume state
        let resumePos = pendingResumePos
        let resumeLocalBodyIndex = pendingResumeLocalBodyIndex
        let resumeLocalChapterIndex = pendingResumeLocalChapterIndex
        let resumeLocalPageIndex = pendingResumeLocalPageIndex
        let capturedTTSIndex = lastTTSSentenceIndex
        let jumpFirst = pendingJumpToFirstPage
        let jumpLast = pendingJumpToLastPage
        let shouldResume = shouldApplyResumeOnce

        if currentCache.pages.isEmpty { isLoading = true }

        Task {
            do {
                let content = try await apiService.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: chapterIndex, contentType: effectiveType)

                // 1. Heavy processing on background thread
                let cleaned = removeHTMLAndSVG(content)

                // 获取当前章节 URL 并尝试“Cookie 预热”
                let chapterUrl = chapters[chapterIndex].url
                if book.type == 2 || cleaned.contains("__IMG__") {
                    prewarmCookies(for: chapterUrl)
                }

                let processed = applyReplaceRules(to: cleaned)
                let sentences = splitIntoParagraphs(processed)

                await MainActor.run {
                    guard self.currentChapterIndex == chapterIndex else { return }

                    var initialCache: ChapterCache? = nil
                    var targetPageIndex = 0

                    // 2. Pre-paginate on main thread (TextKit2 is not thread-safe)
                    if targetPageSize.width > 0 {
                        let attrText = TextKitPaginator.createAttributedText(sentences: sentences, fontSize: fontSize, lineSpacing: lineSpacing, chapterTitle: chapterTitle)
                        let pStarts = TextKitPaginator.paragraphStartIndices(sentences: sentences)
                        let prefixLen = (chapterTitle.isEmpty) ? 0 : (chapterTitle + "\n").utf16.count
                        let tk2Store = TextKit2RenderStore(attributedString: attrText, layoutWidth: targetPageSize.width)
                        let inset = max(8, min(18, fontSize * 0.6))
                        let result = TextKit2Paginator.paginate(renderStore: tk2Store, pageSize: targetPageSize, paragraphStarts: pStarts, prefixLen: prefixLen, contentInset: inset)

                        initialCache = ChapterCache(pages: result.pages, renderStore: tk2Store, pageInfos: result.pageInfos, contentSentences: sentences, rawContent: cleaned, attributedText: attrText, paragraphStarts: pStarts, chapterPrefixLen: prefixLen, isFullyPaginated: result.reachedEnd, chapterUrl: chapterTitle.isEmpty ? book.bookUrl : chapters[chapterIndex].url)

                        // Determine where to land
                        if jumpLast {
                            targetPageIndex = max(0, result.pages.count - 1)
                        } else if jumpFirst {
                            targetPageIndex = 0
                        } else if let ttsIdx = capturedTTSIndex, ttsIdx < pStarts.count {
                            // High Priority: Align with TTS progress if available
                            let charOffset = pStarts[ttsIdx] + prefixLen
                            targetPageIndex = result.pages.firstIndex(where: { NSLocationInRange(charOffset, $0.globalRange) }) ?? 0
                        } else if shouldResume {
                            let bodyLength = (pStarts.last ?? 0) + (sentences.last?.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count ?? 0)
                            let bodyIndex: Int
                            if let localIndex = resumeLocalBodyIndex, resumeLocalChapterIndex == chapterIndex {
                                bodyIndex = localIndex
                            } else if let pos = resumePos, pos > 0 {
                                bodyIndex = pos > 1.0 ? Int(pos) : Int(Double(bodyLength) * min(max(pos, 0.0), 1.0))
                            } else {
                                bodyIndex = 0
                            }
                            let clampedBodyIndex = max(0, min(bodyIndex, max(0, bodyLength - 1)))
                            let charIndex = clampedBodyIndex + prefixLen

                            if let pageIdx = result.pages.firstIndex(where: { NSLocationInRange(charIndex, $0.globalRange) }) {
                                targetPageIndex = pageIdx
                            } else if let localPage = resumeLocalPageIndex, resumeLocalChapterIndex == chapterIndex, result.pages.indices.contains(localPage) {
                                targetPageIndex = localPage
                            }
                        }
                    }

                    self.rawContent = cleaned
                    if let cache = initialCache {
                        self.contentSentences = sentences
                        updateMangaModeState() // 关键：更新模式
                        self.currentContent = processed
                        self.currentCache = cache

                        // 初始对焦：静默同步模式
                        if let ttsIdx = capturedTTSIndex {
                            self.isTTSSyncingPage = true
                            self.isAutoFlipping = true // 关键：标记为自动对焦，防止重启 TTS
                            self.lastTTSSentenceIndex = ttsIdx
                        }

                        // 先设页码，再发跳转指令
                        self.currentPageIndex = targetPageIndex
                        self.pageTurnRequest = PageTurnRequest(direction: .forward, animated: false, targetIndex: targetPageIndex)

                        self.didApplyResumePos = true
                        if !self.hasInitialPagination, !cache.pages.isEmpty { self.hasInitialPagination = true }

                        // Set the pagination key to current state to prevent immediate redundant re-pagination
                        self.lastPaginationKey = PaginationKey(width: Int(targetPageSize.width * 100), height: Int(targetPageSize.height * 100), fontSize: Int(fontSize * 10), lineSpacing: Int(lineSpacing * 10), margin: Int(margin * 10), sentenceCount: sentences.count, chapterIndex: chapterIndex, resumeCharIndex: -1, resumePageIndex: -1)

                        // 给予足够宽裕的时间（0.8s）让 UIKit 的 setViewControllers 完成
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            self.isTTSSyncingPage = false
                            self.isAutoFlipping = false
                        }
                    } else {
                        // 回落逻辑
                        updateProcessedContent(from: cleaned)
                    }

                    if self.shouldSyncPageAfterPagination {
                        let currentIndex = self.ttsManager.currentSentenceIndex + self.ttsBaseIndex
                        let baselineIndex = capturedTTSIndex ?? currentIndex
                        if abs(currentIndex - baselineIndex) >= 2 {
                            self.syncPageForSentenceIndex(self.ttsManager.currentSentenceIndex)
                        }
                        self.shouldSyncPageAfterPagination = false
                    }

                    // 垂直模式置顶逻辑
                    if self.preferences.readingMode == .vertical && capturedTTSIndex == nil && !shouldResume {
                        self.pendingScrollToSentenceIndex = 0
                        self.handlePendingScroll()
                    }

                    self.isLoading = false
                    self.shouldApplyResumeOnce = false
                    self.pendingJumpToFirstPage = false
                    self.pendingJumpToLastPage = false
                    self.pendingResumeLocalBodyIndex = nil
                    self.pendingResumeLocalChapterIndex = nil
                    self.pendingResumeLocalPageIndex = nil
                    self.pendingResumePos = nil

                    prepareAdjacentChapters(for: chapterIndex)

                    if let request = pendingTTSRequest {
                        pendingTTSRequest = nil
                        requestTTSPlayback(pageIndexOverride: request.pageIndexOverride, showControls: request.showControls)
                    }
                    if isTTSAutoChapterChange { isTTSAutoChapterChange = false }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "加载章节失败：\(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    func resetPaginationState() {
        currentCache = .empty; prevCache = .empty; nextCache = .empty
        currentPageIndex = 0; lastAdjacentPrepareAt = 0
        pendingBufferPageIndex = nil; lastHandledPageIndex = nil
    }

    func finalizeAnimatedChapterSwitch(targetChapter: Int, targetPage: Int) {
        let isForward = targetChapter > currentChapterIndex
        let cached = isForward ? nextCache : prevCache
        guard !cached.pages.isEmpty else { return }

        // 交换缓存
        if isForward {
            prevCache = currentCache
            nextCache = .empty
        } else {
            nextCache = currentCache
            prevCache = .empty
        }

        // 更新主状态
        suppressRepaginateOnce = true
        currentChapterIndex = targetChapter
        currentCache = cached
        rawContent = cached.rawContent
        currentContent = cached.contentSentences.joined(separator: "\n")
        contentSentences = cached.contentSentences
        currentVisibleSentenceIndex = nil
        pendingScrollToSentenceIndex = nil

        currentPageIndex = targetPage

        // 完成后续逻辑（TTS等）
        finishChapterSwitch()
    }

    func finishChapterSwitch() {
        ttsBaseIndex = 0
        prepareAdjacentChaptersIfNeeded(for: currentChapterIndex)
        if ttsManager.isPlaying && !ttsManager.isPaused {
            lastTTSSentenceIndex = 0
            requestTTSPlayback(pageIndexOverride: currentPageIndex, showControls: false)
        }
        saveProgress()
    }

    func prewarmCookies(for urlString: String) {
        guard let url = URL(string: urlString) else { return }
        if preferences.isVerboseLoggingEnabled { logger.log("正在预热 Cookie: \(urlString)", category: "漫画调试") }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD" // 轻量级请求
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { _, _, _ in
            // 仅需请求发生，系统会自动处理 Set-Cookie
            if self.preferences.isVerboseLoggingEnabled { self.logger.log("Cookie 预热完成", category: "漫画调试") }
        }.resume()
    }
}
