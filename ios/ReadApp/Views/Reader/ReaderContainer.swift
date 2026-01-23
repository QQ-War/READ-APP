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
            vc.markUserNavigation()
            vc.jumpToChapter(currentChapterIndex)
        }
        
        let desiredMode: ReadingMode
        if readingMode == .vertical {
            desiredMode = .vertical
        } else if readerSettings.pageTurningMode == .simulation {
            desiredMode = .horizontal
        } else {
            desiredMode = .newHorizontal
        }
        if vc.currentReadingMode != desiredMode { vc.switchReadingMode(to: desiredMode) }
        vc.syncTTSState()
    }
}

// MARK: - UIKit 核心容器
class ReaderContainerViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIScrollViewDelegate, HorizontalCollectionViewDelegate {
    let logger = LogManager.shared
    var book: Book!; var chapters: [BookChapter] = []; var readerSettings: ReaderSettingsStore!; var ttsManager: TTSManager!; var replaceRuleViewModel: ReplaceRuleViewModel?
    var onToggleMenu: (() -> Void)?; var onAddReplaceRuleWithText: ((String) -> Void)?; var onProgressChanged: ((Int, Double) -> Void)?
    var onChapterIndexChanged: ((Int) -> Void)?; var onChaptersLoaded: (([BookChapter]) -> Void)?; var onModeDetected: ((Bool) -> Void)?; var onLoadingChanged: ((Bool) -> Void)?

    private struct ReaderSettingsSnapshot: Equatable {
        let fontSize: CGFloat
        let lineSpacing: CGFloat
        let pageHorizontalMargin: CGFloat
        let readingFontName: String
        let readingTheme: ReadingTheme
        let isInfiniteScrollEnabled: Bool
        let infiniteScrollSwitchThreshold: CGFloat
        let verticalDampingFactor: CGFloat
        let mangaMaxZoom: CGFloat
        let pageTurningMode: PageTurningMode
        let ttsFollowCooldown: TimeInterval
        let verticalThreshold: CGFloat
        let progressFontSize: CGFloat
    }
    private var lastSettingsSnapshot: ReaderSettingsSnapshot?
    private var lastReplaceRules: [ReplaceRule]?
    
    var safeAreaTop: CGFloat = 47; var safeAreaBottom: CGFloat = 34
    var currentLayoutSpec: ReaderLayoutSpec {
        let topInsetValue = safeAreaTop > 0 ? safeAreaTop : view.safeAreaInsets.top
        let bottomInsetValue = safeAreaBottom > 0 ? safeAreaBottom : view.safeAreaInsets.bottom
        return ReaderLayoutSpec(
            topInset: topInsetValue + 15,
            bottomInset: bottomInsetValue + 40,
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
    struct TransitionState {
        var isTransitioning: Bool = false
        var timestamp: TimeInterval = 0
    }
    var transitionState = TransitionState()
    var isInternalTransitioning: Bool {
        get { transitionState.isTransitioning }
        set {
            transitionState.isTransitioning = newValue
            if newValue {
                transitionState.timestamp = Date().timeIntervalSince1970
            }
        }
    }
    var isFirstLoad = true
    private var isUserInteracting = false
    var isAutoScrolling = false
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

    var verticalVC: VerticalTextViewController?
    var horizontalVC: UIPageViewController?
    var mangaVC: MangaReaderViewController?
    var newHorizontalVC: HorizontalCollectionViewController?
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
        
        chapterBuilder = ReaderChapterBuilder(readerSettings: readerSettings, replaceRules: replaceRuleViewModel?.rules)
        loadChapters()
        ttsSyncCoordinator = TTSReadingSyncCoordinator(reader: self, ttsManager: ttsManager)
        ttsSyncCoordinator?.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        prefetchCoordinator.cancel()
        ttsSyncCoordinator?.stop()
        
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
                pos = Double(currentPageIndex) / Double(currentCache.pages.count)
            }
            
            UserDefaults.standard.set(currentChapterIndex, forKey: "lastChapter_\(book.bookUrl ?? "")")
            try? await APIService.shared.saveBookProgress(bookUrl: book.bookUrl ?? "", index: currentChapterIndex, pos: pos, title: title)
        }
    }

    private func setupProgressLabel() {
        progressLabel.font = .monospacedDigitSystemFont(ofSize: readerSettings?.progressFontSize ?? 12, weight: .regular)
        progressLabel.textColor = readerSettings?.readingTheme.textColor ?? .white
        progressLabel.backgroundColor = .clear
        view.addSubview(progressLabel)
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            progressLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4)
        ])
    }
    
    private var lastKnownSize: CGSize = .zero
    private var pendingRelocationOffset: Int? // 记录正在进行的跳转目标

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isInternalTransitioning else { return }
        let b = view.bounds; verticalVC?.view.frame = b; horizontalVC?.view.frame = b; mangaVC?.view.frame = b; newHorizontalVC?.view.frame = b
        
        if b.size != lastKnownSize {
            let spec = currentLayoutSpec
            let signature = "\(Int(spec.pageSize.width))x\(Int(spec.pageSize.height))"
            if signature != lastLayoutSignature {
                lastLayoutSignature = signature
                lastKnownSize = b.size
                if !isMangaMode, currentCache.renderStore != nil, (currentReadingMode == .horizontal || currentReadingMode == .newHorizontal) {
                    rebuildPaginationForLayout()
                    if currentReadingMode == .newHorizontal {
                        newHorizontalVC?.collectionView.collectionViewLayout.invalidateLayout()
                        newHorizontalVC?.scrollToPageIndex(currentPageIndex, animated: false)
                    }
                }
            }
        }
    }

    private var lastSafeAreaTop: CGFloat?
    private var lastSafeAreaBottom: CGFloat?

    func updateLayout(safeArea: EdgeInsets) {
        let top = safeArea.top
        let bottom = safeArea.bottom
        if let lastTop = lastSafeAreaTop, let lastBottom = lastSafeAreaBottom {
            if abs(lastTop - top) < 0.5 && abs(lastBottom - bottom) < 0.5 {
                return
            }
        }
        lastSafeAreaTop = top
        lastSafeAreaBottom = bottom
        self.safeAreaTop = top
        self.safeAreaBottom = bottom
    }
        
        func updateSettings(_ settings: ReaderSettingsStore) {
            let snapshot = ReaderSettingsSnapshot(
                fontSize: settings.fontSize,
                lineSpacing: settings.lineSpacing,
                pageHorizontalMargin: settings.pageHorizontalMargin,
                readingFontName: settings.readingFontName,
                readingTheme: settings.readingTheme,
                isInfiniteScrollEnabled: settings.isInfiniteScrollEnabled,
                infiniteScrollSwitchThreshold: settings.infiniteScrollSwitchThreshold,
                verticalDampingFactor: settings.verticalDampingFactor,
                mangaMaxZoom: settings.mangaMaxZoom,
                pageTurningMode: settings.pageTurningMode,
                ttsFollowCooldown: settings.ttsFollowCooldown,
                verticalThreshold: settings.verticalThreshold,
                progressFontSize: settings.progressFontSize
            )
            if lastSettingsSnapshot == snapshot { return }
            let previousSnapshot = lastSettingsSnapshot
            lastSettingsSnapshot = snapshot
            
            // 更新进度标签字体大小
            progressLabel.font = .monospacedDigitSystemFont(ofSize: settings.progressFontSize, weight: .regular)
            mangaVC?.progressLabel.font = .monospacedDigitSystemFont(ofSize: settings.progressFontSize, weight: .regular)

            guard let oldSettings = self.readerSettings else {
                self.readerSettings = settings
                chapterBuilder?.updateSettings(settings)
                view.backgroundColor = settings.readingTheme.backgroundColor
                verticalVC?.view.backgroundColor = settings.readingTheme.backgroundColor
                horizontalVC?.view.backgroundColor = settings.readingTheme.backgroundColor
                newHorizontalVC?.view.backgroundColor = settings.readingTheme.backgroundColor
                mangaVC?.view.backgroundColor = settings.readingTheme.backgroundColor
                return
            }
            self.readerSettings = settings
            chapterBuilder?.updateSettings(settings)
            view.backgroundColor = settings.readingTheme.backgroundColor
            verticalVC?.view.backgroundColor = settings.readingTheme.backgroundColor
            horizontalVC?.view.backgroundColor = settings.readingTheme.backgroundColor
            newHorizontalVC?.view.backgroundColor = settings.readingTheme.backgroundColor
            mangaVC?.view.backgroundColor = settings.readingTheme.backgroundColor

            // 检测关键布局参数是否改变
            let layoutChanged = oldSettings.fontSize != settings.fontSize ||
                                oldSettings.lineSpacing != settings.lineSpacing ||
                                oldSettings.pageHorizontalMargin != settings.pageHorizontalMargin ||
                                oldSettings.readingFontName != settings.readingFontName ||
                                oldSettings.readingTheme != settings.readingTheme
            let turningModeChanged = previousSnapshot?.pageTurningMode != snapshot.pageTurningMode

            // 如果正在进行模式切换跳转，不在此处重新捕获进度，防止捕获到临时的 Offset 0
            let currentOffset = pendingRelocationOffset ?? getCurrentReadingCharOffset()

            // 确保正在切换模式时状态锁能正确管理
            if turningModeChanged || layoutChanged {
                self.isInternalTransitioning = false 
            }

            if turningModeChanged && !isMangaMode {
                rebuildHorizontalControllerForTurningModeChange()
            }

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
            
            // 确保进度 UI 随主题等设置更新
            updateProgressUI()
        }
        
                
        
        func updateReplaceRules(_ rules: [ReplaceRule]) {
            if lastReplaceRules == rules { return }
            lastReplaceRules = rules
            guard let ttsManager = ttsManager else {
                chapterBuilder?.updateReplaceRules(rules)
                return
            }
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
                    requestChapterSwitch(to: index, startAtEnd: startAtEnd)
                }
        
            
        
                                func switchReadingMode(to mode: ReadingMode) {
        
            
        
                                    let offset = getCurrentReadingCharOffset()
        
            
        
                                    currentReadingMode = mode
        
                    
        
                    // 关键：设置挂起目标，防止跳转过程中进度被覆盖
        
                    pendingRelocationOffset = offset
        
        
                    
        
                    if mode == .horizontal || mode == .newHorizontal {
        
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
        
                
        
        
                
        
                        } else if currentReadingMode == .newHorizontal && !currentCache.pages.isEmpty {
                            let idx = newHorizontalVC?.currentPageIndex ?? 0
                            if idx < currentCache.pages.count {
                                offset = currentCache.pages[idx].globalRange.location
                            } else {
                                offset = 0
                            }
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
        } else if currentReadingMode == .newHorizontal {
            if let targetPage = currentCache.pages.firstIndex(where: { page in
                offset >= page.globalRange.location && offset < (page.globalRange.location + page.globalRange.length)
            }) {
                newHorizontalVC?.scrollToPageIndex(targetPage, animated: animated)
            }
        } else {
            if let targetPage = currentCache.pages.firstIndex(where: { page in
                offset >= page.globalRange.location && offset < (page.globalRange.location + page.globalRange.length)
            }) {
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
                            self.requestChapterSwitch(offset: offset, preferSeamless: true)
                        } else {
                            self.requestChapterSwitch(to: newIndex)
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
        if isAutoScrolling {
            isAutoScrolling = false
            return
        }
        notifyUserInteractionEnded()
    }

    func requestChapterSwitch(to index: Int, startAtEnd: Bool = false) {
        guard index >= 0 && index < chapters.count else { return }
        performJumpToChapter(index, startAtEnd: startAtEnd)
    }

    func requestChapterSwitch(offset: Int, preferSeamless: Bool, startAtEnd: Bool? = nil) {
        guard offset != 0 else { return }
        let targetIndex = currentChapterIndex + offset
        guard targetIndex >= 0 && targetIndex < chapters.count else { return }
        if preferSeamless, attemptSeamlessSwitch(offset: offset) {
            applyChapterLandingPage(offset: offset)
            return
        }
        let shouldStartAtEnd = startAtEnd ?? (offset < 0)
        performJumpToChapter(targetIndex, startAtEnd: shouldStartAtEnd)
    }

    private func performJumpToChapter(_ index: Int, startAtEnd: Bool) {
        activePaginationAnchor = 0
        let isNext = index > currentChapterIndex
        currentChapterIndex = index
        lastReportedChapterIndex = index
        onChapterIndexChanged?(index)
        
        if currentReadingMode == .newHorizontal || currentReadingMode == .horizontal {
            performChapterTransition(isNext: isNext) { [weak self] in
                self?.loadChapterContent(at: index, startAtEnd: startAtEnd)
            }
        } else {
            performChapterTransitionFade { [weak self] in
                self?.loadChapterContent(at: index, startAtEnd: startAtEnd)
            }
        }
    }

    private func attemptSeamlessSwitch(offset: Int) -> Bool {
        guard offset != 0 else { return false }
        let canSwap = (offset > 0 && nextCache.renderStore != nil) || (offset < 0 && prevCache.renderStore != nil)
        guard canSwap else { return false }

        if offset > 0 {
            prevCache = currentCache
            currentCache = nextCache
            nextCache = .empty
        } else {
            nextCache = currentCache
            currentCache = prevCache
            prevCache = .empty
        }

        applyChapterState(afterSeamlessOffset: offset)
        return true
    }

    private func applyChapterState(afterSeamlessOffset offset: Int) {
        currentChapterIndex += offset
        lastReportedChapterIndex = currentChapterIndex
        if currentReadingMode == .horizontal || currentReadingMode == .newHorizontal {
            currentPageIndex = offset > 0 ? 0 : max(0, currentCache.pages.count - 1)
        }
        onChapterIndexChanged?(currentChapterIndex)
        updateVerticalAdjacent()
        if currentReadingMode == .newHorizontal {
            updateNewHorizontalContent()
        } else if currentReadingMode == .horizontal {
            updateHorizontalPage(to: currentPageIndex, animated: false)
        }
        prefetchAdjacentChapters(index: currentChapterIndex)
    }

    private func applyChapterLandingPage(offset: Int) {
        if currentReadingMode == .horizontal || currentReadingMode == .newHorizontal {
            let target = offset > 0 ? 0 : max(0, currentCache.pages.count - 1)
            currentPageIndex = target
            if currentReadingMode == .newHorizontal {
                updateNewHorizontalContent()
            } else {
                updateHorizontalPage(to: target, animated: false)
            }
        } else if currentReadingMode == .vertical {
            if offset > 0 { verticalVC?.scrollToTop(animated: false) }
            else { verticalVC?.scrollToBottom(animated: false) }
        }
    }

    private func rebuildHorizontalControllerForTurningModeChange() {
        if currentReadingMode == .newHorizontal {
            if readerSettings.pageTurningMode == .simulation {
                return
            }
            // 新版模式不需要重建控制器，只需要刷新内容以应用新的 Layout 设置
            updateNewHorizontalContent()
            return
        }
        guard currentReadingMode == .horizontal, !isMangaMode else { return }
        if readerSettings.pageTurningMode != .simulation {
            return
        }
        if readerSettings.pageTurningMode == .simulation {
            isInternalTransitioning = true
            horizontalVC?.view.removeFromSuperview()
            horizontalVC?.removeFromParent()
            horizontalVC = nil
            setupHorizontalMode()
            isInternalTransitioning = false
            return
        }
        isInternalTransitioning = true
        performChapterTransitionFade { [weak self] in
            guard let self = self else { return }
            self.horizontalVC?.view.removeFromSuperview()
            self.horizontalVC?.removeFromParent()
            self.horizontalVC = nil
            self.setupHorizontalMode()
            self.isInternalTransitioning = false
        }
    }


    func switchChapterSeamlessly(offset: Int) {
        if attemptSeamlessSwitch(offset: offset) { return }
        requestChapterSwitch(offset: offset, preferSeamless: false)
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
                    requestChapterSwitch(offset: 1, preferSeamless: true)
                    return
                }
            }
        }

        // 确保阅读器记录的章节索引与 TTS 一致
        guard ttsManager.currentChapterIndex == currentChapterIndex else {
            return
        }
        if chapters.indices.contains(currentChapterIndex) {
            guard currentCache.chapterUrl == chapters[currentChapterIndex].url else {
                return
            }
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
        guard !isUserInteracting, ttsManager.isPlaying, now >= suppressTTSFollowUntil else {
            return
        }

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
        } else if currentReadingMode == .newHorizontal || currentReadingMode == .horizontal {
            // 处理标题偏移导致的索引对齐问题
            if ttsManager.isReadingChapterTitle {
                // 如果正在读标题，保持在第一页即可，不执行复杂的正文同步逻辑
                if currentPageIndex != 0 {
                    if currentReadingMode == .newHorizontal {
                        newHorizontalVC?.scrollToPageIndex(0, animated: true)
                    } else {
                        updateHorizontalPage(to: 0, animated: true)
                    }
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
                
                let currentIndex: Int
                if currentReadingMode == .newHorizontal {
                    currentIndex = newHorizontalVC?.currentPageIndex ?? 0
                } else {
                    currentIndex = horizontalPageIndexForDisplay()
                }

                if currentIndex < currentCache.pages.count {
                    let currentRange = currentCache.pages[currentIndex].globalRange
                    if !NSLocationInRange(realTimeOffset, currentRange) {
                        if let targetPage = currentCache.pages.firstIndex(where: { NSLocationInRange(realTimeOffset, $0.globalRange) }) {
                            if targetPage != currentPageIndex {
                                if currentReadingMode == .newHorizontal {
                                    newHorizontalVC?.scrollToPageIndex(targetPage, animated: true)
                                } else {
                                    updateHorizontalPage(to: targetPage, animated: true)
                                }
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
                        self.requestChapterSwitch(offset: offset, preferSeamless: true)
                    } else {
                        self.requestChapterSwitch(to: newIndex)
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
        let pageIndex: Int
        if currentReadingMode == .newHorizontal {
            pageIndex = newHorizontalVC?.currentPageIndex ?? 0
        } else {
            pageIndex = horizontalPageIndexForDisplay()
        }
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
        resetTTSFollowCooldown()
    }

    func notifyUserInteractionStarted() {
        isUserInteracting = true
        pendingTTSPositionSync = true
        resetTTSFollowCooldown()
        ttsSyncCoordinator?.userInteractionStarted()
    }

    func safeToggleMenu() {
        guard !isInternalTransitioning else { return }
        onToggleMenu?()
    }

    func notifyUserInteractionEnded() {
        guard isUserInteracting || pendingTTSPositionSync else { return }
        isUserInteracting = false
        resetTTSFollowCooldown()
        ttsSyncCoordinator?.scheduleCatchUp(delay: readerSettings.ttsFollowCooldown)
    }

    private func resetTTSFollowCooldown() {
        suppressTTSFollowUntil = Date().timeIntervalSince1970 + readerSettings.ttsFollowCooldown
    }

    func markUserNavigation() {
        suppressTTSFollowUntil = Date().timeIntervalSince1970 + readerSettings.ttsFollowCooldown
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

        if currentReadingMode == .horizontal || currentReadingMode == .newHorizontal {
            let pageIndex: Int
            if currentReadingMode == .newHorizontal {
                pageIndex = newHorizontalVC?.currentPageIndex ?? 0
            } else {
                pageIndex = horizontalPageIndexForDisplay()
            }
            if pageIndex < pageInfos.count {
                let pageInfo = pageInfos[pageIndex]
                charOffset = pageInfo.range.location
                // 查找满足：page.start <= charOffset < page.end 的句索引
                sentenceIndex = starts.lastIndex(where: { $0 <= charOffset }) ?? 0
            }
        } else if currentReadingMode == .vertical {
            charOffset = verticalVC?.getCurrentCharOffset() ?? 0
            // 垂直模式：直接使用 charOffset 作为 sentenceOffset
            // getCurrentCharOffset() 返回的是当前可见区域顶部的行偏移
            // 不需要通过 paragraphStarts 计算偏移
            if charOffset < 0 {
                // 当前视窗落在相邻章节，避免强制回到当前章节起点
                let fallbackIndex = max(0, verticalVC?.lastReportedIndex ?? 0)
                sentenceIndex = min(fallbackIndex, starts.count - 1)
                charOffset = starts[sentenceIndex]
            } else {
                sentenceIndex = starts.lastIndex(where: { $0 <= charOffset }) ?? 0
            }
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
        } else if currentReadingMode == .newHorizontal {
            let target = max(0, currentCache.pages.count - 1)
            currentPageIndex = target
            newHorizontalVC?.scrollToPageIndex(target, animated: animated)
        } else { 
            isAutoScrolling = animated
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

    // MARK: - HorizontalCollectionViewDelegate
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, didUpdatePageIndex index: Int) {
        self.currentPageIndex = index
        self.isInternalTransitioning = false
        self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
        updateProgressUI()
    }
    
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, didTapMiddle: Bool) {
        safeToggleMenu()
    }
    
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, didTapLeft: Bool) {
        handlePageTap(isNext: false)
    }
    
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, didTapRight: Bool) {
        handlePageTap(isNext: true)
    }
    
    func horizontalCollectionView(_ collectionView: HorizontalCollectionViewController, requestChapterSwitch offset: Int) {
        if offset > 0 && !nextCache.pages.isEmpty {
            animateToAdjacentChapter(offset: 1, targetPage: 0)
        } else if offset < 0 && !prevCache.pages.isEmpty {
            animateToAdjacentChapter(offset: -1, targetPage: prevCache.pages.count - 1)
        } else {
            self.requestChapterSwitch(offset: offset, preferSeamless: true)
        }
    }
}
