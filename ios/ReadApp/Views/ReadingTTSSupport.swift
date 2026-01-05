import SwiftUI
import Foundation

// MARK: - TTS Support
extension ReadingView {
    func handleTTSPlayStateChange(_ isPlaying: Bool) {
        if !isPlaying {
            showUIControls = true
            if ttsManager.currentSentenceIndex > 0 && ttsManager.currentSentenceIndex <= contentSentences.count {
                lastTTSSentenceIndex = ttsManager.currentSentenceIndex
            }
        }
    }

    func handleTTSPauseStateChange(_ isPaused: Bool) {
        if isPaused {
            pausedChapterIndex = currentChapterIndex
            pausedPageIndex = currentPageIndex
            needsTTSRestartAfterPause = false
        } else {
            needsTTSRestartAfterPause = false
        }
    }

    func handleTTSSentenceChange() {
        if preferences.readingMode == .horizontal && ttsManager.isPlaying {
            if !suppressTTSSync { syncPageForSentenceIndex(ttsManager.currentSentenceIndex) }
            scheduleAutoFlip(duration: ttsManager.currentSentenceDuration)
            suppressTTSSync = false
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .active {
            syncUIToTTSProgressIfNeeded()
        }
    }

    func syncUIToTTSProgressIfNeeded() {
        guard ttsManager.isPlaying, ttsManager.bookUrl == book.bookUrl else { return }
        ttsBaseIndex = ttsManager.currentBaseSentenceIndex
        let targetChapter = ttsManager.currentChapterIndex

        if targetChapter != currentChapterIndex {
            if switchChapterUsingCacheIfAvailable(targetIndex: targetChapter, jumpToFirst: false, jumpToLast: false) {
                syncPageForSentenceIndex(ttsManager.currentSentenceIndex)
            } else {
                currentChapterIndex = targetChapter
                shouldSyncPageAfterPagination = true
                loadChapterContent()
            }
            return
        }

        if preferences.readingMode == .horizontal {
            syncPageForSentenceIndex(ttsManager.currentSentenceIndex)
        } else {
            let absoluteIndex = ttsManager.currentSentenceIndex + ttsBaseIndex
            pendingScrollToSentenceIndex = absoluteIndex
            handlePendingScroll()
        }
    }

    func requestTTSPlayback(pageIndexOverride: Int?, showControls: Bool) {
        if contentSentences.isEmpty {
            pendingTTSRequest = TTSPlayRequest(pageIndexOverride: pageIndexOverride, showControls: showControls)
            return
        }
        ttsManager.stop()
        startTTS(pageIndexOverride: pageIndexOverride, showControls: showControls)
    }

    func globalCharIndexForSentence(_ index: Int) -> Int? {
        guard index >= 0, index < currentCache.paragraphStarts.count else { return nil }
        return currentCache.paragraphStarts[index] + currentCache.chapterPrefixLen
    }

    func pageIndexForSentence(_ index: Int) -> Int? {
        guard let charIndex = globalCharIndexForSentence(index) else { return nil }
        return currentCache.pages.firstIndex { NSLocationInRange(charIndex, $0.globalRange) }
    }

    func syncPageForSentenceIndex(_ index: Int) {
        guard index >= 0, preferences.readingMode == .horizontal else { return }
        let realIndex = index + ttsBaseIndex

        if currentCache.pages.indices.contains(currentPageIndex), let sentenceStart = globalCharIndexForSentence(realIndex) {
            let pageRange = currentCache.pages[currentPageIndex].globalRange
            let sentenceLen = contentSentences.indices.contains(realIndex) ? contentSentences[realIndex].utf16.count : 0
            let sentenceRange = NSRange(location: sentenceStart, length: sentenceLen)
            if (sentenceLen > 0 && NSIntersectionRange(sentenceRange, pageRange).length > 0) || NSLocationInRange(sentenceStart, pageRange) { return }
        }

        if let pageIndex = pageIndexForSentence(realIndex) ?? (globalCharIndexForSentence(realIndex).flatMap { ensurePagesForCharIndex($0) }), pageIndex != currentPageIndex {
            isTTSSyncingPage = true
            isAutoFlipping = true // 标记为自动翻页，防止 handlePageIndexChange 重启播放
            // 使用动画请求进行 TTS 自动翻页
            pageTurnRequest = PageTurnRequest(direction: .forward, animated: true, targetIndex: pageIndex)

            // 延长锁定期，确保动画和状态稳定
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.isTTSSyncingPage = false
                self.isAutoFlipping = false
            }
        }
    }

    func scheduleAutoFlip(duration: TimeInterval) {
        guard duration > 0, ttsManager.isPlaying, preferences.readingMode == .horizontal else { return }

        pendingFlipId = UUID()
        let taskId = pendingFlipId
        let realIndex = ttsManager.currentSentenceIndex + ttsBaseIndex

        guard currentCache.pages.indices.contains(currentPageIndex), let sentenceStart = globalCharIndexForSentence(realIndex) else { return }
        let sentenceLen = contentSentences.indices.contains(realIndex) ? contentSentences[realIndex].utf16.count : 0
        guard sentenceLen > 0 else { return }

        let sentenceRange = NSRange(location: sentenceStart, length: sentenceLen)
        let pageRange = currentCache.pages[currentPageIndex].globalRange
        let intersection = NSIntersectionRange(sentenceRange, pageRange)

        if sentenceStart >= pageRange.location, NSMaxRange(sentenceRange) > NSMaxRange(pageRange), intersection.length > 0 {
            let delay = duration * (Double(intersection.length) / Double(sentenceLen))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if self.pendingFlipId == taskId {
                    self.isAutoFlipping = true
                    self.goToNextPage()
                }
            }
        }
    }

    func toggleTTS() {
        if ttsManager.isPlaying {
            if ttsManager.isPaused {
                if preferences.readingMode == .horizontal, let pci = pausedChapterIndex, let ppi = pausedPageIndex, (pci != currentChapterIndex || ppi != currentPageIndex || needsTTSRestartAfterPause) {
                    ttsManager.stop(); startTTS(pageIndexOverride: currentPageIndex)
                } else {
                    ttsManager.resume()
                }
            } else {
                pausedChapterIndex = currentChapterIndex; pausedPageIndex = currentPageIndex; ttsManager.pause()
            }
        } else {
            startTTS()
        }
        needsTTSRestartAfterPause = false
    }

    func startTTS(pageIndexOverride: Int? = nil, showControls: Bool = true) {
        if showControls { showUIControls = true }
        suppressTTSSync = true
        needsTTSRestartAfterPause = false

        var startIndex = lastTTSSentenceIndex ?? 0
        var textForTTS = contentSentences.joined(separator: "\n")
        let pageIndex = pageIndexOverride ?? currentPageIndex

        if preferences.readingMode == .horizontal, let pageRange = pageRange(for: pageIndex), let pageStartIndex = pageStartSentenceIndex(for: pageIndex) {
            startIndex = pageStartIndex
            if currentCache.paragraphStarts.indices.contains(startIndex) {
                let sentenceStartGlobal = currentCache.paragraphStarts[startIndex] + currentCache.chapterPrefixLen
                let offset = max(0, pageRange.location - sentenceStartGlobal)

                if offset > 0 && startIndex < contentSentences.count {
                    let firstSentence = contentSentences[startIndex]
                    if offset < firstSentence.utf16.count, let strIndex = String.Index(firstSentence.utf16.index(firstSentence.utf16.startIndex, offsetBy: offset), within: firstSentence) {
                        var sentences = [String(firstSentence[strIndex...])]
                        if startIndex + 1 < contentSentences.count { sentences.append(contentsOf: contentSentences[(startIndex + 1)...]) }
                        textForTTS = sentences.joined(separator: "\n")
                        ttsBaseIndex = startIndex; startIndex = 0
                    }
                } else if startIndex < contentSentences.count {
                    textForTTS = Array(contentSentences[startIndex...]).joined(separator: "\n")
                    ttsBaseIndex = startIndex; startIndex = 0
                }
            }
        } else {
            startIndex = currentVisibleSentenceIndex ?? startIndex
            ttsBaseIndex = 0
        }

        guard !textForTTS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lastTTSSentenceIndex = ttsBaseIndex + startIndex
        ttsManager.currentBaseSentenceIndex = ttsBaseIndex

        let speakTitle = preferences.readingMode == .horizontal && pageIndex == 0 && currentCache.chapterPrefixLen > 0
        ttsManager.startReading(text: textForTTS, chapters: chapters, currentIndex: currentChapterIndex, bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, bookTitle: book.name ?? "阅读", coverUrl: book.displayCoverUrl, onChapterChange: { newIndex in
            self.isAutoFlipping = true
            if self.switchChapterUsingCacheIfAvailable(targetIndex: newIndex, jumpToFirst: true, jumpToLast: false) {
                self.lastTTSSentenceIndex = 0
                self.saveProgress()
                return
            }
            self.isTTSAutoChapterChange = true
            self.didApplyResumePos = true
            self.currentVisibleSentenceIndex = nil
            self.currentChapterIndex = newIndex
            self.pendingTTSRequest = nil
            self.loadChapterContent()
            self.saveProgress()
        }, startAtSentenceIndex: startIndex, shouldSpeakChapterTitle: speakTitle)
    }
}
