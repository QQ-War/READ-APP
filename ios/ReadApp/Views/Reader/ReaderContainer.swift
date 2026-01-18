import SwiftUI
import UIKit

// MARK: - 布局规范
struct ReaderLayoutSpec {
    let topInset: CGFloat
    let bottomInset: CGFloat
    let sideMargin: CGFloat
    let pageSize: CGSize
}

// MARK: - SwiftUI 桥接入口
struct ReaderContainerRepresentable: UIViewControllerRepresentable {
    let book: Book
    @ObservedObject var readerSettings: ReaderSettingsStore
    @ObservedObject var ttsManager: TTSManager
    @ObservedObject var replaceRuleViewModel: ReplaceRuleViewModel
    
    @Binding var chapters: [BookChapter]
    @Binding var currentChapterIndex: Int
    @Binding var isMangaMode: Bool
    @Binding var isLoading: Bool // 新增
    
    var onToggleMenu: () -> Void
    var onAddReplaceRule: (String) -> Void
    var onProgressChanged: (Int, Double) -> Void
    var onToggleTTS: ((@escaping () -> Void) -> Void)?
    var onRefreshChapter: ((@escaping () -> Void) -> Void)?
    var readingMode: ReadingMode
    var safeAreaInsets: EdgeInsets 
    
    class Coordinator {
        var parent: ReaderContainerRepresentable
        init(_ parent: ReaderContainerRepresentable) { self.parent = parent }
        func handleChapterChange(_ index: Int) {
            DispatchQueue.main.async { self.parent.currentChapterIndex = index }
        }
        func handleProgress(_ idx: Int, _ pos: Double) {
            self.parent.onProgressChanged(idx, pos)
        }
        func handleChaptersLoaded(_ list: [BookChapter]) {
            DispatchQueue.main.async { self.parent.chapters = list }
        }
        func handleModeDetected(_ isManga: Bool) {
            DispatchQueue.main.async { self.parent.isMangaMode = isManga }
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeUIViewController(context: Context) -> ReaderContainerViewController {
        let vc = ReaderContainerViewController()
        vc.book = book; vc.readerSettings = readerSettings; vc.ttsManager = ttsManager
        vc.replaceRuleViewModel = replaceRuleViewModel
        vc.onToggleMenu = onToggleMenu; vc.onAddReplaceRuleWithText = { onAddReplaceRule($0) }
        vc.onChapterIndexChanged = { idx in context.coordinator.handleChapterChange(idx) }
        vc.onProgressChanged = { idx, pos in context.coordinator.handleProgress(idx, pos) }
        vc.onChaptersLoaded = { list in context.coordinator.handleChaptersLoaded(list) }
        vc.onModeDetected = { isManga in context.coordinator.handleModeDetected(isManga) }
        vc.onLoadingChanged = { loading in DispatchQueue.main.async { self.isLoading = loading } }
        onToggleTTS?({ [weak vc] in vc?.toggleTTS() })
        onRefreshChapter?({ [weak vc] in vc?.refreshCurrentChapter() })
        return vc
    }
    
    func updateUIViewController(_ vc: ReaderContainerViewController, context: Context) {
        context.coordinator.parent = self
        vc.updateLayout(safeArea: safeAreaInsets)
        vc.updateSettings(readerSettings)
        vc.updateReplaceRules(replaceRuleViewModel.rules)
        vc.verticalThreshold = readerSettings.verticalThreshold
        
        // 外部跳转检测逻辑优化
        if !vc.isInternalTransitioning && vc.lastReportedChapterIndex != currentChapterIndex {
            vc.jumpToChapter(currentChapterIndex)
        }
        
        if vc.currentReadingMode != readingMode { vc.switchReadingMode(to: readingMode) }
        vc.syncTTSState()
    }
}

// MARK: - UIKit 核心容器
class ReaderContainerViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIScrollViewDelegate {
    let logger = LogManager.shared
    var book: Book!; var chapters: [BookChapter] = []; var readerSettings: ReaderSettingsStore!; var ttsManager: TTSManager!; var replaceRuleViewModel: ReplaceRuleViewModel?
    var onToggleMenu: (() -> Void)?; var onAddReplaceRuleWithText: ((String) -> Void)?; var onProgressChanged: ((Int, Double) -> Void)?
    var onChapterIndexChanged: ((Int) -> Void)?; var onChaptersLoaded: (([BookChapter]) -> Void)?; var onModeDetected: ((Bool) -> Void)?; var onLoadingChanged: ((Bool) -> Void)?
    
    var safeAreaTop: CGFloat = 47; var safeAreaBottom: CGFloat = 34
    var currentLayoutSpec: ReaderLayoutSpec {
        return ReaderLayoutSpec(
            topInset: max(safeAreaTop, view.safeAreaInsets.top) + 15,
            bottomInset: max(safeAreaBottom, view.safeAreaInsets.bottom) + 40,
            sideMargin: readerSettings.pageHorizontalMargin + 8,
            pageSize: view.bounds.size
        )
    }

    
    var currentChapterIndex: Int = 0
    var lastReportedChapterIndex: Int = -1
    var verticalThreshold: CGFloat = 80 {
        didSet {
            verticalVC?.threshold = verticalThreshold
            mangaVC?.threshold = verticalThreshold
        }
    }
        var currentReadingMode: ReadingMode = .vertical
        private var activePaginationAnchor: Int = 0 // 分页锚点
        var isInternalTransitioning = false
        var isFirstLoad = true
        private var isUserInteracting = false
        private var ttsSyncCoordinator: TTSReadingSyncCoordinator?
        
        var chapterBuilder: ReaderChapterBuilder?
        var currentCache: ChapterCache = .empty
        var nextCache: ChapterCache = .empty
        var prevCache: ChapterCache = .empty
        var currentPageIndex: Int = 0
        private var visibleHorizontalPageIndex: Int? {
            guard let pageVC = horizontalVC?.viewControllers?.first as? PageContentViewController else { return nil }
            guard pageVC.chapterOffset == 0 else { return nil }
            return pageVC.pageIndex
        }
        func horizontalPageIndexForDisplay() -> Int {
            if let visible = visibleHorizontalPageIndex, visible >= 0, visible < currentCache.pages.count {
                return visible
            }
            return currentPageIndex
        }
        private func previewSentences(from startIndex: Int, limit: Int) -> [String] {
            guard !currentCache.contentSentences.isEmpty else { return [] }
            var lines: [String] = []
            for idx in startIndex..<min(startIndex + limit, currentCache.contentSentences.count) {
                lines.append(sanitizedPreviewText(currentCache.contentSentences[idx]))
            }
            return lines
        }
        private func sanitizedPreviewText(_ text: String) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
            guard trimmed.count > 120 else { return trimmed }
            let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 120)
            return String(trimmed[..<endIndex]) + "…"
        }
        private func visibleTopSentenceInfo() -> (index: Int, sentences: [String]) {
            guard !currentCache.contentSentences.isEmpty else { return (0, []) }
            let startIndex: Int
            if currentReadingMode == .vertical {
                startIndex = verticalVC?.getCurrentSentenceIndex() ?? 0
            } else {
                let pageIndex = horizontalPageIndexForDisplay()
                if let pageInfos = currentCache.pageInfos, pageIndex < pageInfos.count {
                    startIndex = pageInfos[pageIndex].startSentenceIndex
                } else {
                    startIndex = 0
                }
            }
            let sentences = previewSentences(from: startIndex, limit: 2)
            return (startIndex, sentences)
        }
        private func horizontalPageStartSnippet(for pageIndex: Int, limit: Int) -> String {
            guard let pageInfos = currentCache.pageInfos, pageIndex < pageInfos.count else { return "" }
            let range = pageInfos[pageIndex].range
            let attributed = currentCache.attributedText.string as NSString
            let validLen = max(0, min(limit, attributed.length - range.location))
            guard validLen > 0 else { return "" }
            let fragment = attributed.substring(with: NSRange(location: range.location, length: validLen))
            return sanitizedPreviewText(fragment)
        }
        var isMangaMode = false
        var latestVisibleFragmentLines: [String] = []
    
            var verticalVC: VerticalTextViewController?; var horizontalVC: UIPageViewController?; var mangaVC: MangaReaderViewController?
            var prebuiltNextMangaVC: MangaReaderViewController?
                var prebuiltNextIndex: Int?
                
                let progressLabel = UILabel()
                private var lastLayoutSignature: String = ""
                var loadToken: Int = 0
                let prefetchCoordinator = ReaderPrefetchCoordinator()
        private var pendingTTSPositionSync = false
        var prefetchedMangaNextIndex: Int?
        var prefetchedMangaNextContent: String?
        var lastChapterSwitchTime: TimeInterval = 0
        let chapterSwitchCooldown: TimeInterval = 1.0
        private var suppressTTSFollowUntil: TimeInterval = 0
        private var lastLoggedCacheChapterIndex: Int = -1
        private var lastLoggedNextUrl: String?
        private var lastLoggedPrevUrl: String?
        private var lastLoggedNextCount: Int = -1
        private var lastLoggedPrevCount: Int = -1
    
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = readerSettings.readingTheme.backgroundColor
            setupProgressLabel()
            currentChapterIndex = book.durChapterIndex ?? 0
            lastReportedChapterIndex = currentChapterIndex
            currentReadingMode = readerSettings.readingMode
            
            // 初始加载设锚点为书籍保存的进度
            if currentReadingMode == .horizontal {
                // 注意：如果是首次进入且为水平模式，由于此时排版未完成，
                // 锚点将稍后在 processLoadedChapterContent 中应用
            }
            
            chapterBuilder = ReaderChapterBuilder(readerSettings: readerSettings, replaceRules: replaceRuleViewModel?.rules)
            loadChapters()
            ttsSyncCoordinator = TTSReadingSyncCoordinator(reader: self, ttsManager: ttsManager)
            ttsSyncCoordinator?.start()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // 退出阅读器时强制保存进度
            Task {
                let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
                var pos: Double = 0.0
                if currentReadingMode == .vertical {
                    if isMangaMode {
                        pos = Double(mangaVC?.currentVisibleIndex ?? 0)
                    } else {
                        let count = max(1, currentCache.contentSentences.count)
                        let idx = verticalVC?.lastReportedIndex ?? 0
                        pos = Double(idx) / Double(count)
                    }
                } else if !currentCache.pages.isEmpty {
                    // 水平模式
                    pos = Double(currentPageIndex) / Double(currentCache.pages.count)
                }
                
                // 本地和远程同步
                UserDefaults.standard.set(currentChapterIndex, forKey: "lastChapter_\(book.bookUrl ?? "")")
                try? await APIService.shared.saveBookProgress(bookUrl: book.bookUrl ?? "", index: currentChapterIndex, pos: pos, title: title)
            }
        }
        
        private func setupProgressLabel() {
            progressLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular); progressLabel.textColor = .secondaryLabel
            view.addSubview(progressLabel); progressLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([progressLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), progressLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4)])
        }
        
                private var lastKnownSize: CGSize = .zero
        
                private var pendingRelocationOffset: Int? // 记录正在进行的跳转目标
        
                
        
                override func viewDidLayoutSubviews() {
        
                    super.viewDidLayoutSubviews()
        
                    guard !isInternalTransitioning else { return }
        
                    let b = view.bounds; verticalVC?.view.frame = b; horizontalVC?.view.frame = b; mangaVC?.view.frame = b
        
                    
        
                    if b.size != lastKnownSize {
        
                        let spec = currentLayoutSpec
        
                        let signature = "\(Int(spec.pageSize.width))x\(Int(spec.pageSize.height))|\(Int(spec.topInset))"
        
                        if signature != lastLayoutSignature {
        
                            lastLayoutSignature = signature
        
                            lastKnownSize = b.size
        
                            if !isMangaMode, currentCache.renderStore != nil, currentReadingMode == .horizontal {
        
                                rebuildPaginationForLayout()
        
                            }
        
                        }
        
                    }
        
                }
        
            
        
                func updateLayout(safeArea: EdgeInsets) { self.safeAreaTop = safeArea.top; self.safeAreaBottom = safeArea.bottom }
        
        func updateSettings(_ settings: ReaderSettingsStore) {
            let oldSettings = self.readerSettings!
            self.readerSettings = settings
            chapterBuilder?.updateSettings(settings)
            view.backgroundColor = settings.readingTheme.backgroundColor
            verticalVC?.view.backgroundColor = settings.readingTheme.backgroundColor
            horizontalVC?.view.backgroundColor = settings.readingTheme.backgroundColor
            mangaVC?.view.backgroundColor = settings.readingTheme.backgroundColor

            // 检测关键布局参数是否改变
            let layoutChanged = oldSettings.fontSize != settings.fontSize ||
                                oldSettings.lineSpacing != settings.lineSpacing ||
                                oldSettings.pageHorizontalMargin != settings.pageHorizontalMargin ||
                                oldSettings.readingFontName != settings.readingFontName ||
                                oldSettings.readingTheme != settings.readingTheme

            // 如果正在进行模式切换跳转，不在此处重新捕获进度，防止捕获到临时的 Offset 0
            let currentOffset = pendingRelocationOffset ?? getCurrentReadingCharOffset()

            if let v = verticalVC, v.isInfiniteScrollEnabled != settings.isInfiniteScrollEnabled {
                v.isInfiniteScrollEnabled = settings.isInfiniteScrollEnabled
                if !isMangaMode && currentReadingMode == .vertical {
                    updateVerticalAdjacent()
                }
            }

            if layoutChanged && !isMangaMode {
                // 无论是水平还是垂直模式，重绘时都带上锚点以保持位置
                reRenderCurrentContent(anchorOffset: currentOffset)
                
                // 只有在布局真正改变时，才在垂直模式下执行行级对齐滚动
                if currentReadingMode == .vertical && pendingRelocationOffset == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                        self?.scrollToCharOffset(currentOffset, animated: false)
                    }
                }
            } else if !isMangaMode && currentReadingMode == .vertical {
                // 如果布局没变，仅更新相邻章节状态，不再强制滚动
                updateVerticalAdjacent()
            }
        }
        
                
        
        func updateReplaceRules(_ rules: [ReplaceRule]) {
            let oldRules = ttsManager.replaceRules
            chapterBuilder?.updateReplaceRules(rules)
            ttsManager.replaceRules = rules
            
            // 只有当规则真的发生变化且非漫画模式时，才触发重绘
            if oldRules != rules && !isMangaMode {
                if !currentCache.rawContent.isEmpty {
                    let currentOffset = pendingRelocationOffset ?? getCurrentReadingCharOffset()
                    // 无论是水平还是垂直模式，重绘都应带上锚点
                    reRenderCurrentContent(anchorOffset: currentOffset)
                } else if currentReadingMode == .vertical {
                    updateVerticalAdjacent()
                }
            }
        }
        
                
        
                func jumpToChapter(_ index: Int, startAtEnd: Bool = false) {
        
                    activePaginationAnchor = 0 
        
                    currentChapterIndex = index; lastReportedChapterIndex = index; onChapterIndexChanged?(index)
                    performChapterTransitionFade { [weak self] in
                        self?.loadChapterContent(at: index, startAtEnd: startAtEnd)
                    }
        
                }
        
            
        
                                func switchReadingMode(to mode: ReadingMode) {
        
            
        
                                    let offset = getCurrentReadingCharOffset()
        
            
        
                                    currentReadingMode = mode
        
                    
        
                    // 关键：设置挂起目标，防止跳转过程中进度被覆盖
        
                    pendingRelocationOffset = offset
        
        
                    
        
                    if mode == .horizontal {
        
                        reRenderCurrentContent(anchorOffset: offset)
        
                        pendingRelocationOffset = nil // 水平模式重渲染即完成定位
        
                    } else {
        
                        setupReaderMode()
        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
        
                            guard let self = self else { return }
        
                            self.scrollToCharOffset(offset, animated: false)
        
                            self.pendingRelocationOffset = nil // 完成后解锁
        
                        }
        
                    }
        
                }
        
                
        
                    func getCurrentReadingCharOffset() -> Int {
        
                
        
                        // 如果有挂起的跳转，优先返回跳转目标，避免在视图未准备好时探测到 0
        
                
        
                        if let pending = pendingRelocationOffset {
        
                
        
        
                
        
                            return pending
        
                
        
                        }
        
                
        
                        
        
                
        
                        let offset: Int
        
                
        
                        if currentReadingMode == .vertical {
        
                
        
                            offset = verticalVC?.getCurrentCharOffset() ?? 0
        
                
        
        
                
        
                        } else if !currentCache.pages.isEmpty {
        
                
        
                            let idx = horizontalPageIndexForDisplay()
        
                
        
                            if idx < currentCache.pages.count {
        
                
        
                                offset = currentCache.pages[idx].globalRange.location
        
                
        
        
                
        
                            } else {
        
                
        
                                offset = 0
        
                
        
                            }
        
                
        
                        } else {
        
                
        
                            offset = 0
        
                
        
                        }
        
                
        
                        return offset
        
                
        
                    }
        
        func scrollToCharOffset(_ offset: Int, animated: Bool) {
            if currentReadingMode == .vertical {
                verticalVC?.scrollToCharOffset(offset, animated: animated)
            } else {
                if let targetPage = currentCache.pages.firstIndex(where: { NSLocationInRange(offset, $0.globalRange) }) {
                    updateHorizontalPage(to: targetPage, animated: animated)
                } else {
                }
            }
        }
    
        
    
    func toggleTTS() {
        if ttsManager.isPlaying {
            if ttsManager.isPaused { ttsManager.resume() }
            else { ttsManager.pause() }
        } else {
            guard currentChapterIndex < chapters.count else { return }
            let startPos = currentStartPosition()
            
            let ttsSentences = currentCache.contentSentences
            ttsManager.startReading(
                text: currentCache.rawContent,
                chapters: chapters,
                currentIndex: currentChapterIndex,
                bookUrl: book.bookUrl ?? "",
                bookSourceUrl: book.origin,
                bookTitle: book.name ?? "未知书名",
                coverUrl: book.coverUrl,
                onChapterChange: { [weak self] newIndex in
                    guard let self = self else { return }
                    Task { @MainActor in
                        if self.currentReadingMode == .horizontal && newIndex == self.currentChapterIndex + 1 && !self.nextCache.pages.isEmpty {
                            self.animateToAdjacentChapter(offset: 1, targetPage: 0)
                        } else if self.currentReadingMode == .horizontal && newIndex == self.currentChapterIndex - 1 && !self.prevCache.pages.isEmpty {
                            self.animateToAdjacentChapter(offset: -1, targetPage: self.prevCache.pages.count - 1)
                        } else if self.currentReadingMode == .vertical && self.readerSettings.isInfiniteScrollEnabled {
                            // 垂直无限流平滑换章
                            let offset = newIndex - self.currentChapterIndex
                            self.suppressTTSFollowUntil = Date().timeIntervalSince1970 + 0.5
                            self.switchChapterSeamlessly(offset: offset)
                        } else {
                            self.jumpToChapter(newIndex)
                        }
                    }
                },
                processedSentences: ttsSentences,
                textProcessor: { [rules = replaceRuleViewModel?.rules] text in
                    ReadingTextProcessor.prepareText(text, rules: rules)
                },
                replaceRules: replaceRuleViewModel?.rules,
                startAtSentenceIndex: startPos.sentenceIndex,
                startAtSentenceOffset: startPos.sentenceOffset,
                shouldSpeakChapterTitle: startPos.isAtChapterStart
            )
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        notifyUserInteractionStarted()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            notifyUserInteractionEnded()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        notifyUserInteractionEnded()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        notifyUserInteractionEnded()
    }


    private func switchChapterSeamlessly(offset: Int) {
        guard offset != 0 else { return }
        let canSwap = (offset > 0 && nextCache.renderStore != nil) || (offset < 0 && prevCache.renderStore != nil)
        if canSwap {
            if offset > 0 {
                prevCache = currentCache
                currentCache = nextCache
                nextCache = .empty
            } else {
                nextCache = currentCache
                currentCache = prevCache
                prevCache = .empty
            }
            self.currentChapterIndex += offset
            self.lastReportedChapterIndex = self.currentChapterIndex
            self.onChapterIndexChanged?(self.currentChapterIndex)
            updateVerticalAdjacent()
            prefetchAdjacentChapters(index: currentChapterIndex)
        } else {
            jumpToChapter(currentChapterIndex + offset, startAtEnd: offset < 0)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { return nil }
    func syncTTSState() {
        if isMangaMode { return }
        guard ttsManager.isReady else { return }
        
        // 跨章预判：如果 TTS 已经进入下一章，且我们处于垂直无限流模式
        if currentReadingMode == .vertical && readerSettings.isInfiniteScrollEnabled {
            if ttsManager.currentChapterIndex == currentChapterIndex + 1 && nextCache.renderStore != nil {
                // TTS 已经超前进入下一章，主动发起平滑切换
                let now = Date().timeIntervalSince1970
                if now >= suppressTTSFollowUntil {
                    suppressTTSFollowUntil = now + 0.5
                    switchChapterSeamlessly(offset: 1)
                    return
                }
            }
        }

        // 确保阅读器记录的章节索引与 TTS 一致
        guard ttsManager.currentChapterIndex == currentChapterIndex else { return }
        if chapters.indices.contains(currentChapterIndex) {
            guard currentCache.chapterUrl == chapters[currentChapterIndex].url else { return }
        }
        
        let sentenceIndex = ttsManager.currentSentenceIndex
        
        // 1. 垂直模式：局部高亮更新，避免全局刷新
        if currentReadingMode == .vertical { 
            var finalIdx: Int? = sentenceIndex
            var secondaryIdxs = Set(ttsManager.preloadedIndices)
            
            if ttsManager.hasChapterTitleInSentences {
                if ttsManager.isReadingChapterTitle {
                    finalIdx = nil
                } else {
                    finalIdx = sentenceIndex - 1
                }
                secondaryIdxs = Set(ttsManager.preloadedIndices.compactMap { $0 > 0 ? ($0 - 1) : nil })
            }
            
            verticalVC?.setHighlight(index: finalIdx, secondaryIndices: secondaryIdxs, isPlaying: ttsManager.isPlaying)
        }

        // 2. 视口跟随逻辑 (只有在非交互状态下执行)
        let now = Date().timeIntervalSince1970
        guard !isUserInteracting, ttsManager.isPlaying, now >= suppressTTSFollowUntil else { return }

        if currentReadingMode == .vertical {
            // 垂直模式：利用优化后的 ensureSentenceVisible 实现平滑滚动
            // 内部会根据 charOffset 自动判断是否需要滚动，不再局限于段落开头
            let isVisible = verticalVC?.isSentenceVisible(index: sentenceIndex) ?? true
            if !isVisible {
                verticalVC?.ensureSentenceVisible(index: sentenceIndex)
            } else {
                // 即便可见，如果正在播放，也允许其内部进行微调（例如快出底部时）
                verticalVC?.ensureSentenceVisible(index: sentenceIndex)
            }
        } else if currentReadingMode == .horizontal {
            // 处理标题偏移导致的索引对齐问题
            if ttsManager.isReadingChapterTitle {
                // 如果正在读标题，保持在第一页即可，不执行复杂的正文同步逻辑
                if currentPageIndex != 0 {
                    updateHorizontalPage(to: 0, animated: true)
                }
                return
            }
            
            // 如果播放列表中包含标题，则正文句子的索引需要减 1
            let bodySentenceIdx = ttsManager.hasChapterTitleInSentences ? (sentenceIndex - 1) : sentenceIndex
            guard bodySentenceIdx >= 0 else { return }
            
            let sentenceOffset = ttsManager.currentSentenceOffset
            let starts = currentCache.paragraphStarts
            
            if bodySentenceIdx < starts.count {
                let realTimeOffset = starts[bodySentenceIdx] + sentenceOffset + paragraphIndentLength
                
                let currentIndex = horizontalPageIndexForDisplay()
                if currentIndex < currentCache.pages.count {
                    let currentRange = currentCache.pages[currentIndex].globalRange
                    if !NSLocationInRange(realTimeOffset, currentRange) {
                        if let targetPage = currentCache.pages.firstIndex(where: { NSLocationInRange(realTimeOffset, $0.globalRange) }) {
                            if targetPage != currentPageIndex {
                                updateHorizontalPage(to: targetPage, animated: true)
                            }
                        }
                    }
                }
            }
        }
    }

    func completePendingTTSPositionSync() {
        guard pendingTTSPositionSync else { return }
        pendingTTSPositionSync = false
        syncTTSReadingPositionIfNeeded()
    }

    func handleUserScrollCatchUp() {
        guard pendingTTSPositionSync else { return }
        pendingTTSPositionSync = false
        guard let bookUrl = book.bookUrl, ttsManager.bookUrl == bookUrl else { return }
        guard ttsManager.isPlaying && !ttsManager.isPaused else { return }

        if !isTTSPositionInCurrentPage() {
            restartTTSFromCurrentPageStart()
        } else {
            syncTTSState()
        }
    }

    private func restartTTSFromCurrentPageStart() {
        guard currentChapterIndex < chapters.count else { return }
        let startPos = currentStartPosition()
        let ttsSentences = currentCache.contentSentences
        ttsManager.startReading(
            text: currentCache.rawContent,
            chapters: chapters,
            currentIndex: currentChapterIndex,
            bookUrl: book.bookUrl ?? "",
            bookSourceUrl: book.origin,
            bookTitle: book.name ?? "未知书名",
            coverUrl: book.coverUrl,
            onChapterChange: { [weak self] newIndex in
                guard let self = self else { return }
                Task { @MainActor in
                    if self.currentReadingMode == .horizontal && newIndex == self.currentChapterIndex + 1 && !self.nextCache.pages.isEmpty {
                        self.animateToAdjacentChapter(offset: 1, targetPage: 0)
                    } else if self.currentReadingMode == .horizontal && newIndex == self.currentChapterIndex - 1 && !self.prevCache.pages.isEmpty {
                        self.animateToAdjacentChapter(offset: -1, targetPage: self.prevCache.pages.count - 1)
                    } else if self.currentReadingMode == .vertical && self.readerSettings.isInfiniteScrollEnabled {
                        // 垂直无限流平滑换章
                        let offset = newIndex - self.currentChapterIndex
                        self.suppressTTSFollowUntil = Date().timeIntervalSince1970 + 0.5
                        self.switchChapterSeamlessly(offset: offset)
                    } else {
                        self.jumpToChapter(newIndex)
                    }
                }
            },
            processedSentences: ttsSentences,
            textProcessor: { [rules = replaceRuleViewModel?.rules] text in
                ReadingTextProcessor.prepareText(text, rules: rules)
            },
            replaceRules: replaceRuleViewModel?.rules,
            startAtSentenceIndex: startPos.sentenceIndex,
            startAtSentenceOffset: startPos.sentenceOffset,
            shouldSpeakChapterTitle: startPos.isAtChapterStart
        )
    }

    private func isTTSPositionInCurrentPage() -> Bool {
        guard ttsManager.currentChapterIndex == currentChapterIndex else { return false }
        if currentReadingMode == .vertical {
            return verticalVC?.isSentenceVisible(index: ttsManager.currentSentenceIndex) ?? true
        }
        
        // 标题特殊处理
        if ttsManager.isReadingChapterTitle {
            return currentPageIndex == 0
        }
        
        let pageInfos = currentCache.pageInfos ?? []
        let pageIndex = horizontalPageIndexForDisplay()
        guard pageIndex < pageInfos.count else { return true }
        let starts = currentCache.paragraphStarts
        
        let sentenceIdx = ttsManager.currentSentenceIndex
        let bodySentenceIdx = ttsManager.hasChapterTitleInSentences ? (sentenceIdx - 1) : sentenceIdx
        
        guard bodySentenceIdx >= 0 && bodySentenceIdx < starts.count else { return false }
        let indentLen = 2
        let totalOffset = starts[bodySentenceIdx] + ttsManager.currentSentenceOffset + indentLen
        return NSLocationInRange(totalOffset, pageInfos[pageIndex].range)
    }

    func finalizeUserInteraction() {
        isUserInteracting = false
        suppressTTSFollowUntil = Date().timeIntervalSince1970 + readerSettings.ttsFollowCooldown
        ttsSyncCoordinator?.scheduleCatchUp(delay: readerSettings.ttsFollowCooldown)
    }

    func notifyUserInteractionStarted() {
        isUserInteracting = true
        pendingTTSPositionSync = true
        suppressTTSFollowUntil = Date().timeIntervalSince1970 + readerSettings.ttsFollowCooldown
        ttsSyncCoordinator?.userInteractionStarted()
    }

    func safeToggleMenu() {
        guard !isInternalTransitioning else { return }
        onToggleMenu?()
    }

    func notifyUserInteractionEnded() {
        suppressTTSFollowUntil = Date().timeIntervalSince1970 + readerSettings.ttsFollowCooldown
        ttsSyncCoordinator?.scheduleCatchUp(delay: readerSettings.ttsFollowCooldown)
    }
    
    func syncTTSReadingPositionIfNeeded() {
        guard pendingTTSPositionSync else { return }
        pendingTTSPositionSync = false
        guard let bookUrl = book.bookUrl, ttsManager.bookUrl == bookUrl else { return }
        let position = currentStartPosition()
        ttsManager.updateReadingPosition(to: position)
    }


    deinit {
        prefetchCoordinator.cancel()
        ttsSyncCoordinator?.stop()
    }
    private func currentStartPosition() -> ReadingPosition {
        guard !currentCache.contentSentences.isEmpty else {
            return ReadingPosition(chapterIndex: currentChapterIndex, sentenceIndex: 0, sentenceOffset: 0, charOffset: 0)
        }
        let pageInfos = currentCache.pageInfos ?? []
        let starts = currentCache.paragraphStarts
        guard !starts.isEmpty else {
            return ReadingPosition(chapterIndex: currentChapterIndex, sentenceIndex: 0, sentenceOffset: 0, charOffset: 0)
        }

        var charOffset: Int = 0
        var sentenceIndex: Int = 0

        if currentReadingMode == .horizontal {
            let pageIndex = horizontalPageIndexForDisplay()
            if pageIndex < pageInfos.count {
                let pageInfo = pageInfos[pageIndex]
                charOffset = pageInfo.range.location
                // 直接信任 pageInfo.range.location 作为 charOffset
                // 并用这个值找到对应的 sentenceIndex
                sentenceIndex = starts.lastIndex(where: { $0 <= charOffset }) ?? 0
            }
        } else if currentReadingMode == .vertical {
            charOffset = verticalVC?.getCurrentCharOffset() ?? 0
            // 垂直模式：直接使用 charOffset 作为 sentenceOffset
            // getCurrentCharOffset() 返回的是当前可见区域顶部的行偏移
            // 不需要通过 paragraphStarts 计算偏移
            sentenceIndex = starts.lastIndex(where: { $0 <= charOffset }) ?? 0
        }

        // 边界检查
        sentenceIndex = max(0, min(sentenceIndex, currentCache.contentSentences.count - 1))

        let sentenceStart = starts[sentenceIndex]
        let intra = max(0, charOffset - sentenceStart - paragraphIndentLength)
        let offsetInSentence = intra
        
        let maxLen = currentCache.contentSentences[sentenceIndex].utf16.count
        let clampedOffset = min(maxLen, offsetInSentence)
        
        return ReadingPosition(chapterIndex: currentChapterIndex, sentenceIndex: sentenceIndex, sentenceOffset: clampedOffset, charOffset: charOffset)
    }
    func scrollToChapterEnd(animated: Bool) { 
        if isMangaMode {
            mangaVC?.scrollToBottom(animated: animated)
        } else if currentReadingMode == .vertical { 
            verticalVC?.scrollToBottom(animated: animated) 
        } else { 
            updateHorizontalPage(to: max(0, currentCache.pages.count - 1), animated: animated) 
        } 
    }
    private func matchSentenceIndex(for snippet: String) -> (index: Int, offset: Int)? {
        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for (idx, sentence) in currentCache.contentSentences.enumerated() {
            if let range = sentence.range(of: trimmed, options: [.anchored, .literal]) {
                let offset = sentence.distance(from: sentence.startIndex, to: range.lowerBound)
                return (idx, offset)
            } else if let range = sentence.range(of: trimmed, options: [.literal]) {
                let offset = sentence.distance(from: sentence.startIndex, to: range.lowerBound)
                return (idx, offset)
            }
        }
        return nil
    }
}
class PageContentViewController: UIViewController { var pageIndex: Int; var chapterOffset: Int; init(pageIndex: Int, chapterOffset: Int) { self.pageIndex = pageIndex; self.chapterOffset = chapterOffset; super.init(nibName: nil, bundle: nil) }; required init?(coder: NSCoder) { fatalError() } }
