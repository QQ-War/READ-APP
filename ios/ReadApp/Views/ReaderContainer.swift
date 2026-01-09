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
    
    var onToggleMenu: () -> Void
    var onAddReplaceRule: (String) -> Void
    var onProgressChanged: (Int, Double) -> Void
    var onToggleTTS: ((@escaping () -> Void) -> Void)?
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
        onToggleTTS?({ [weak vc] in vc?.toggleTTS() })
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
    var book: Book!; var chapters: [BookChapter] = []; var readerSettings: ReaderSettingsStore!; var ttsManager: TTSManager!; var replaceRuleViewModel: ReplaceRuleViewModel?
    var onToggleMenu: (() -> Void)?; var onAddReplaceRuleWithText: ((String) -> Void)?; var onProgressChanged: ((Int, Double) -> Void)?
    var onChapterIndexChanged: ((Int) -> Void)?; var onChaptersLoaded: (([BookChapter]) -> Void)?; var onModeDetected: ((Bool) -> Void)?
    
    private var safeAreaTop: CGFloat = 47; private var safeAreaBottom: CGFloat = 34
    private var currentLayoutSpec: ReaderLayoutSpec {
        return ReaderLayoutSpec(
            topInset: max(safeAreaTop, view.safeAreaInsets.top) + 15,
            bottomInset: max(safeAreaBottom, view.safeAreaInsets.bottom) + 40,
            sideMargin: readerSettings.pageHorizontalMargin + 8,
            pageSize: view.bounds.size
        )
    }
    
    private(set) var currentChapterIndex: Int = 0
    var lastReportedChapterIndex: Int = -1
    var verticalThreshold: CGFloat = 80 {
        didSet {
            verticalVC?.threshold = verticalThreshold
            mangaVC?.threshold = verticalThreshold
        }
    }
    private(set) var currentReadingMode: ReadingMode = .vertical
    var isInternalTransitioning = false
    private var isFirstLoad = true
    private var isUserInteracting = false
    private var ttsCoordinator: ReaderTtsCoordinator?
    
    private var chapterBuilder: ReaderChapterBuilder?
    private var currentCache: ChapterCache = .empty
    private var nextCache: ChapterCache = .empty
    private var prevCache: ChapterCache = .empty
    private var currentPageIndex: Int = 0
    private var isMangaMode = false

    private var verticalVC: VerticalTextViewController?; private var horizontalVC: UIPageViewController?; private var mangaVC: MangaReaderViewController?
    private let progressLabel = UILabel()
    private var lastLayoutSignature: String = ""
    private var loadToken: Int = 0
    private let prefetchCoordinator = ReaderPrefetchCoordinator()
    private var pendingTTSPositionSync = false
    private var prefetchedMangaNextIndex: Int?
    private var prefetchedMangaNextContent: String?
    private var lastChapterSwitchTime: TimeInterval = 0
    private let chapterSwitchCooldown: TimeInterval = 1.0
    private var lastLoggedCacheChapterIndex: Int = -1
    private var lastLoggedNextUrl: String?
    private var lastLoggedPrevUrl: String?
    private var lastLoggedNextCount: Int = -1
    private var lastLoggedPrevCount: Int = -1

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupProgressLabel()
        currentChapterIndex = book.durChapterIndex ?? 0
        lastReportedChapterIndex = currentChapterIndex
        currentReadingMode = readerSettings.readingMode
        chapterBuilder = ReaderChapterBuilder(readerSettings: readerSettings, replaceRules: replaceRuleViewModel?.rules)
        loadChapters()
        ttsCoordinator = ReaderTtsCoordinator(reader: self, ttsManager: ttsManager)
        ttsCoordinator?.start()
    }
    
    private func setupProgressLabel() {
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular); progressLabel.textColor = .secondaryLabel
        view.addSubview(progressLabel); progressLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([progressLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), progressLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4)])
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isInternalTransitioning else { return }
        let b = view.bounds; verticalVC?.view.frame = b; horizontalVC?.view.frame = b; mangaVC?.view.frame = b
        
        if !isMangaMode, currentCache.renderStore != nil, currentReadingMode == .horizontal {
            let spec = currentLayoutSpec
            let signature = "\(Int(spec.pageSize.width))x\(Int(spec.pageSize.height))|\(Int(spec.topInset))"
            if signature != lastLayoutSignature {
                lastLayoutSignature = signature
                let offset = (currentPageIndex < currentCache.pages.count) ? currentCache.pages[currentPageIndex].globalRange.location : 0
                rebuildPaginationForLayout()
                currentPageIndex = currentCache.pages.firstIndex(where: { NSLocationInRange(offset, $0.globalRange) }) ?? 0
                updateHorizontalPage(to: currentPageIndex, animated: false)
            }
        }
    }

    func updateLayout(safeArea: EdgeInsets) { self.safeAreaTop = safeArea.top; self.safeAreaBottom = safeArea.bottom }
    func updateSettings(_ settings: ReaderSettingsStore) {
        let oldSettings = self.readerSettings!
        self.readerSettings = settings
        chapterBuilder?.updateSettings(settings)
        if let v = verticalVC, v.isInfiniteScrollEnabled != settings.isInfiniteScrollEnabled {
            v.isInfiniteScrollEnabled = settings.isInfiniteScrollEnabled
            if !isMangaMode && currentReadingMode == .vertical {
                updateVerticalAdjacent()
            }
        }
        if (oldSettings.fontSize != settings.fontSize || oldSettings.lineSpacing != settings.lineSpacing) && !isMangaMode {
            reRenderCurrentContent() 
        } else if !isMangaMode && currentReadingMode == .vertical {
            updateVerticalAdjacent()
        }
    }
    func updateReplaceRules(_ rules: [ReplaceRule]) { 
        chapterBuilder?.updateReplaceRules(rules)
        if !currentCache.rawContent.isEmpty && !isMangaMode { 
            reRenderCurrentContent()
        } else if !isMangaMode && currentReadingMode == .vertical {
            updateVerticalAdjacent()
        }
    }
    
    func jumpToChapter(_ index: Int, startAtEnd: Bool = false) {
        currentChapterIndex = index; lastReportedChapterIndex = index; onChapterIndexChanged?(index); loadChapterContent(at: index, startAtEnd: startAtEnd)
    }
    func switchReadingMode(to mode: ReadingMode) {
        let offset = getCurrentReadingCharOffset()
        currentReadingMode = mode
        setupReaderMode()
        
        // 模式切换后的进度同步
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.scrollToCharOffset(offset, animated: false)
        }
    }
    
    private func getCurrentReadingCharOffset() -> Int {
        if currentReadingMode == .vertical {
            return verticalVC?.getCurrentCharOffset() ?? 0
        } else if !currentCache.pages.isEmpty && currentPageIndex < currentCache.pages.count {
            return currentCache.pages[currentPageIndex].globalRange.location
        }
        return 0
    }
    
    private func scrollToCharOffset(_ offset: Int, animated: Bool) {
        if currentReadingMode == .vertical {
            verticalVC?.scrollToCharOffset(offset, animated: animated)
        } else {
            if let targetPage = currentCache.pages.firstIndex(where: { NSLocationInRange(offset, $0.globalRange) }) {
                updateHorizontalPage(to: targetPage, animated: animated)
            }
        }
    }

    private func loadChapters() {
        Task { do {
            let list = try await APIService.shared.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
            await MainActor.run {
                self.chapters = list; self.onChaptersLoaded?(list)
                // 如果 TTS 正在播放这本书，优先同步到 TTS 的章节
                if ttsManager.isPlaying && ttsManager.bookUrl == book.bookUrl {
                    self.currentChapterIndex = ttsManager.currentChapterIndex
                    self.onChapterIndexChanged?(self.currentChapterIndex)
                }
                loadChapterContent(at: currentChapterIndex)
            }
        } catch { } }
    }
    
    private func loadChapterContent(at index: Int, startAtEnd: Bool = false) {
        loadToken += 1; let token = loadToken
        Task { [weak self] in
            guard let self = self else { return }
            let isM = book.type == 2 || readerSettings.manualMangaUrls.contains(book.bookUrl ?? "")
            if !isM { self.resetMangaPrefetchedContent() }
            if isM, let cached = self.consumePrefetchedMangaContent(for: index) {
                await MainActor.run {
                    self.processLoadedChapterContent(index: index, rawContent: cached, isManga: isM, startAtEnd: startAtEnd, token: token)
                }
                return
            }
            do {
                let content = try await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index, contentType: isM ? 2 : 0)
                await MainActor.run {
                    self.processLoadedChapterContent(index: index, rawContent: content, isManga: isM, startAtEnd: startAtEnd, token: token)
                }
            } catch { }
        }
    }

    private func processLoadedChapterContent(index: Int, rawContent: String, isManga: Bool, startAtEnd: Bool, token: Int) {
        guard loadToken == token else { return }
        self.isMangaMode = isManga
        self.onModeDetected?(isManga)
        self.reRenderCurrentContent(rawContentOverride: rawContent)

        if isMangaMode { nextCache = .empty }

        if self.isFirstLoad && !self.isMangaMode {
            self.isFirstLoad = false
            if self.ttsManager.isPlaying && self.ttsManager.bookUrl == self.book.bookUrl && self.ttsManager.currentChapterIndex == index {
                let sentenceIdx = self.ttsManager.currentSentenceIndex
                if self.currentReadingMode == .horizontal {
                    self.syncHorizontalPageToTTS(sentenceIndex: sentenceIdx)
                } else {
                    self.verticalVC?.scrollToSentence(index: sentenceIdx, animated: false)
                }
            } else {
                let pos = self.book.durChapterPos ?? 0
                let targetPage = Int(round(pos * Double(max(1, self.currentCache.pages.count))))
                self.updateHorizontalPage(to: targetPage, animated: false)
                self.verticalVC?.scrollToProgress(pos)
            }
        } else if startAtEnd {
            self.scrollToChapterEnd(animated: false)
        } else {
            self.updateHorizontalPage(to: 0, animated: false)
            self.verticalVC?.scrollToTop(animated: false)
        }
        self.prefetchAdjacentChapters(index: index)
        self.syncTTSReadingPositionIfNeeded()
    }
    
    private func reRenderCurrentContent(rawContentOverride: String? = nil) {
        guard let builder = chapterBuilder else { return }
        let rawContent = rawContentOverride ?? currentCache.rawContent
        let chapterUrl = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].url : nil
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        if isMangaMode {
            currentCache = builder.buildMangaCache(rawContent: rawContent, chapterUrl: chapterUrl)
        } else {
            currentCache = builder.buildTextCache(
                rawContent: rawContent,
                title: title,
                layoutSpec: currentLayoutSpec,
                reuseStore: currentCache.renderStore,
                chapterUrl: chapterUrl
            )
        }
        setupReaderMode()
        updateProgressUI()
    }

    private func rebuildPaginationForLayout() {
        guard !isMangaMode, !currentCache.rawContent.isEmpty else { return }
        reRenderCurrentContent()
    }
    
    private func updateProgressUI() {
        if isMangaMode || currentCache.pages.isEmpty { progressLabel.text = ""; return }
        let total = currentCache.pages.count
        let current = max(1, min(total, currentPageIndex + 1))
        progressLabel.text = currentReadingMode == .horizontal ? "\(current)/\(total)" : ""
    }
    
    private func updateVerticalAdjacent(secondaryIndices: Set<Int> = []) {
        guard let v = verticalVC, readerSettings != nil, ttsManager != nil else { return }
        v.isInfiniteScrollEnabled = readerSettings.isInfiniteScrollEnabled
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        let nextTitle = (currentChapterIndex + 1 < chapters.count) ? chapters[currentChapterIndex + 1].title : nil
        let prevTitle = (currentChapterIndex - 1 >= 0) ? chapters[currentChapterIndex - 1].title : nil
        
        // 始终尝试传递预加载内容。
        // 在非无限流模式下，这能让用户在拉动边缘时看到上一章/下一章的“预览”，增强平滑感
        let nextSentences = nextCache.contentSentences.isEmpty ? nil : nextCache.contentSentences
        let prevSentences = prevCache.contentSentences.isEmpty ? nil : prevCache.contentSentences

        if readerSettings.isInfiniteScrollEnabled {
            let nextUrl = nextCache.chapterUrl
            let prevUrl = prevCache.chapterUrl
            let nextCount = nextCache.contentSentences.count
            let prevCount = prevCache.contentSentences.count
            if currentChapterIndex != lastLoggedCacheChapterIndex ||
                nextUrl != lastLoggedNextUrl ||
                prevUrl != lastLoggedPrevUrl ||
                nextCount != lastLoggedNextCount ||
                prevCount != lastLoggedPrevCount {
                lastLoggedCacheChapterIndex = currentChapterIndex
                lastLoggedNextUrl = nextUrl
                lastLoggedPrevUrl = prevUrl
                lastLoggedNextCount = nextCount
                lastLoggedPrevCount = prevCount
                LogManager.shared.log(
                    "无限流缓存状态: cur=\(currentChapterIndex), nextUrl=\(nextUrl ?? "nil"), nextCount=\(nextCount), prevUrl=\(prevUrl ?? "nil"), prevCount=\(prevCount)",
                    category: "阅读器"
                )
            }
        }
        
        let highlightIdx = ttsManager.isPlaying ? ttsManager.currentSentenceIndex : nil
        v.update(sentences: currentCache.contentSentences, nextSentences: nextSentences, prevSentences: prevSentences, title: title, nextTitle: nextTitle, prevTitle: prevTitle, fontSize: readerSettings.fontSize, lineSpacing: readerSettings.lineSpacing, margin: readerSettings.pageHorizontalMargin, highlightIndex: highlightIdx, secondaryIndices: secondaryIndices, isPlaying: ttsManager.isPlaying)
    }


    private func setupReaderMode() {
        if isMangaMode {
            verticalVC?.view.removeFromSuperview(); verticalVC = nil
            horizontalVC?.view.removeFromSuperview(); horizontalVC = nil
            setupMangaMode()
            return
        }
        
        mangaVC?.view.removeFromSuperview(); mangaVC?.removeFromParent(); mangaVC = nil
        
        if currentReadingMode == .vertical {
            if verticalVC == nil {
                horizontalVC?.view.removeFromSuperview(); horizontalVC = nil
                mangaVC?.view.removeFromSuperview(); mangaVC?.removeFromParent(); mangaVC = nil
                setupVerticalMode()
            } else {
                // 如果已经存在，仅更新状态
                updateVerticalAdjacent()
            }
        } else {
            if horizontalVC == nil {
                verticalVC?.view.removeFromSuperview(); verticalVC = nil
                mangaVC?.view.removeFromSuperview(); mangaVC?.removeFromParent(); mangaVC = nil
                setupHorizontalMode()
            } else {
                // 水平模式下的状态同步（如果需要）
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
                    DispatchQueue.main.async { self?.jumpToChapter(newIndex) }
                },
                processedSentences: ttsSentences,
                textProcessor: { [rules = replaceRuleViewModel?.rules] text in
                    ReadingTextProcessor.prepareText(text, rules: rules)
                },
                startAtSentenceIndex: startPos.sentenceIndex,
                startAtSentenceOffset: startPos.sentenceOffset,
                shouldSpeakChapterTitle: startPos.isAtChapterStart
            )
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isUserInteracting = true
        pendingTTSPositionSync = true
        // 进入 Detach 模式：不再跟随 TTS
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            // 停止操作后，延迟恢复跟随 (Catch-up)
            scheduleCatchUp()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scheduleCatchUp()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        scheduleCatchUp()
    }

    private func scheduleCatchUp() {
        // 延迟 1.5 秒如果没有新交互，则认为用户阅读位置已定，同步 TTS 并恢复 Follow
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.isUserInteracting else { return }
            self.isUserInteracting = false
            self.syncTTSReadingPositionIfNeeded()
            // 触发一次即时同步
            self.syncTTSState()
        }
    }

    private func setupHorizontalMode() {
        let h = UIPageViewController(transitionStyle: readerSettings.pageTurningMode == .simulation ? .pageCurl : .scroll, navigationOrientation: .horizontal, options: nil)
        h.dataSource = self; h.delegate = self; addChild(h); view.insertSubview(h.view, at: 0); h.didMove(toParent: self)
        
        // 监听内部滚动视图以检测用户交互
        for view in h.view.subviews {
            if let scrollView = view as? UIScrollView {
                scrollView.delegate = self
            }
        }
        
        for recognizer in h.gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }
        self.horizontalVC = h; updateHorizontalPage(to: currentPageIndex, animated: false)
    }
    
    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating f: Bool, previousViewControllers p: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let v = pvc.viewControllers?.first as? PageContentViewController else { return }
        
        if v.chapterOffset != 0 {
            completeDataDrift(offset: v.chapterOffset, targetPage: v.pageIndex, currentVC: v)
        } else {
            self.currentPageIndex = v.pageIndex
            self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
            updateProgressUI()
        }
    }

    private func completeDataDrift(offset: Int, targetPage: Int, currentVC: PageContentViewController?) {
        self.isInternalTransitioning = true
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
        self.currentPageIndex = targetPage
        self.onChapterIndexChanged?(self.currentChapterIndex)
        
        if let v = currentVC {
            v.chapterOffset = 0
            if let rv = v.view.subviews.first as? ReadContent2View {
                rv.renderStore = self.currentCache.renderStore
                rv.paragraphStarts = self.currentCache.paragraphStarts
                rv.chapterPrefixLen = self.currentCache.chapterPrefixLen
            }
        }
        
        self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
        updateProgressUI()
        prefetchAdjacentChapters(index: currentChapterIndex)
        self.isInternalTransitioning = false
    }
    
    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        guard let c = vc as? PageContentViewController, !isInternalTransitioning else { return nil }
        if c.chapterOffset == 0 {
            if c.pageIndex > 0 { return createPageVC(at: c.pageIndex - 1, offset: 0) }
            if !prevCache.pages.isEmpty { return createPageVC(at: prevCache.pages.count - 1, offset: -1) }
        }
        return nil
    }
    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        guard let c = vc as? PageContentViewController, !isInternalTransitioning else { return nil }
        if c.chapterOffset == 0 {
            if c.pageIndex < currentCache.pages.count - 1 { return createPageVC(at: c.pageIndex + 1, offset: 0) }
            if !nextCache.pages.isEmpty { return createPageVC(at: 0, offset: 1) }
        }
        return nil
    }
    
    private func updateHorizontalPage(to i: Int, animated: Bool) {
        guard let h = horizontalVC, !currentCache.pages.isEmpty else { return }
        let targetIndex = max(0, min(i, currentCache.pages.count - 1))
        let direction: UIPageViewController.NavigationDirection = targetIndex >= currentPageIndex ? .forward : .reverse
        currentPageIndex = targetIndex
        h.setViewControllers([createPageVC(at: targetIndex, offset: 0)], direction: direction, animated: animated)
        updateProgressUI()
        self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
    }
    
    private func createPageVC(at i: Int, offset: Int) -> PageContentViewController {
        let vc = PageContentViewController(pageIndex: i, chapterOffset: offset); let pV = ReadContent2View(frame: .zero)
        let cache = offset == 0 ? currentCache : (offset > 0 ? nextCache : prevCache)
        let aS = cache.renderStore
        let aI = cache.pageInfos ?? []
        let aPS = offset == 0 ? currentCache.paragraphStarts : []
        
        pV.renderStore = aS; if i < aI.count { 
            let info = aI[i]; pV.pageInfo = TK2PageInfo(range: info.range, yOffset: info.yOffset, pageHeight: info.pageHeight, actualContentHeight: info.actualContentHeight, startSentenceIndex: info.startSentenceIndex, contentInset: currentLayoutSpec.topInset)
        }
        pV.onTapLocation = { [weak self] loc in if loc == .middle { self?.onToggleMenu?() } else { self?.handlePageTap(isNext: loc == .right) } }
        pV.horizontalInset = currentLayoutSpec.sideMargin
        pV.paragraphStarts = aPS
        pV.chapterPrefixLen = offset == 0 ? currentCache.chapterPrefixLen : 0
        
        vc.view.addSubview(pV); pV.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([pV.topAnchor.constraint(equalTo: vc.view.topAnchor), pV.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor), pV.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor), pV.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor)])
        return vc
    }
    
    private func handlePageTap(isNext: Bool) {
        isUserInteracting = true
        pendingTTSPositionSync = true
        let t = isNext ? currentPageIndex + 1 : currentPageIndex - 1
        var didChangeWithinChapter = false
        if t >= 0 && t < currentCache.pages.count {
            updateHorizontalPage(to: t, animated: true)
            didChangeWithinChapter = true
        } else {
            let targetChapter = isNext ? currentChapterIndex + 1 : currentChapterIndex - 1
            guard targetChapter >= 0 && targetChapter < chapters.count else {
                isUserInteracting = false
                return
            }
            
            if isNext, !nextCache.pages.isEmpty {
                animateToAdjacentChapter(offset: 1, targetPage: 0)
                didChangeWithinChapter = true
            } else if !isNext, !prevCache.pages.isEmpty {
                animateToAdjacentChapter(offset: -1, targetPage: prevCache.pages.count - 1)
                didChangeWithinChapter = true
            } else {
                jumpToChapter(targetChapter, startAtEnd: !isNext)
            }
        }
        if didChangeWithinChapter {
            scheduleTTSPositionSyncAfterInteraction()
        }
    }

    private func animateToAdjacentChapter(offset: Int, targetPage: Int) {
        guard let h = horizontalVC, !isInternalTransitioning else { return }
        let vc = createPageVC(at: targetPage, offset: offset)
        let direction: UIPageViewController.NavigationDirection = offset > 0 ? .forward : .reverse
        
        h.setViewControllers([vc], direction: direction, animated: true) { [weak self] completed in
            guard completed, let self = self else { return }
            DispatchQueue.main.async {
                let currentVC = h.viewControllers?.first as? PageContentViewController
                self.completeDataDrift(offset: offset, targetPage: targetPage, currentVC: currentVC)
            }
        }
    }

    private func prefetchAdjacentChapters(index: Int) {
        guard let builder = chapterBuilder else { return }
        prefetchCoordinator.prefetchAdjacent(
            book: book,
            chapters: chapters,
            index: index,
            contentType: isMangaMode ? 2 : 0,
            layoutSpec: currentLayoutSpec,
            builder: builder,
            nextCache: nextCache,
            prevCache: prevCache,
            isMangaMode: isMangaMode,
            onNextCache: { [weak self] cache in
                guard let self = self, self.currentChapterIndex == index else { return }
                self.nextCache = cache
                LogManager.shared.log("应用下一章缓存: baseIndex=\(index), nextUrl=\(cache.chapterUrl ?? "nil"), nextCount=\(cache.contentSentences.count)", category: "阅读器")
                self.updateVerticalAdjacent()
                if self.isMangaMode {
                    self.prefetchedMangaNextIndex = index + 1
                    self.prefetchedMangaNextContent = cache.rawContent
                }
            },
            onPrevCache: { [weak self] cache in
                guard let self = self, self.currentChapterIndex == index else { return }
                self.prevCache = cache
                LogManager.shared.log("应用上一章缓存: baseIndex=\(index), prevUrl=\(cache.chapterUrl ?? "nil"), prevCount=\(cache.contentSentences.count)", category: "阅读器")
                self.updateVerticalAdjacent()
            },
            onResetNext: { [weak self] in self?.resetMangaPrefetchedContent() },
            onResetPrev: { [weak self] in self?.prevCache = .empty }
        )
    }
    
    private func prefetchNextChapterOnly(index: Int) {
        guard let builder = chapterBuilder else { return }
        prefetchCoordinator.prefetchNextOnly(
            book: book,
            chapters: chapters,
            index: index,
            contentType: 0,
            layoutSpec: currentLayoutSpec,
            builder: builder,
            nextCache: nextCache,
            isMangaMode: isMangaMode,
            onNextCache: { [weak self] cache in
                guard let self = self, self.currentChapterIndex == index else { return }
                self.nextCache = cache
                LogManager.shared.log("应用下一章缓存: baseIndex=\(index), nextUrl=\(cache.chapterUrl ?? "nil"), nextCount=\(cache.contentSentences.count)", category: "阅读器")
                self.updateVerticalAdjacent()
            },
            onResetNext: { [weak self] in self?.nextCache = .empty }
        )
    }
    
    private func prefetchPrevChapterOnly(index: Int) {
        guard let builder = chapterBuilder else { return }
        prefetchCoordinator.prefetchPrevOnly(
            book: book,
            chapters: chapters,
            index: index,
            contentType: 0,
            layoutSpec: currentLayoutSpec,
            builder: builder,
            prevCache: prevCache,
            isMangaMode: isMangaMode,
            onPrevCache: { [weak self] cache in
                guard let self = self, self.currentChapterIndex == index else { return }
                self.prevCache = cache
                LogManager.shared.log("应用上一章缓存: baseIndex=\(index), prevUrl=\(cache.chapterUrl ?? "nil"), prevCount=\(cache.contentSentences.count)", category: "阅读器")
                self.updateVerticalAdjacent()
            },
            onResetPrev: { [weak self] in self?.prevCache = .empty }
        )
    }

    private func setupVerticalMode() {
        guard readerSettings != nil, ttsManager != nil else {
            // 如果依赖尚未注入，推迟初始化
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.setupVerticalMode() }
            return
        }
        
        let v = VerticalTextViewController()
        v.onVisibleIndexChanged = { [weak self] idx in 
            guard let self = self else { return }
            let count = max(1, self.currentCache.contentSentences.count)
            self.onProgressChanged?(self.currentChapterIndex, Double(idx) / Double(count)) 
        }
        v.onAddReplaceRule = { [weak self] text in self?.onAddReplaceRuleWithText?(text) }; v.onTapMenu = { [weak self] in self?.onToggleMenu?() }
        v.isInfiniteScrollEnabled = readerSettings.isInfiniteScrollEnabled
        v.onReachedBottom = { [weak self] in 
            guard let self = self else { return }
            self.prefetchNextChapterOnly(index: self.currentChapterIndex)
        }
        v.onReachedTop = { [weak self] in
            guard let self = self else { return }
            self.prefetchPrevChapterOnly(index: self.currentChapterIndex)
        }
        v.onChapterSwitched = { [weak self] offset in 
            guard let self = self else { return }
            if !self.readerSettings.isInfiniteScrollEnabled {
                let target = self.currentChapterIndex + offset
                guard target >= 0 && target < self.chapters.count else { return }
                self.jumpToChapter(target, startAtEnd: offset < 0)
                return
            }
            let now = Date().timeIntervalSince1970
            guard now - self.lastChapterSwitchTime > self.chapterSwitchCooldown else { return }
            let target = self.currentChapterIndex + offset
            guard target >= 0 && target < self.chapters.count else { return }
            self.lastChapterSwitchTime = now
            self.switchChapterSeamlessly(offset: offset)
        }
        v.onInteractionChanged = { [weak self] interacting in
            guard let self = self else { return }
            self.isUserInteracting = interacting
            if interacting { self.pendingTTSPositionSync = true }
        }
        v.threshold = verticalThreshold
        self.verticalVC = v
        addChild(v); view.insertSubview(v.view, at: 0); v.view.frame = view.bounds; v.didMove(toParent: self); v.safeAreaTop = safeAreaTop
        
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        let nextTitle = (currentChapterIndex + 1 < chapters.count) ? chapters[currentChapterIndex + 1].title : nil
        let prevTitle = (currentChapterIndex - 1 >= 0) ? chapters[currentChapterIndex - 1].title : nil
        let nextSentences = readerSettings.isInfiniteScrollEnabled ? (nextCache.contentSentences.isEmpty ? nil : nextCache.contentSentences) : nil
        let prevSentences = readerSettings.isInfiniteScrollEnabled ? (prevCache.contentSentences.isEmpty ? nil : prevCache.contentSentences) : nil
        v.update(sentences: currentCache.contentSentences, nextSentences: nextSentences, prevSentences: prevSentences, title: title, nextTitle: nextTitle, prevTitle: prevTitle, fontSize: readerSettings.fontSize, lineSpacing: readerSettings.lineSpacing, margin: readerSettings.pageHorizontalMargin, highlightIndex: ttsManager.isPlaying ? ttsManager.currentSentenceIndex : nil, secondaryIndices: [], isPlaying: ttsManager.isPlaying)
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

    private func setupMangaMode() {
        if mangaVC == nil {
            let vc = MangaReaderViewController()
            vc.safeAreaTop = safeAreaTop
            vc.onToggleMenu = { [weak self] in self?.onToggleMenu?() }
            vc.onInteractionChanged = { [weak self] interacting in
                guard let self = self else { return }
                self.isUserInteracting = interacting
                if interacting { self.pendingTTSPositionSync = true }
            }
            vc.onChapterSwitched = { [weak self] offset in
                guard let self = self else { return }
                let now = Date().timeIntervalSince1970
                guard now - self.lastChapterSwitchTime > self.chapterSwitchCooldown else { return }
                let target = self.currentChapterIndex + offset
                guard target >= 0 && target < self.chapters.count else { return }
                self.lastChapterSwitchTime = now
                self.jumpToChapter(target, startAtEnd: offset < 0)
            }
            vc.threshold = verticalThreshold
            addChild(vc); view.insertSubview(vc.view, at: 0); vc.view.frame = view.bounds; vc.didMove(toParent: self)
            self.mangaVC = vc
        }
        mangaVC?.update(urls: currentCache.contentSentences)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { return nil }
    func syncTTSState() {
        if isMangaMode { return }
        let sentenceIndex = ttsManager.currentSentenceIndex
        let sentenceOffset = ttsManager.currentSentenceOffset
        
        // 1. 垂直模式：局部高亮更新，避免全局刷新
        if currentReadingMode == .vertical { 
            verticalVC?.setHighlight(index: sentenceIndex, secondaryIndices: Set(ttsManager.preloadedIndices), isPlaying: ttsManager.isPlaying)
        }
        
        // 2. 视口跟随逻辑 (只有在非交互状态下执行)
        guard !isUserInteracting, ttsManager.isPlaying else { return }
        
        if currentReadingMode == .vertical {
            verticalVC?.ensureSentenceVisible(index: sentenceIndex)
        } else if currentReadingMode == .horizontal {
            syncHorizontalPageToTTS(sentenceIndex: sentenceIndex, sentenceOffset: sentenceOffset)
        }
    }

    private func syncHorizontalPageToTTS(sentenceIndex: Int, sentenceOffset: Int) { 
        let starts = currentCache.paragraphStarts
        guard sentenceIndex < starts.count else { return }
        
        // 计算全局字符偏移量
        let totalOffset = starts[sentenceIndex] + sentenceOffset
        
        // 查找包含该偏移量的精确页码
        if let targetPage = currentCache.pages.firstIndex(where: { NSLocationInRange(totalOffset, $0.globalRange) }) {
            if targetPage != currentPageIndex {
                updateHorizontalPage(to: targetPage, animated: true) 
            }
        }
    }
    
    private func syncTTSReadingPositionIfNeeded() {
        guard pendingTTSPositionSync else { return }
        pendingTTSPositionSync = false
        guard let bookUrl = book.bookUrl, ttsManager.bookUrl == bookUrl else { return }
        let position = currentStartPosition()
        ttsManager.updateReadingPosition(to: position)
    }

    private func scheduleTTSPositionSyncAfterInteraction(delay: TimeInterval = 0.1) {
        pendingTTSPositionSync = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.isUserInteracting = false
            self.syncTTSReadingPositionIfNeeded()
        }
    }

    private func resetMangaPrefetchedContent() {
        nextCache = .empty
        prefetchedMangaNextIndex = nil
        prefetchedMangaNextContent = nil
    }

    private func consumePrefetchedMangaContent(for index: Int) -> String? {
        guard prefetchedMangaNextIndex == index else { return nil }
        let content = prefetchedMangaNextContent
        prefetchedMangaNextIndex = nil
        prefetchedMangaNextContent = nil
        return content
    }

    deinit {
        prefetchCoordinator.cancel()
        ttsCoordinator?.stop()
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
        var preferredSentenceIndex: Int?

        if currentReadingMode == .horizontal, currentPageIndex < pageInfos.count {
            let pageInfo = pageInfos[currentPageIndex]
            let clampedIndex = max(0, min(pageInfo.startSentenceIndex, starts.count - 1))
            preferredSentenceIndex = clampedIndex
            charOffset = starts[clampedIndex]
        } else if currentReadingMode == .vertical {
            charOffset = verticalVC?.getCurrentCharOffset() ?? 0
        }

        let sentenceIndex: Int
        if let preferred = preferredSentenceIndex {
            sentenceIndex = preferred
        } else {
            sentenceIndex = max(0, min((starts.lastIndex(where: { $0 <= charOffset }) ?? 0), currentCache.contentSentences.count - 1))
        }

        let sentenceStart = starts[sentenceIndex]
        let intra = max(0, charOffset - sentenceStart)
        let indentLen = min(2, currentCache.contentSentences[sentenceIndex].utf16.count)
        let offsetInSentence = max(0, intra - indentLen)
        let maxLen = currentCache.contentSentences[sentenceIndex].utf16.count
        let clampedOffset = min(maxLen, offsetInSentence)
        return ReadingPosition(chapterIndex: currentChapterIndex, sentenceIndex: sentenceIndex, sentenceOffset: clampedOffset, charOffset: charOffset)
    }
    private func scrollToChapterEnd(animated: Bool) { 
        if isMangaMode, let m = mangaVC { 
            let sv = m.scrollView
            sv.setContentOffset(CGPoint(x: 0, y: max(0, sv.contentSize.height - sv.bounds.height)), animated: animated) 
        } else if currentReadingMode == .vertical { 
            verticalVC?.scrollToBottom(animated: animated) 
        } else if !currentCache.pages.isEmpty { 
            updateHorizontalPage(to: max(0, currentCache.pages.count - 1), animated: animated) 
        } 
    }
}
class PageContentViewController: UIViewController { var pageIndex: Int; var chapterOffset: Int; init(pageIndex: Int, chapterOffset: Int) { self.pageIndex = pageIndex; self.chapterOffset = chapterOffset; super.init(nibName: nil, bundle: nil) }; required init?(coder: NSCoder) { fatalError() } }
