import SwiftUI

// MARK: - Navigation
extension ReadingView {
    func goToPreviousPage() {
        if currentPageIndex > 0 {
            pageTurnRequest = PageTurnRequest(direction: .reverse, animated: true, targetIndex: currentPageIndex - 1)
        }
        else if currentChapterIndex > 0 {
            pendingJumpToLastPage = true
            previousChapter(animated: true)
        }
    }

    func goToNextPage() {
        if currentPageIndex < currentCache.pages.count - 1 {
            pageTurnRequest = PageTurnRequest(direction: .forward, animated: true, targetIndex: currentPageIndex + 1)
        }
        else if currentChapterIndex < chapters.count - 1 {
            pendingJumpToFirstPage = true
            nextChapter(animated: true)
        }
    }

    func handleReaderTap(location: ReaderTapLocation) {
        if showUIControls {
            showUIControls = false
            return
        }
        if location == .middle {
            showUIControls = true
            return
        }
        if ttsManager.isPlaying && preferences.lockPageOnTTS { return }
        switch location {
        case .left: goToPreviousPage()
        case .right: goToNextPage()
        case .middle: showUIControls = true
        }
    }

    func handlePageIndexChange(_ newIndex: Int) {
        if suppressPageIndexChangeOnce {
            suppressPageIndexChangeOnce = false
            return
        }
        pendingBufferPageIndex = newIndex
        processPendingPageChangeIfReady()
    }

    func processPendingPageChangeIfReady() {
        guard !isPageTransitioning, let newIndex = pendingBufferPageIndex else { return }
        if lastHandledPageIndex == newIndex { return }

        pendingBufferPageIndex = nil
        lastHandledPageIndex = newIndex

        if newIndex <= 1 || newIndex >= max(0, currentCache.pages.count - 2) {
            triggerAdjacentPrefetchIfNeeded()
        }

        if ttsManager.isPlaying && !ttsManager.isPaused && !isAutoFlipping {
            if !preferences.lockPageOnTTS {
                requestTTSPlayback(pageIndexOverride: newIndex, showControls: false)
            }
        }
        if ttsManager.isPlaying && ttsManager.isPaused {
            needsTTSRestartAfterPause = true
        }
        isAutoFlipping = false

        if let startIndex = pageStartSentenceIndex(for: newIndex) {
            lastTTSSentenceIndex = startIndex
        }
    }

    func handleChapterSwitch(offset: Int) {
        pendingFlipId = UUID()
        didApplyResumePos = true // Mark as true to prevent auto-resuming from server/local storage
        let shouldContinuePlaying = ttsManager.isPlaying && !ttsManager.isPaused && ttsManager.bookUrl == book.bookUrl

        if offset == 1 {
            guard !nextCache.pages.isEmpty else {
                currentChapterIndex += 1
                loadChapterContent()
                return
            }
            let cached = nextCache
            let nextIndex = currentChapterIndex + 1
            prevCache = currentCache
            nextCache = .empty
            applyCachedChapter(cached, chapterIndex: nextIndex, jumpToFirst: true, jumpToLast: false)
            ttsBaseIndex = 0
            prepareAdjacentChaptersIfNeeded(for: currentChapterIndex)
            if shouldContinuePlaying {
                lastTTSSentenceIndex = 0
                requestTTSPlayback(pageIndexOverride: currentPageIndex, showControls: false)
            }
            return
        } else if offset == -1 {
            guard !prevCache.pages.isEmpty else {
                currentChapterIndex -= 1
                loadChapterContent()
                return
            }
            let cached = prevCache
            let prevIndex = currentChapterIndex - 1
            nextCache = currentCache
            prevCache = .empty
            applyCachedChapter(cached, chapterIndex: prevIndex, jumpToFirst: false, jumpToLast: true)
            ttsBaseIndex = 0
            prepareAdjacentChaptersIfNeeded(for: currentChapterIndex)
            if shouldContinuePlaying {
                lastTTSSentenceIndex = max(0, currentCache.paragraphStarts.count - 1)
                requestTTSPlayback(pageIndexOverride: currentPageIndex, showControls: false)
            }
            return
        }
        loadChapterContent()
    }

    func previousChapter(animated: Bool = false) {
        guard currentChapterIndex > 0 else { return }
        isExplicitlySwitchingChapter = true // 标记开始切章
        didApplyResumePos = true
        currentVisibleSentenceIndex = nil
        let targetIndex = currentChapterIndex - 1

        if !prevCache.pages.isEmpty {
            let cached = prevCache
            if animated {
                // 带动画：不立即更新状态，先发翻页请求
                pageTurnRequest = PageTurnRequest(
                    direction: .reverse,
                    animated: true,
                    targetIndex: max(0, cached.pages.count - 1),
                    targetSnapshot: snapshot(from: cached),
                    targetChapterIndex: targetIndex
                )
            } else {
                // 不带动画：立即更新状态（如目录跳转）
                nextCache = currentCache
                prevCache = .empty
                applyCachedChapter(cached, chapterIndex: targetIndex, jumpToFirst: false, jumpToLast: true, animated: false)
                finishChapterSwitch()
            }
            return
        }
        currentChapterIndex = targetIndex
        loadChapterContent()
        saveProgress()
    }

    func nextChapter(animated: Bool = false) {
        guard currentChapterIndex < chapters.count - 1 else { return }
        isExplicitlySwitchingChapter = true // 标记开始切章
        didApplyResumePos = true
        currentVisibleSentenceIndex = nil
        let targetIndex = currentChapterIndex + 1

        if !nextCache.pages.isEmpty {
            let cached = nextCache
            if animated {
                // 带动画：先发请求，不切数据
                pageTurnRequest = PageTurnRequest(
                    direction: .forward,
                    animated: true,
                    targetIndex: 0,
                    targetSnapshot: snapshot(from: cached),
                    targetChapterIndex: targetIndex
                )
            } else {
                // 不带动画：立即更新
                prevCache = currentCache
                nextCache = .empty
                applyCachedChapter(cached, chapterIndex: targetIndex, jumpToFirst: true, jumpToLast: false, animated: false)
                finishChapterSwitch()
            }
            return
        }
        currentChapterIndex = targetIndex
        loadChapterContent()
        saveProgress()
    }
}
