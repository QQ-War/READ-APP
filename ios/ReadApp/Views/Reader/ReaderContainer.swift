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
    private let logger = LogManager.shared
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
    private var ttsSyncCoordinator: TTSReadingSyncCoordinator?
    
    private var chapterBuilder: ReaderChapterBuilder?
    private var currentCache: ChapterCache = .empty
    private var nextCache: ChapterCache = .empty
    private var prevCache: ChapterCache = .empty
    private var currentPageIndex: Int = 0
    private var visibleHorizontalPageIndex: Int? {
        guard let pageVC = horizontalVC?.viewControllers?.first as? PageContentViewController else { return nil }
        guard pageVC.chapterOffset == 0 else { return nil }
        return pageVC.pageIndex
    }
    private func horizontalPageIndexForDisplay() -> Int {
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
    private var isMangaMode = false
    private var latestVisibleFragmentLines: [String] = []

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
    private var suppressTTSFollowUntil: TimeInterval = 0
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
        ttsSyncCoordinator = TTSReadingSyncCoordinator(reader: self, ttsManager: ttsManager)
        ttsSyncCoordinator?.start()
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
        } else if !currentCache.pages.isEmpty {
            let idx = horizontalPageIndexForDisplay()
            guard idx < currentCache.pages.count else { return 0 }
            return currentCache.pages[idx].globalRange.location
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
                    // 使用 charOffset 直接定位
                    if let targetPage = self.currentCache.pages.firstIndex(where: { NSLocationInRange(self.ttsManager.currentCharOffset, $0.globalRange) }) {
                        self.updateHorizontalPage(to: targetPage, animated: false)
                    }
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
        v.seamlessSwitchThreshold = readerSettings.infiniteScrollSwitchThreshold
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
                _ = nextUrl
                _ = prevUrl
                _ = nextCount
                _ = prevCount
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
        guard let v = pvc.viewControllers?.first as? PageContentViewController else {
            isInternalTransitioning = false
            return
        }
        guard completed else {
            isInternalTransitioning = false
            return
        }
        
        if v.chapterOffset != 0 {
            completeDataDrift(offset: v.chapterOffset, targetPage: v.pageIndex, currentVC: v)
        } else {
            self.currentPageIndex = v.pageIndex
            self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
            updateProgressUI()
            self.isInternalTransitioning = false
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
        h.setViewControllers([createPageVC(at: targetIndex, offset: 0)], direction: direction, animated: animated) { [weak self] finished in
            guard let self = self else { return }
            if animated {
                self.isInternalTransitioning = false
            }
        }
        if !animated {
            self.isInternalTransitioning = false
        }
        updateProgressUI()
        self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
    }
    
    private func createPageVC(at i: Int, offset: Int) -> PageContentViewController {
        let vc = PageContentViewController(pageIndex: i, chapterOffset: offset); let pV = ReadContent2View(frame: .zero)
        let cache = offset == 0 ? currentCache : (offset > 0 ? nextCache : prevCache)
        let aS = cache.renderStore
        let aI = cache.pageInfos ?? []
        let aPS = offset == 0 ? currentCache.paragraphStarts : []
        
        pV.renderStore = aS
        pV.pageIndex = i
        pV.onVisibleFragments = { [weak self] pageIdx, lines in
            guard let self = self else { return }
            let displayPage = self.horizontalPageIndexForDisplay()
            if pageIdx == displayPage {
                self.latestVisibleFragmentLines = lines
                let snippet = lines.isEmpty ? "[]" : lines.joined(separator: " | ")
                self.logger.log("ReadContent2View visible fragments - mode=\(self.currentReadingMode) page=\(pageIdx) currentDisplay=\(displayPage) snippet=\(snippet)", category: "TTS")
            }
        }
        if i < aI.count { 
            let info = aI[i]; pV.pageInfo = TK2PageInfo(range: info.range, yOffset: info.yOffset, pageHeight: info.pageHeight, actualContentHeight: info.actualContentHeight, startSentenceIndex: info.startSentenceIndex, contentInset: currentLayoutSpec.topInset)
        }
        pV.onTapLocation = { [weak self] loc in if loc == .middle { self?.safeToggleMenu() } else { self?.handlePageTap(isNext: loc == .right) } }
        pV.horizontalInset = currentLayoutSpec.sideMargin
        pV.paragraphStarts = aPS
        pV.chapterPrefixLen = offset == 0 ? currentCache.chapterPrefixLen : 0
        
        vc.view.addSubview(pV); pV.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([pV.topAnchor.constraint(equalTo: vc.view.topAnchor), pV.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor), pV.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor), pV.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor)])
        return vc
    }
    
    private func handlePageTap(isNext: Bool) {
        guard !isInternalTransitioning else {
            finalizeUserInteraction()
            return
        }
        notifyUserInteractionStarted()
        let t = isNext ? currentPageIndex + 1 : currentPageIndex - 1
        var didChangeWithinChapter = false
        if t >= 0 && t < currentCache.pages.count {
            isInternalTransitioning = true
            updateHorizontalPage(to: t, animated: true)
            didChangeWithinChapter = true
        } else {
            let targetChapter = isNext ? currentChapterIndex + 1 : currentChapterIndex - 1
            guard targetChapter >= 0 && targetChapter < chapters.count else {
                finalizeUserInteraction()
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
            notifyUserInteractionEnded()
        }
    }

    private func animateToAdjacentChapter(offset: Int, targetPage: Int) {
        guard let h = horizontalVC, !isInternalTransitioning else { return }
        isInternalTransitioning = true
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
                self.updateVerticalAdjacent()
                if self.isMangaMode {
                    self.prefetchedMangaNextIndex = index + 1
                    self.prefetchedMangaNextContent = cache.rawContent
                }
            },
            onPrevCache: { [weak self] cache in
                guard let self = self, self.currentChapterIndex == index else { return }
                self.prevCache = cache
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
        v.onAddReplaceRule = { [weak self] text in self?.onAddReplaceRuleWithText?(text) }; v.onTapMenu = { [weak self] in self?.safeToggleMenu() }
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
            if interacting {
                self.notifyUserInteractionStarted()
            } else {
                self.notifyUserInteractionEnded()
            }
        }
        v.threshold = verticalThreshold
        v.seamlessSwitchThreshold = readerSettings.infiniteScrollSwitchThreshold
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
            vc.onToggleMenu = { [weak self] in self?.safeToggleMenu() }
            vc.onInteractionChanged = { [weak self] interacting in
                guard let self = self else { return }
                if interacting {
                    self.notifyUserInteractionStarted()
                } else {
                    self.notifyUserInteractionEnded()
                }
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
        
        // 1. 垂直模式：局部高亮更新，避免全局刷新
        if currentReadingMode == .vertical { 
            verticalVC?.setHighlight(index: sentenceIndex, secondaryIndices: Set(ttsManager.preloadedIndices), isPlaying: ttsManager.isPlaying)
        }

        // 2. 视口跟随逻辑 (只有在非交互状态下执行)
        let now = Date().timeIntervalSince1970
        guard !isUserInteracting, ttsManager.isPlaying, now >= suppressTTSFollowUntil else { return }

        if currentReadingMode == .vertical {
            // 避免因段落转折回翻上一页：仅在刚到新句且 offset=0 时确保可见，其它情况保持当前视图
            if ttsManager.currentSentenceOffset == 0 {
                let isVisible = verticalVC?.isSentenceVisible(index: sentenceIndex) ?? true
                logger.log("TTS 垂直同步 -> sentence=\(sentenceIndex), isVisible=\(isVisible), userInteracting=\(isUserInteracting)", category: "TTS")
                if !isVisible {
                    verticalVC?.ensureSentenceVisible(index: sentenceIndex)
                }
            }
        } else if currentReadingMode == .horizontal {
            // 方案：直接用 charOffset 判断是否在当前页，不要用 sentenceIndex 二次计算
            let ttsCharOffset = ttsManager.currentCharOffset
            if ttsCharOffset > 0 {
                let currentIndex = horizontalPageIndexForDisplay()
                if currentIndex < currentCache.pages.count {
                    let currentRange = currentCache.pages[currentIndex].globalRange
                    if !NSLocationInRange(ttsCharOffset, currentRange) {
                        if let targetPage = currentCache.pages.firstIndex(where: { NSLocationInRange(ttsCharOffset, $0.globalRange) }) {
                            if targetPage != currentPageIndex {
                                logger.log("TTS 横翻跳页 -> fromPage=\(currentPageIndex) toPage=\(targetPage) charOffset=\(ttsCharOffset), sentence=\(sentenceIndex)", category: "TTS")
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
        logger.log("TTS重新定位 -> page=\(currentPageIndex), mode=\(currentReadingMode), charOffset=\(startPos.charOffset), sentence=\(startPos.sentenceIndex), sentenceOffset=\(startPos.sentenceOffset)", category: "TTS")
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

    private func isTTSPositionInCurrentPage() -> Bool {
        guard ttsManager.currentChapterIndex == currentChapterIndex else { return false }
        if currentReadingMode == .vertical {
            return verticalVC?.isSentenceVisible(index: ttsManager.currentSentenceIndex) ?? true
        }
        let pageInfos = currentCache.pageInfos ?? []
        let pageIndex = horizontalPageIndexForDisplay()
        guard pageIndex < pageInfos.count else { return true }
        let starts = currentCache.paragraphStarts
        let sentenceIdx = ttsManager.currentSentenceIndex
        guard sentenceIdx >= 0 && sentenceIdx < starts.count else { return false }
        let indentLen = 2
        let totalOffset = starts[sentenceIdx] + ttsManager.currentSentenceOffset + indentLen
        return NSLocationInRange(totalOffset, pageInfos[pageIndex].range)
    }

    func finalizeUserInteraction() {
        isUserInteracting = false
    }

    private func notifyUserInteractionStarted() {
        isUserInteracting = true
        pendingTTSPositionSync = true
        suppressTTSFollowUntil = Date().timeIntervalSince1970 + readerSettings.ttsFollowCooldown
        ttsSyncCoordinator?.userInteractionStarted()
    }

    private func safeToggleMenu() {
        guard !isInternalTransitioning else { return }
        onToggleMenu?()
    }

    private func notifyUserInteractionEnded() {
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
        logger.log("TTS 启动位置诊断 -> charOffset=\(charOffset), sentenceIndex=\(sentenceIndex), sentenceStart=\(sentenceStart), intra=\(intra)", category: "TTS")
        
        let offsetInSentence = intra
        
        let maxLen = currentCache.contentSentences[sentenceIndex].utf16.count
        let clampedOffset = min(maxLen, offsetInSentence)
        
        let visibleInfo = visibleTopSentenceInfo()
        let previewLines = previewSentences(from: sentenceIndex, limit: 2)
        let pageSnippet = horizontalPageStartSnippet(for: horizontalPageIndexForDisplay(), limit: 120)
        logTTSStartSnapshot(
            sentenceIndex: sentenceIndex,
            sentenceOffset: clampedOffset,
            charOffset: charOffset,
            visibleTopIndex: visibleInfo.index,
            visibleTopLines: visibleInfo.sentences,
            previewLines: previewLines,
            pageSnippet: pageSnippet,
            visibleFragmentLines: latestVisibleFragmentLines
        )
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
    private func logTTSStartSnapshot(sentenceIndex: Int, sentenceOffset: Int, charOffset: Int, visibleTopIndex: Int, visibleTopLines: [String], previewLines: [String], pageSnippet: String, visibleFragmentLines: [String]) {
        let pageIdx = horizontalPageIndexForDisplay()
        let topLinesDesc = visibleTopLines.isEmpty ? "[]" : visibleTopLines.joined(separator: " | ")
        let previewDesc = previewLines.isEmpty ? "[]" : previewLines.joined(separator: " | ")
        let snippetDesc = pageSnippet.isEmpty ? "[]" : pageSnippet
        let fragmentDesc = visibleFragmentLines.isEmpty ? "[]" : visibleFragmentLines.joined(separator: " | ")
        let pageMatch = matchSentenceIndex(for: pageSnippet)
        let fragmentMatch = matchSentenceIndex(for: visibleFragmentLines.first ?? "")
        let previewMatch = matchSentenceIndex(for: previewLines.first ?? "")
        let detail = { (tuple: (index: Int, offset: Int)?) -> String in
            guard let tuple = tuple else { return "nil" }
            return "\(tuple.index)@\(tuple.offset)"
        }
        let message = """
        TTS start snapshot - mode=\(currentReadingMode) chapter=\(currentChapterIndex) currentPageIdx=\(currentPageIndex) visiblePageIdx=\(pageIdx) \
        visibleTopIdx=\(visibleTopIndex) topLines=\(topLinesDesc) startSentenceIdx=\(sentenceIndex) sentenceOffset=\(sentenceOffset) \
        charOffset=\(charOffset) previewLines=\(previewDesc) pageSnippet=\(snippetDesc) visibleFragments=\(fragmentDesc) \
        pageSnippetMatch=\(detail(pageMatch)) fragmentMatch=\(detail(fragmentMatch)) previewMatch=\(detail(previewMatch))
        """
        logger.log(message, category: "TTS")
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
