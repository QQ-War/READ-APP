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
    private var lastLayoutSignature: String = ""
    private var lastAppliedLayoutSettings: String = ""
    private var loadToken: Int = 0
    private var lastKnownSize: CGSize = .zero
    private var pendingRelocationOffset: Int?
    
    private var currentLayoutSpec: ReaderLayoutSpec {
        let sideMargin = (readerSettings != nil) ? (readerSettings.pageHorizontalMargin + 8) : 28
        return ReaderLayoutSpec(
            topInset: max(safeAreaTop, view.safeAreaInsets.top) + 15,
            bottomInset: max(safeAreaBottom, view.safeAreaInsets.bottom) + 40,
            sideMargin: sideMargin,
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
    private var isMangaMode = false
    private var latestVisibleFragmentLines: [String] = []
    
    private var verticalVC: VerticalTextViewController?
    private var horizontalVC: UIPageViewController?
    private var mangaVC: MangaReaderViewController?
    private let progressLabel = UILabel()
    private let prefetchCoordinator = ReaderPrefetchCoordinator()
    
    private var lastChapterSwitchTime: TimeInterval = 0
    private let chapterSwitchCooldown: TimeInterval = 1.0
    
    private var pendingTTSPositionSync = false
    private var prefetchedMangaNextIndex: Int?
    private var prefetchedMangaNextContent: String?
    private var suppressTTSFollowUntil: TimeInterval = 0
    private var paragraphIndentLength: Int = 2
    private var verticalDetectionOffset: CGFloat = 20

    private var visibleHorizontalPageIndex: Int? {
        guard let pageVC = horizontalVC?.viewControllers?.first as? PageContentViewController else { return nil }
        guard pageVC.chapterOffset == 0 else { return nil }
        return pageVC.pageIndex
    }

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
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        progressLabel.textColor = .secondaryLabel
        view.addSubview(progressLabel)
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            progressLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4)
        ])
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isInternalTransitioning else { return }
        let b = view.bounds
        verticalVC?.view.frame = b; horizontalVC?.view.frame = b; mangaVC?.view.frame = b
        
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
        if self.readerSettings == nil { self.readerSettings = settings }
        let oldSettings = self.readerSettings!
        self.readerSettings = settings
        
        chapterBuilder?.updateSettings(settings)
        
        let currentSettingsSig = "\(settings.fontSize)-\(settings.lineSpacing)-\(settings.pageHorizontalMargin)-\(currentReadingMode.rawValue)"
        let needsRerender = currentSettingsSig != lastAppliedLayoutSettings
        
        if !needsRerender && oldSettings.isInfiniteScrollEnabled == settings.isInfiniteScrollEnabled {
            return
        }
        
        lastAppliedLayoutSettings = currentSettingsSig
        let currentOffset = pendingRelocationOffset ?? getCurrentReadingCharOffset()
        
        if let v = verticalVC, v.isInfiniteScrollEnabled != settings.isInfiniteScrollEnabled {
            v.isInfiniteScrollEnabled = settings.isInfiniteScrollEnabled
            if !isMangaMode && currentReadingMode == .vertical { updateVerticalAdjacent() }
        }
        
        if needsRerender && !isMangaMode {
            if currentReadingMode == .horizontal {
                reRenderCurrentContent(anchorOffset: max(0, currentOffset))
            } else {
                reRenderCurrentContent()
            }
        } else if !isMangaMode && currentReadingMode == .vertical {
            updateVerticalAdjacent()
        }
        
        if currentReadingMode == .vertical && !isMangaMode && pendingRelocationOffset == nil && currentOffset >= 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.scrollToCharOffset(currentOffset, animated: false)
            }
        }
    }

    func updateReplaceRules(_ rules: [ReplaceRule]) { 
        chapterBuilder?.updateReplaceRules(rules)
        ttsManager.replaceRules = rules
        if !currentCache.rawContent.isEmpty && !isMangaMode { 
            let currentOffset = pendingRelocationOffset ?? getCurrentReadingCharOffset()
            if currentReadingMode == .horizontal {
                reRenderCurrentContent(anchorOffset: currentOffset >= 0 ? currentOffset : 0)
            } else {
                reRenderCurrentContent()
            }
        } else if !isMangaMode && currentReadingMode == .vertical {
            updateVerticalAdjacent()
        }
    }

    func jumpToChapter(_ index: Int, startAtEnd: Bool = false) {
        currentChapterIndex = index; lastReportedChapterIndex = index
        onChapterIndexChanged?(index); loadChapterContent(at: index, startAtEnd: startAtEnd)
    }

    func switchReadingMode(to mode: ReadingMode) {
        let offset = getCurrentReadingCharOffset()
        let oldMode = currentReadingMode
        currentReadingMode = mode
        pendingRelocationOffset = offset
        logger.log("模式切换触发: \(oldMode.rawValue) -> \(mode.rawValue), 目标锚点: \(offset)", category: "ReaderProgress")
        
        if mode == .horizontal {
            reRenderCurrentContent(anchorOffset: offset)
            pendingRelocationOffset = nil
        } else {
            setupReaderMode()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                self.scrollToCharOffset(offset, animated: false)
                self.pendingRelocationOffset = nil
            }
        }
    }

    private func getCurrentReadingCharOffset() -> Int {
        if let pending = pendingRelocationOffset { return pending }
        if currentReadingMode == .vertical {
            return verticalVC?.getCurrentCharOffset() ?? 0
        } else if !currentCache.pages.isEmpty {
            let idx = horizontalPageIndexForDisplay()
            if idx >= 0 && idx < currentCache.pages.count {
                return currentCache.pages[idx].globalRange.location
            }
        }
        return 0
    }

    private func scrollToCharOffset(_ offset: Int, animated: Bool, isEnd: Bool = false) {
        if currentReadingMode == .vertical {
            verticalVC?.scrollToCharOffset(offset, animated: animated, isEnd: isEnd)
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
        
        if self.isFirstLoad && !isManga {
            let initialOffset = (self.ttsManager.isPlaying && self.ttsManager.bookUrl == self.book.bookUrl && self.ttsManager.currentChapterIndex == index) 
                ? self.ttsManager.currentCharOffset 
                : Int((self.book.durChapterPos ?? 0) * Double(rawContent.count))
            reRenderCurrentContent(rawContentOverride: rawContent, anchorOffset: currentReadingMode == .horizontal ? initialOffset : 0)
        } else if startAtEnd && !isManga {
            reRenderCurrentContent(rawContentOverride: rawContent, anchorOffset: rawContent.count)
        } else {
            reRenderCurrentContent(rawContentOverride: rawContent, anchorOffset: 0)
        }

        if self.isFirstLoad && !self.isMangaMode {
            self.isFirstLoad = false
            if self.currentReadingMode == .horizontal {
                self.updateHorizontalPage(to: self.currentCache.anchorPageIndex, animated: false)
            } else if self.ttsManager.isPlaying && self.ttsManager.bookUrl == self.book.bookUrl {
                self.verticalVC?.scrollToSentence(index: self.ttsManager.currentSentenceIndex, animated: false)
            } else {
                self.verticalVC?.scrollToProgress(self.book.durChapterPos ?? 0)
            }
        } else if startAtEnd {
            self.scrollToCharOffset(self.currentCache.rawContent.count, animated: false, isEnd: true)
        } else {
            if currentReadingMode == .horizontal { self.updateHorizontalPage(to: self.currentCache.anchorPageIndex, animated: false) }
            else { self.verticalVC?.scrollToTop(animated: false) }
        }
        self.prefetchAdjacentChapters(index: index)
    }
    
    private func reRenderCurrentContent(rawContentOverride: String? = nil, anchorOffset: Int = 0) {
        guard let builder = chapterBuilder else { return }
        let rawContent = rawContentOverride ?? currentCache.rawContent
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        if isMangaMode {
            currentCache = builder.buildMangaCache(rawContent: rawContent, chapterUrl: nil)
        } else {
            currentCache = builder.buildTextCache(rawContent: rawContent, title: title, layoutSpec: currentLayoutSpec, reuseStore: currentCache.renderStore, chapterUrl: nil, anchorOffset: anchorOffset)
        }
        if currentReadingMode == .horizontal { self.currentPageIndex = currentCache.anchorPageIndex }
        setupReaderMode()
        updateProgressUI()
    }

    private func rebuildPaginationForLayout() {
        guard !isMangaMode, !currentCache.rawContent.isEmpty else { return }
        reRenderCurrentContent(anchorOffset: getCurrentReadingCharOffset())
    }

    private func updateProgressUI() {
        if isMangaMode || currentCache.pages.isEmpty { progressLabel.text = ""; return }
        let current = max(1, min(currentCache.pages.count, currentPageIndex + 1))
        progressLabel.text = currentReadingMode == .horizontal ? "\(current)/\(currentCache.pages.count)" : ""
    }

    private func updateVerticalAdjacent(secondaryIndices: Set<Int> = []) {
        guard let v = verticalVC, readerSettings != nil else { return }
        v.isInfiniteScrollEnabled = readerSettings.isInfiniteScrollEnabled
        v.seamlessSwitchThreshold = readerSettings.infiniteScrollSwitchThreshold
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        let nextTitle = (currentChapterIndex + 1 < chapters.count) ? chapters[currentChapterIndex + 1].title : nil
        let prevTitle = (currentChapterIndex - 1 >= 0) ? chapters[currentChapterIndex - 1].title : nil
        
        var highlightIdx = ttsManager.isPlaying ? ttsManager.currentSentenceIndex : nil
        if let hIdx = highlightIdx, ttsManager.hasChapterTitleInSentences {
            highlightIdx = ttsManager.isReadingChapterTitle ? nil : (hIdx - 1)
        }
        v.update(sentences: currentCache.contentSentences, nextSentences: nextCache.contentSentences.isEmpty ? nil : nextCache.contentSentences, prevSentences: prevCache.contentSentences.isEmpty ? nil : prevCache.contentSentences, title: title, nextTitle: nextTitle, prevTitle: prevTitle, fontSize: readerSettings.fontSize, lineSpacing: readerSettings.lineSpacing, margin: currentLayoutSpec.sideMargin, highlightIndex: highlightIdx, secondaryIndices: secondaryIndices, isPlaying: ttsManager.isPlaying)
    }

    private func setupReaderMode() {
        if isMangaMode {
            verticalVC?.view.removeFromSuperview(); verticalVC = nil
            horizontalVC?.view.removeFromSuperview(); horizontalVC = nil
            setupMangaMode()
        } else if currentReadingMode == .vertical {
            if verticalVC == nil {
                horizontalVC?.view.removeFromSuperview(); horizontalVC = nil
                mangaVC?.view.removeFromSuperview(); mangaVC?.removeFromParent(); mangaVC = nil
                setupVerticalMode()
            } else { updateVerticalAdjacent() }
        } else {
            if horizontalVC == nil {
                verticalVC?.view.removeFromSuperview(); verticalVC = nil
                mangaVC?.view.removeFromSuperview(); mangaVC?.removeFromParent(); mangaVC = nil
                setupHorizontalMode()
            }
        }
    }

    func toggleTTS() {
        guard !ttsManager.isPlaying else {
            if ttsManager.isPaused { ttsManager.resume() } else { ttsManager.pause() }
            return
        }
        guard currentChapterIndex < chapters.count else { return }
        let startIdx = currentReadingMode == .vertical ? (verticalVC?.getCurrentSentenceIndex() ?? 0) : (currentCache.pageInfos?[currentPageIndex].startSentenceIndex ?? 0)
        ttsManager.startReading(text: currentCache.rawContent, chapters: chapters, currentIndex: currentChapterIndex, bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, bookTitle: book.name ?? "未知", coverUrl: book.coverUrl, onChapterChange: { [weak self] newIdx in
            self?.jumpToChapter(newIdx)
        }, processedSentences: currentCache.contentSentences, textProcessor: { ReadingTextProcessor.prepareText($0, rules: self.replaceRuleViewModel?.rules) }, replaceRules: replaceRuleViewModel?.rules, startAtSentenceIndex: startIdx)
    }

    private func setupHorizontalMode() {
        let h = UIPageViewController(transitionStyle: readerSettings.pageTurningMode == .simulation ? .pageCurl : .scroll, navigationOrientation: .horizontal, options: nil)
        h.dataSource = self; h.delegate = self; addChild(h); view.insertSubview(h.view, at: 0); h.didMove(toParent: self)
        self.horizontalVC = h; updateHorizontalPage(to: currentPageIndex, animated: false)
    }

    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating f: Bool, previousViewControllers p: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let v = pvc.viewControllers?.first as? PageContentViewController else { return }
        if v.chapterOffset != 0 {
            let offset = v.chapterOffset
            if offset > 0 { prevCache = currentCache; currentCache = nextCache; nextCache = .empty }
            else { nextCache = currentCache; currentCache = prevCache; prevCache = .empty }
            currentChapterIndex += offset; lastReportedChapterIndex = currentChapterIndex; currentPageIndex = v.pageIndex
            onChapterIndexChanged?(currentChapterIndex); v.chapterOffset = 0
            prefetchAdjacentChapters(index: currentChapterIndex)
        } else { self.currentPageIndex = v.pageIndex }
        updateProgressUI()
        onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, currentCache.pages.count)))
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        guard let c = vc as? PageContentViewController else { return nil }
        if c.pageIndex > 0 { return createPageVC(at: c.pageIndex - 1, offset: 0) }
        return !prevCache.pages.isEmpty ? createPageVC(at: prevCache.pages.count - 1, offset: -1) : nil
    }
    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        guard let c = vc as? PageContentViewController else { return nil }
        if c.pageIndex < currentCache.pages.count - 1 { return createPageVC(at: c.pageIndex + 1, offset: 0) }
        return !nextCache.pages.isEmpty ? createPageVC(at: 0, offset: 1) : nil
    }

    private func updateHorizontalPage(to i: Int, animated: Bool) {
        guard let h = horizontalVC, !currentCache.pages.isEmpty else { return }
        currentPageIndex = max(0, min(i, currentCache.pages.count - 1))
        h.setViewControllers([createPageVC(at: currentPageIndex, offset: 0)], direction: .forward, animated: animated)
        updateProgressUI()
    }

    private func createPageVC(at i: Int, offset: Int) -> PageContentViewController {
        let vc = PageContentViewController(pageIndex: i, chapterOffset: offset); let pV = ReadContent2View(frame: .zero)
        let cache = offset == 0 ? currentCache : (offset > 0 ? nextCache : prevCache)
        pV.renderStore = cache.renderStore; pV.pageIndex = i
        if i < (cache.pageInfos?.count ?? 0), let info = cache.pageInfos?[i] {
            pV.pageInfo = TK2PageInfo(range: info.range, yOffset: info.yOffset, pageHeight: info.pageHeight, actualContentHeight: info.actualContentHeight, startSentenceIndex: info.startSentenceIndex, contentInset: currentLayoutSpec.topInset)
        }
        pV.onTapLocation = { [weak self] loc in if loc == .middle { self?.onToggleMenu?() } else { self?.handlePageTap(isNext: loc == .right) } }
        pV.onAddReplaceRule = { [weak self] text in self?.onAddReplaceRuleWithText?(text) }
        pV.horizontalInset = currentLayoutSpec.sideMargin
        vc.view.addSubview(pV); pV.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([pV.topAnchor.constraint(equalTo: vc.view.topAnchor), pV.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor), pV.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor), pV.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor)])
        return vc
    }

    private func handlePageTap(isNext: Bool) {
        let t = isNext ? currentPageIndex + 1 : currentPageIndex - 1
        if t >= 0 && t < currentCache.pages.count { updateHorizontalPage(to: t, animated: true) }
        else {
            let target = isNext ? currentChapterIndex + 1 : currentChapterIndex - 1
            if target >= 0 && target < chapters.count { jumpToChapter(target, startAtEnd: !isNext) }
        }
    }

    private func prefetchAdjacentChapters(index: Int) {
        guard let builder = chapterBuilder else { return }
        prefetchCoordinator.prefetchAdjacent(book: book, chapters: chapters, index: index, contentType: isMangaMode ? 2 : 0, layoutSpec: currentLayoutSpec, builder: builder, nextCache: nextCache, prevCache: prevCache, isMangaMode: isMangaMode, onNextCache: { [weak self] in self?.nextCache = $0; self?.updateVerticalAdjacent() }, onPrevCache: { [weak self] in self?.prevCache = $0; self?.updateVerticalAdjacent() }, onResetNext: { [weak self] in self?.nextCache = .empty }, onResetPrev: { [weak self] in self?.prevCache = .empty })
    }

    private func setupVerticalMode() {
        let v = VerticalTextViewController()
        v.onVisibleIndexChanged = { [weak self] idx in self?.onProgressChanged?(self?.currentChapterIndex ?? 0, Double(idx) / Double(max(1, self?.currentCache.contentSentences.count ?? 1))) }
        v.onAddReplaceRule = { [weak self] in self?.onAddReplaceRuleWithText?($0) }; v.onTapMenu = { [weak self] in self?.onToggleMenu?() }
        v.isInfiniteScrollEnabled = readerSettings.isInfiniteScrollEnabled
        v.onReachedBottom = { [weak self] in 
            guard let self = self, let b = self.chapterBuilder else { return }
            self.prefetchCoordinator.prefetchNextOnly(book: self.book, chapters: self.chapters, index: self.currentChapterIndex, contentType: 0, layoutSpec: self.currentLayoutSpec, builder: b, nextCache: self.nextCache, isMangaMode: false, onNextCache: { self.nextCache = $0; self.updateVerticalAdjacent() }, onResetNext: { self.nextCache = .empty })
        }
        v.onChapterSwitched = { [weak self] offset in 
            guard let self = self else { return }
            let target = self.currentChapterIndex + offset
            if target >= 0 && target < self.chapters.count { self.jumpToChapter(target, startAtEnd: offset < 0) }
        }
        self.verticalVC = v; addChild(v); view.insertSubview(v.view, at: 0); v.view.frame = view.bounds; v.didMove(toParent: self); v.safeAreaTop = safeAreaTop
        updateVerticalAdjacent()
    }

    private func setupMangaMode() {
        if mangaVC == nil {
            let vc = MangaReaderViewController(); vc.safeAreaTop = safeAreaTop; vc.onToggleMenu = { [weak self] in self?.onToggleMenu?() }
            vc.onChapterSwitched = { [weak self] in self?.jumpToChapter((self?.currentChapterIndex ?? 0) + $0, startAtEnd: $0 < 0) }
            addChild(vc); view.insertSubview(vc.view, at: 0); vc.view.frame = view.bounds; vc.didMove(toParent: self); self.mangaVC = vc
        }
        mangaVC?.update(urls: currentCache.contentSentences)
    }
    
    // MARK: - TTS Support
    func syncTTSReadingPositionIfNeeded() {
        guard pendingTTSPositionSync else { return }
        pendingTTSPositionSync = false
        guard let bookUrl = book.bookUrl, ttsManager.bookUrl == bookUrl else { return }
        let position = currentStartPosition()
        ttsManager.updateReadingPosition(to: position)
    }

    func handleUserScrollCatchUp() {
        guard pendingTTSPositionSync else { return }
        pendingTTSPositionSync = false
        guard let bookUrl = book.bookUrl, ttsManager.bookUrl == bookUrl else { return }
        guard ttsManager.isPlaying && !ttsManager.isPaused else { return }
        if !isTTSPositionInCurrentPage() { restartTTSFromCurrentPageStart() } else { syncTTSState() }
    }

    func syncTTSState() {
        if isMangaMode { return }
        guard ttsManager.isReady && ttsManager.currentChapterIndex == currentChapterIndex else { return }
        if chapters.indices.contains(currentChapterIndex) {
            guard currentCache.chapterUrl == chapters[currentChapterIndex].url else { return }
        }
        let sentenceIndex = ttsManager.currentSentenceIndex
        if currentReadingMode == .vertical { 
            var finalIdx: Int? = sentenceIndex
            var secondaryIdxs = Set(ttsManager.preloadedIndices)
            if ttsManager.hasChapterTitleInSentences {
                finalIdx = ttsManager.isReadingChapterTitle ? nil : (sentenceIndex - 1)
                secondaryIdxs = Set(ttsManager.preloadedIndices.compactMap { $0 > 0 ? ($0 - 1) : nil })
            }
            verticalVC?.setHighlight(index: finalIdx, secondaryIndices: secondaryIdxs, isPlaying: ttsManager.isPlaying)
        }
        let now = Date().timeIntervalSince1970
        guard !isUserInteracting, ttsManager.isPlaying, now >= suppressTTSFollowUntil else { return }
        if currentReadingMode == .vertical {
            verticalVC?.ensureSentenceVisible(index: sentenceIndex)
        } else if currentReadingMode == .horizontal {
            if ttsManager.isReadingChapterTitle { if currentPageIndex != 0 { updateHorizontalPage(to: 0, animated: true) }; return }
            let bodySentenceIdx = ttsManager.hasChapterTitleInSentences ? (sentenceIndex - 1) : sentenceIndex
            guard bodySentenceIdx >= 0 else { return }
            let starts = currentCache.paragraphStarts
            if bodySentenceIdx < starts.count {
                let realTimeOffset = starts[bodySentenceIdx] + ttsManager.currentSentenceOffset + paragraphIndentLength
                let currentIndex = horizontalPageIndexForDisplay()
                if currentIndex < currentCache.pages.count {
                    if !NSLocationInRange(realTimeOffset, currentCache.pages[currentIndex].globalRange) {
                        if let targetPage = currentCache.pages.firstIndex(where: { NSLocationInRange(realTimeOffset, $0.globalRange) }) {
                            if targetPage != currentPageIndex { updateHorizontalPage(to: targetPage, animated: true) }
                        }
                    }
                }
            }
        }
    }

    private func isTTSPositionInCurrentPage() -> Bool {
        guard ttsManager.currentChapterIndex == currentChapterIndex else { return false }
        if currentReadingMode == .vertical { return verticalVC?.isSentenceVisible(index: ttsManager.currentSentenceIndex) ?? true }
        if ttsManager.isReadingChapterTitle { return currentPageIndex == 0 }
        let pageIndex = horizontalPageIndexForDisplay()
        guard pageIndex < (currentCache.pageInfos?.count ?? 0) else { return true }
        let starts = currentCache.paragraphStarts
        let bodySentenceIdx = ttsManager.hasChapterTitleInSentences ? (ttsManager.currentSentenceIndex - 1) : ttsManager.currentSentenceIndex
        guard bodySentenceIdx >= 0 && bodySentenceIdx < starts.count else { return false }
        let totalOffset = starts[bodySentenceIdx] + ttsManager.currentSentenceOffset + paragraphIndentLength
        return NSLocationInRange(totalOffset, currentCache.pages[pageIndex].globalRange)
    }

    private func restartTTSFromCurrentPageStart() {
        guard currentChapterIndex < chapters.count else { return }
        let startPos = currentStartPosition()
        ttsManager.startReading(text: currentCache.rawContent, chapters: chapters, currentIndex: currentChapterIndex, bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, bookTitle: book.name ?? "未知", coverUrl: book.coverUrl, onChapterChange: { [weak self] in self?.jumpToChapter($0) }, processedSentences: currentCache.contentSentences, textProcessor: { ReadingTextProcessor.prepareText($0, rules: self.replaceRuleViewModel?.rules) }, replaceRules: replaceRuleViewModel?.rules, startAtSentenceIndex: startPos.sentenceIndex, startAtSentenceOffset: startPos.sentenceOffset, shouldSpeakChapterTitle: startPos.isAtChapterStart)
    }

    private func currentStartPosition() -> ReadingPosition {
        let starts = currentCache.paragraphStarts
        let sentences = currentCache.contentSentences
        guard !starts.isEmpty && !sentences.isEmpty else { 
            return ReadingPosition(chapterIndex: currentChapterIndex, sentenceIndex: 0, sentenceOffset: 0, charOffset: 0) 
        }
        
        var charOffset = 0
        if currentReadingMode == .horizontal {
            let idx = horizontalPageIndexForDisplay()
            if idx < (currentCache.pageInfos?.count ?? 0) { charOffset = currentCache.pageInfos?[idx].range.location ?? 0 }
        } else { charOffset = verticalVC?.getCurrentCharOffset() ?? 0 }
        
        // 确保索引在有效范围内
        let foundIdx = starts.lastIndex(where: { $0 <= charOffset }) ?? 0
        let sentenceIndex = max(0, min(foundIdx, sentences.count - 1))
        
        let sentenceStart = starts[sentenceIndex]
        let offsetInSentence = max(0, charOffset - sentenceStart - paragraphIndentLength)
        let maxSentenceLen = sentences[sentenceIndex].utf16.count
        
        return ReadingPosition(
            chapterIndex: currentChapterIndex, 
            sentenceIndex: sentenceIndex, 
            sentenceOffset: min(maxSentenceLen, offsetInSentence), 
            charOffset: charOffset
        )
    }

    private func horizontalPageIndexForDisplay() -> Int {
        if let visible = visibleHorizontalPageIndex, visible >= 0, visible < currentCache.pages.count { return visible }
        return currentPageIndex
    }

    private func notifyUserInteractionStarted() {
        isUserInteracting = true; pendingTTSPositionSync = true
        suppressTTSFollowUntil = Date().timeIntervalSince1970 + (readerSettings?.ttsFollowCooldown ?? 5.0)
        ttsSyncCoordinator?.userInteractionStarted()
    }
    private func notifyUserInteractionEnded() {
        suppressTTSFollowUntil = Date().timeIntervalSince1970 + (readerSettings?.ttsFollowCooldown ?? 5.0)
        ttsSyncCoordinator?.scheduleCatchUp(delay: readerSettings?.ttsFollowCooldown ?? 5.0)
    }
    func finalizeUserInteraction() { isUserInteracting = false }
    func consumePrefetchedMangaContent(for index: Int) -> String? {
        guard prefetchedMangaNextIndex == index else { return nil }
        let c = prefetchedMangaNextContent; prefetchedMangaNextIndex = nil; prefetchedMangaNextContent = nil; return c
    }
    func resetMangaPrefetchedContent() { nextCache = .empty; prefetchedMangaNextIndex = nil; prefetchedMangaNextContent = nil }
}

class PageContentViewController: UIViewController {
    let pageIndex: Int; var chapterOffset: Int
    init(pageIndex: Int, chapterOffset: Int) { self.pageIndex = pageIndex; self.chapterOffset = chapterOffset; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
}
