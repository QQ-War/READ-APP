import SwiftUI

extension ReaderContainerViewController {
    func refreshCurrentChapter() {
        loadChapterContent(at: currentChapterIndex, cachePolicy: .refresh, allowPrefetch: false)
    }

    func loadChapters() {
        Task {
            await MainActor.run { self.onLoadingChanged?(true) }
            do {
                let list = try await APIService.shared.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
                await MainActor.run {
                    self.chapters = list
                    self.onChaptersLoaded?(list)
                    // 如果 TTS 正在播放这本书，优先同步到 TTS 的章节
                    if ttsManager.isPlaying && ttsManager.bookUrl == book.bookUrl {
                        self.currentChapterIndex = ttsManager.currentChapterIndex
                        self.onChapterIndexChanged?(self.currentChapterIndex)
                    }
                    loadChapterContent(at: currentChapterIndex)
                }
            } catch {
                if Task.isCancelled || error is CancellationError {
                    await MainActor.run { self.onLoadingChanged?(false) }
                    return
                }
                await MainActor.run {
                    self.onLoadingChanged?(false)
                    let errorMsg = "获取目录失败: \(error.localizedDescription)\n\n[点击屏幕中心呼出菜单，点击右上角刷新按钮重试]"
                    // 使用当前 loadToken 确保渲染请求有效
                    self.processLoadedChapterContent(index: currentChapterIndex, rawContent: errorMsg, isManga: false, startAtEnd: false, token: self.loadToken)
                }
            }
        }
    }

    func loadChapterContent(at index: Int, startAtEnd: Bool = false, cachePolicy: ChapterContentFetchPolicy = .standard, allowPrefetch: Bool = true) {
        loadToken += 1
        let token = loadToken
        Task { [weak self] in
            guard let self = self else { return }

            await MainActor.run { self.onLoadingChanged?(true) }
            defer { Task { @MainActor in if self.loadToken == token { self.onLoadingChanged?(false) } } }

            let isM = book.type == 2 || readerSettings.manualMangaUrls.contains(book.bookUrl ?? "")
            if !isM || !allowPrefetch {
                await MainActor.run { self.resetMangaPrefetchedContent() }
            }
            if allowPrefetch, isM {
                let cached = await MainActor.run { self.consumePrefetchedMangaContent(for: index) }
                if let cached = cached {
                await MainActor.run {
                    self.processLoadedChapterContent(index: index, rawContent: cached, isManga: isM, startAtEnd: startAtEnd, token: token)
                }
                return
            }
            }
            do {
                let realIndex = chapters.indices.contains(index) ? chapters[index].index : index
                let contentType = (book.type == 2) ? 2 : (book.type == 1 ? 1 : 0)
                let content = try await APIService.shared.fetchChapterContent(
                    bookUrl: book.bookUrl ?? "",
                    bookSourceUrl: book.origin,
                    index: realIndex,
                    contentType: contentType,
                    cachePolicy: cachePolicy
                )
                await MainActor.run {
                    self.processLoadedChapterContent(index: index, rawContent: content, isManga: isM, startAtEnd: startAtEnd, token: token)
                }
            } catch {
                if Task.isCancelled || error is CancellationError {
                    return
                }
                await MainActor.run {
                    let errorMsg = "加载失败: \(error.localizedDescription)\n\n[点击屏幕中心呼出菜单，点击右上角刷新按钮重试]"
                    self.processLoadedChapterContent(index: index, rawContent: errorMsg, isManga: false, startAtEnd: false, token: token)
                }
            }
        }
    }

    func processLoadedChapterContent(index: Int, rawContent: String, isManga: Bool, startAtEnd: Bool, token: Int) {
        guard loadToken == token else { return }
        defer { self.isInternalTransitioning = false }
        let rewrittenContent = ImageGatewayService.shared.rewriteLocalEpubImageSourcesIfNeeded(rawContent, book: book)
        let trimmed = rewrittenContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedManga = isManga
        self.isMangaMode = resolvedManga
        self.onModeDetected?(resolvedManga)

        // 核心修复：如果目录还没加载成功（chapters 为空），仅渲染文字内容（错误提示），跳过后续逻辑
        if chapters.isEmpty {
            reRenderCurrentContent(rawContentOverride: rewrittenContent, anchorOffset: 0)
            return
        }

        // 尝试重用预取缓存 (方案 2：性能优化并避免重新分页导致的 1/2 Bug)
        let chapterUrl = chapters.indices.contains(index) ? chapters[index].url : nil
        var cacheUsed = false
        if !resolvedManga, let url = chapterUrl {
            if prevCache.chapterUrl == url && !prevCache.pages.isEmpty {
                currentCache = prevCache
                prevCache = .empty
                cacheUsed = true
            } else if nextCache.chapterUrl == url && !nextCache.pages.isEmpty {
                currentCache = nextCache
                nextCache = .empty
                cacheUsed = true
            }
        }

        if cacheUsed {
            // 已从缓存加载，根据进入方向预设初始页码
            if startAtEnd {
                self.currentPageIndex = max(0, currentCache.pages.count - 1)
            } else {
                self.currentPageIndex = 0
            }
            
            // 显式刷新 UI 容器前重置滚动状态，防止滑动撞墙
            newHorizontalVC?.resetScrollState()
            
            if currentReadingMode == .newHorizontal {
                updateNewHorizontalContent()
            } else if currentReadingMode == .horizontal {
                updateHorizontalPage(to: currentPageIndex, animated: false)
            } else if currentReadingMode == .vertical {
                updateVerticalAdjacent()
            }
            
            setupReaderMode()
            updateProgressUI()
        } else if self.isFirstLoad && !resolvedManga {
            let initialOffset: Int
            if self.ttsManager.isPlaying && self.ttsManager.bookUrl == self.book.bookUrl && self.ttsManager.currentChapterIndex == index {
                initialOffset = self.ttsManager.currentCharOffset
            } else {
                // 将 Double 进度转换为字符偏移
                let durPos = self.book.durChapterPos ?? 0
                initialOffset = Int(durPos * Double(rawContent.count))
            }
            // 首次加载且是水平模式，使用锚点分页保持位置
            reRenderCurrentContent(rawContentOverride: rewrittenContent, anchorOffset: (currentReadingMode == .horizontal || currentReadingMode == .newHorizontal) ? initialOffset : 0)
        } else {
            // 无论是翻回上一章还是正常进入，加载新章节时统一使用起点分页
            // 这样能保持分页序列自然（1/1），后续由 scrollToChapterEnd 负责定位到末尾
            reRenderCurrentContent(rawContentOverride: rewrittenContent, anchorOffset: 0)
        }

        if isMangaMode { nextCache = .empty }

        if self.isFirstLoad {
            self.isFirstLoad = false
            if !resolvedManga {
                if self.ttsManager.isPlaying && self.ttsManager.bookUrl == self.book.bookUrl && self.ttsManager.currentChapterIndex == index {
                    let sentenceIdx = self.ttsManager.currentSentenceIndex
                    if self.currentReadingMode == .horizontal || self.currentReadingMode == .newHorizontal {
                        // 已经通过锚点分页了，直接跳到 anchorPageIndex
                        self.updateHorizontalPage(to: self.currentCache.anchorPageIndex, animated: false)
                    } else {
                        self.verticalVC?.scrollToSentence(index: sentenceIdx, animated: false)
                    }
                } else {
                    if self.currentReadingMode == .horizontal || self.currentReadingMode == .newHorizontal {
                        self.updateHorizontalPage(to: self.currentCache.anchorPageIndex, animated: false)
                    } else {
                        let pos = self.book.durChapterPos ?? 0
                        self.verticalVC?.scrollToProgress(pos)
                    }
                }
            } else {
                // 漫画模式首次加载恢复
                let pos = self.book.durChapterPos ?? 0
                let total = self.currentCache.contentSentences.count
                let targetIdx = Int(pos * Double(total))
                self.mangaVC?.scrollToIndex(targetIdx, animated: false)
            }
        } else if startAtEnd {
            self.scrollToChapterEnd(animated: false)
        } else {
            if !isManga {
                if currentReadingMode == .horizontal || currentReadingMode == .newHorizontal {
                    self.updateHorizontalPage(to: 0, animated: false)
                }
                self.verticalVC?.scrollToTop(animated: false)
            } else {
                self.mangaVC?.scrollToIndex(0, animated: false)
            }
        }
        self.prefetchAdjacentChapters(index: index)
        self.syncTTSReadingPositionIfNeeded()
    }

}
