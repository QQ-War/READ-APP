import SwiftUI
import UIKit
import Combine

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
    @ObservedObject var preferences: UserPreferences
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
        vc.book = book; vc.preferences = preferences; vc.ttsManager = ttsManager
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
        vc.updatePreferences(preferences)
        vc.updateReplaceRules(replaceRuleViewModel.rules)
        
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
    var book: Book!; var chapters: [BookChapter] = []; var preferences: UserPreferences!; var ttsManager: TTSManager!; var replaceRuleViewModel: ReplaceRuleViewModel?
    var onToggleMenu: (() -> Void)?; var onAddReplaceRuleWithText: ((String) -> Void)?; var onProgressChanged: ((Int, Double) -> Void)?
    var onChapterIndexChanged: ((Int) -> Void)?; var onChaptersLoaded: (([BookChapter]) -> Void)?; var onModeDetected: ((Bool) -> Void)?
    
    private var safeAreaTop: CGFloat = 47; private var safeAreaBottom: CGFloat = 34
    private var currentLayoutSpec: ReaderLayoutSpec {
        return ReaderLayoutSpec(
            topInset: max(safeAreaTop, view.safeAreaInsets.top) + 15,
            bottomInset: max(safeAreaBottom, view.safeAreaInsets.bottom) + 40,
            sideMargin: preferences.pageHorizontalMargin + 8,
            pageSize: view.bounds.size
        )
    }
    
    private(set) var currentChapterIndex: Int = 0
    var lastReportedChapterIndex: Int = -1
    private(set) var currentReadingMode: ReadingMode = .vertical
    var isInternalTransitioning = false
    private var isFirstLoad = true
    private var isUserInteracting = false
    private var cancellables: Set<AnyCancellable> = []
    
    private var rawContent: String = ""; private var contentSentences: [String] = []
    private var renderStore: TextKit2RenderStore?
    private var pages: [PaginatedPage] = []; private var pageInfos: [TK2PageInfo] = []
    private var currentParagraphStarts: [Int] = []
    private var currentPageIndex: Int = 0; private var isMangaMode = false
    
    private var nextChapterStore: TextKit2RenderStore?; private var prevChapterStore: TextKit2RenderStore?
    private var nextChapterPages: [PaginatedPage] = []; private var prevChapterPages: [PaginatedPage] = []
    private var nextChapterPageInfos: [TK2PageInfo] = []; private var prevChapterPageInfos: [TK2PageInfo] = []
    private var nextChapterSentences: [String]?; private var prevChapterSentences: [String]?
    private var nextChapterRawContent: String?; private var prevChapterRawContent: String?

    private var verticalVC: VerticalTextViewController?; private var horizontalVC: UIPageViewController?; private var mangaVC: MangaReaderViewController?
    private let progressLabel = UILabel()
    private var lastLayoutSignature: String = ""
    private var loadToken: Int = 0
    private var prefetchNextTask: Task<Void, Never>?; private var prefetchPrevTask: Task<Void, Never>?
    private var lastChapterSwitchTime: TimeInterval = 0
    private let chapterSwitchCooldown: TimeInterval = 1.0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupProgressLabel()
        currentChapterIndex = book.durChapterIndex ?? 0
        lastReportedChapterIndex = currentChapterIndex
        currentReadingMode = preferences.readingMode
        loadChapters()
        setupTTSObservers()
    }
    
    private func setupTTSObservers() {
        ttsManager.$currentSentenceIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncTTSState() }
            .store(in: &cancellables)
            
        ttsManager.$isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncTTSState() }
            .store(in: &cancellables)
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
        
        if !isMangaMode, renderStore != nil, currentReadingMode == .horizontal {
            let spec = currentLayoutSpec
            let signature = "\(Int(spec.pageSize.width))x\(Int(spec.pageSize.height))|\(Int(spec.topInset))"
            if signature != lastLayoutSignature {
                lastLayoutSignature = signature
                let offset = (currentPageIndex < pages.count) ? pages[currentPageIndex].globalRange.location : 0
                prepareRenderStore(); performPagination()
                currentPageIndex = pages.firstIndex(where: { NSLocationInRange(offset, $0.globalRange) }) ?? 0
                updateHorizontalPage(to: currentPageIndex, animated: false)
            }
        }
    }

    func updateLayout(safeArea: EdgeInsets) { self.safeAreaTop = safeArea.top; self.safeAreaBottom = safeArea.bottom }
    func updatePreferences(_ prefs: UserPreferences) {
        let oldP = self.preferences!; self.preferences = prefs
        if (oldP.fontSize != prefs.fontSize || oldP.lineSpacing != prefs.lineSpacing) && !isMangaMode { 
            reRenderCurrentContent() 
        } else if !isMangaMode && currentReadingMode == .vertical {
            updateVerticalAdjacent()
        }
    }
    func updateReplaceRules(_ rules: [ReplaceRule]) { 
        if !rawContent.isEmpty && !isMangaMode { 
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
        } else if !pages.isEmpty && currentPageIndex < pages.count {
            return pages[currentPageIndex].globalRange.location
        }
        return 0
    }
    
    private func scrollToCharOffset(_ offset: Int, animated: Bool) {
        if currentReadingMode == .vertical {
            verticalVC?.scrollToCharOffset(offset, animated: animated)
        } else {
            if let targetPage = pages.firstIndex(where: { NSLocationInRange(offset, $0.globalRange) }) {
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
        } catch { print("Load chapters failed") } }
    }
    
    private func loadChapterContent(at index: Int, startAtEnd: Bool = false) {
        loadToken += 1; let token = loadToken
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let isM = book.type == 2 || preferences.manualMangaUrls.contains(book.bookUrl ?? "")
                let content = try await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index, contentType: isM ? 2 : 0)
                await MainActor.run {
                    guard self.loadToken == token else { return }
                    self.rawContent = content; self.isMangaMode = isM; self.onModeDetected?(isM)
                    self.reRenderCurrentContent()
                    
                    if self.isFirstLoad && !self.isMangaMode {
                        self.isFirstLoad = false
                        // 优先检查 TTS 状态：如果正在播放同一本书的当前章节，则定位到 TTS 句子
                        if self.ttsManager.isPlaying && self.ttsManager.bookUrl == self.book.bookUrl && self.ttsManager.currentChapterIndex == index {
                            let sentenceIdx = self.ttsManager.currentSentenceIndex
                            if self.currentReadingMode == .horizontal {
                                self.syncHorizontalPageToTTS(sentenceIndex: sentenceIdx)
                            } else {
                                self.verticalVC?.scrollToSentence(index: sentenceIdx, animated: false)
                            }
                        } else {
                            let pos = self.book.durChapterPos ?? 0
                            let targetPage = Int(round(pos * Double(max(1, self.pages.count))))
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
                }
            } catch { print("Content load failed") }
        }
    }
    
    private func reRenderCurrentContent() {
        if isMangaMode {
            let imgs = extractMangaImageSentences(from: rawContent)
            self.contentSentences = imgs.isEmpty ? removeHTMLAndSVG(rawContent).components(separatedBy: "\n") : imgs
        } else {
            let processed = applyReplaceRules(to: removeHTMLAndSVG(rawContent))
            // 核心修改：在此处进行 trim，确保后续所有逻辑（分页、渲染）使用的数据都是干净的
            self.contentSentences = processed.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            prepareRenderStore(); performPagination()
        }
        setupReaderMode(); updateProgressUI()
    }
    
    private func updateProgressUI() {
        if isMangaMode || pages.isEmpty { progressLabel.text = ""; return }
        let total = pages.count
        let current = max(1, min(total, currentPageIndex + 1))
        progressLabel.text = currentReadingMode == .horizontal ? "\(current)/\(total)" : ""
    }
    
    private func updateVerticalAdjacent(secondaryIndices: Set<Int> = []) {
        guard !isMangaMode, currentReadingMode == .vertical else { return }
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        let nextTitle = (currentChapterIndex + 1 < chapters.count) ? chapters[currentChapterIndex + 1].title : nil
        let prevTitle = (currentChapterIndex - 1 >= 0) ? chapters[currentChapterIndex - 1].title : nil
        verticalVC?.isInfiniteScrollEnabled = preferences.isInfiniteScrollEnabled
        let nextSentences = preferences.isInfiniteScrollEnabled ? nextChapterSentences : nil
        let prevSentences = preferences.isInfiniteScrollEnabled ? prevChapterSentences : nil
        let highlightIndex = ttsManager.isPlaying ? ttsManager.currentSentenceIndex : nil
        verticalVC?.update(sentences: contentSentences, nextSentences: nextSentences, prevSentences: prevSentences, title: title, nextTitle: nextTitle, prevTitle: prevTitle, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, margin: preferences.pageHorizontalMargin, highlightIndex: highlightIndex, secondaryIndices: secondaryIndices, isPlaying: ttsManager.isPlaying)
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
            var ttsSentences = contentSentences
            if startPos.offset > 0 && startPos.index < ttsSentences.count {
                let sentence = ttsSentences[startPos.index]
                let utf16Count = sentence.utf16.count
                let clamped = min(startPos.offset, utf16Count)
                let idx = String.Index(utf16Offset: clamped, in: sentence)
                let tail = String(sentence[idx...])
                if !tail.isEmpty { ttsSentences[startPos.index] = tail }
            }
            ttsManager.startReading(
                text: rawContent,
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
                startAtSentenceIndex: startPos.index,
                shouldSpeakChapterTitle: startPos.index == 0 && startPos.offset == 0
            )
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isUserInteracting = true
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { isUserInteracting = false }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        isUserInteracting = false
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isUserInteracting = false
    }

    private func setupHorizontalMode() {
        let h = UIPageViewController(transitionStyle: preferences.pageTurningMode == .simulation ? .pageCurl : .scroll, navigationOrientation: .horizontal, options: nil)
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
            self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, pages.count)))
            updateProgressUI()
        }
    }

    private func completeDataDrift(offset: Int, targetPage: Int, currentVC: PageContentViewController?) {
        self.isInternalTransitioning = true
        if offset > 0 {
            prevChapterStore = renderStore; prevChapterPages = pages; prevChapterPageInfos = pageInfos; prevChapterSentences = contentSentences; prevChapterRawContent = rawContent
            renderStore = nextChapterStore; pages = nextChapterPages; pageInfos = nextChapterPageInfos; contentSentences = nextChapterSentences ?? []; rawContent = nextChapterRawContent ?? ""
            nextChapterStore = nil; nextChapterPages = []; nextChapterPageInfos = []
        } else {
            nextChapterStore = renderStore; nextChapterPages = pages; nextChapterPageInfos = pageInfos; nextChapterSentences = contentSentences; nextChapterRawContent = rawContent
            renderStore = prevChapterStore; pages = prevChapterPages; pageInfos = prevChapterPageInfos; contentSentences = prevChapterSentences ?? []; rawContent = prevChapterRawContent ?? ""
            prevChapterStore = nil; prevChapterPages = []; prevChapterPageInfos = []
        }
        
        self.currentChapterIndex += offset
        self.lastReportedChapterIndex = self.currentChapterIndex
        self.currentPageIndex = targetPage
        self.onChapterIndexChanged?(self.currentChapterIndex)
        
        if let v = currentVC {
            v.chapterOffset = 0
            if let rv = v.view.subviews.first as? ReadContent2View {
                rv.renderStore = self.renderStore
            }
        }
        
        self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, pages.count)))
        updateProgressUI()
        prefetchAdjacentChapters(index: currentChapterIndex)
        self.isInternalTransitioning = false
    }
    
    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        guard let c = vc as? PageContentViewController, !isInternalTransitioning else { return nil }
        if c.chapterOffset == 0 {
            if c.pageIndex > 0 { return createPageVC(at: c.pageIndex - 1, offset: 0) }
            if !prevChapterPages.isEmpty { return createPageVC(at: prevChapterPages.count - 1, offset: -1) }
        }
        return nil
    }
    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        guard let c = vc as? PageContentViewController, !isInternalTransitioning else { return nil }
        if c.chapterOffset == 0 {
            if c.pageIndex < pages.count - 1 { return createPageVC(at: c.pageIndex + 1, offset: 0) }
            if !nextChapterPages.isEmpty { return createPageVC(at: 0, offset: 1) }
        }
        return nil
    }
    
    private func updateHorizontalPage(to i: Int, animated: Bool) {
        guard let h = horizontalVC, !pages.isEmpty else { return }
        let targetIndex = max(0, min(i, pages.count - 1))
        let direction: UIPageViewController.NavigationDirection = targetIndex >= currentPageIndex ? .forward : .reverse
        currentPageIndex = targetIndex
        h.setViewControllers([createPageVC(at: targetIndex, offset: 0)], direction: direction, animated: animated)
        updateProgressUI()
        self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, pages.count)))
    }
    
    private func createPageVC(at i: Int, offset: Int) -> PageContentViewController {
        let vc = PageContentViewController(pageIndex: i, chapterOffset: offset); let pV = ReadContent2View(frame: .zero)
        let aS = (offset == 0) ? renderStore : (offset > 0 ? nextChapterStore : prevChapterStore)
        let aI = (offset == 0) ? pageInfos : (offset > 0 ? nextChapterPageInfos : prevChapterPageInfos)
        pV.renderStore = aS; if i < aI.count { 
            let info = aI[i]; pV.pageInfo = TK2PageInfo(range: info.range, yOffset: info.yOffset, pageHeight: info.pageHeight, actualContentHeight: info.actualContentHeight, startSentenceIndex: info.startSentenceIndex, contentInset: currentLayoutSpec.topInset)
        }
        pV.onTapLocation = { [weak self] loc in if loc == .middle { self?.onToggleMenu?() } else { self?.handlePageTap(isNext: loc == .right) } }
        pV.horizontalInset = currentLayoutSpec.sideMargin; vc.view.addSubview(pV); pV.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([pV.topAnchor.constraint(equalTo: vc.view.topAnchor), pV.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor), pV.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor), pV.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor)])
        return vc
    }
    
    private func handlePageTap(isNext: Bool) {
        let t = isNext ? currentPageIndex + 1 : currentPageIndex - 1
        if t >= 0 && t < pages.count { 
            updateHorizontalPage(to: t, animated: true) 
        } else {
            let targetChapter = isNext ? currentChapterIndex + 1 : currentChapterIndex - 1
            guard targetChapter >= 0 && targetChapter < chapters.count else { return }
            
            if isNext, !nextChapterPages.isEmpty {
                animateToAdjacentChapter(offset: 1, targetPage: 0)
            } else if !isNext, !prevChapterPages.isEmpty {
                animateToAdjacentChapter(offset: -1, targetPage: prevChapterPages.count - 1)
            } else {
                jumpToChapter(targetChapter, startAtEnd: !isNext)
            }
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
        if isMangaMode { return }
        prefetchNextTask?.cancel(); prefetchPrevTask?.cancel()
        if index + 1 < chapters.count {
            prefetchNextTask = Task { if let content = try? await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index + 1, contentType: 0) {
                await MainActor.run { guard !Task.isCancelled else { return }
                    let processed = self.applyReplaceRules(to: self.removeHTMLAndSVG(content)); let sents = processed.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    let title = self.chapters[index + 1].title; let attr = self.createAttrString(processed, title: title); let spec = self.currentLayoutSpec
                    let store = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, spec.pageSize.width - spec.sideMargin * 2))
                    let res = self.performSilentPagination(for: store, sentences: sents, title: title)
                    self.nextChapterStore = store; self.nextChapterPages = res.pages; self.nextChapterPageInfos = res.pageInfos; self.nextChapterSentences = sents; self.nextChapterRawContent = content
                    self.updateVerticalAdjacent()
                }
            } }
        }
        if index - 1 >= 0 {
            prefetchPrevTask = Task { if let content = try? await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index - 1, contentType: 0) {
                await MainActor.run { guard !Task.isCancelled else { return }
                    let processed = self.applyReplaceRules(to: self.removeHTMLAndSVG(content)); let sents = processed.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    let title = self.chapters[index - 1].title; let attr = self.createAttrString(processed, title: title); let spec = self.currentLayoutSpec
                    let store = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, spec.pageSize.width - spec.sideMargin * 2))
                    let res = self.performSilentPagination(for: store, sentences: sents, title: title)
                    self.prevChapterStore = store; self.prevChapterPages = res.pages; self.prevChapterPageInfos = res.pageInfos; self.prevChapterSentences = sents; self.prevChapterRawContent = content
                    self.updateVerticalAdjacent()
                }
            } }
        }
    }

    private func performSilentPagination(for store: TextKit2RenderStore, sentences: [String], title: String) -> TextKit2Paginator.PaginationResult {
        let spec = currentLayoutSpec
        var pS: [Int] = []
        var c = title.isEmpty ? 0 : (title + "\n").utf16.count
        for s in sentences {
            pS.append(c)
            c += (s.count + 2 + 1) // 2 是全角空格 "　　" 的长度，1 是换行符
        }
        return TextKit2Paginator.paginate(renderStore: store, pageSize: spec.pageSize, paragraphStarts: pS, prefixLen: title.isEmpty ? 0 : (title + "\n").utf16.count, topInset: spec.topInset, bottomInset: spec.bottomInset)
    }

    private func createAttrString(_ text: String, title: String) -> NSAttributedString {
        let fullAttr = NSMutableAttributedString()
        if !title.isEmpty { 
            let p = NSMutableParagraphStyle()
            p.alignment = .center
            p.paragraphSpacing = preferences.fontSize * 1.5
            fullAttr.append(NSAttributedString(string: title + "\n", attributes: [.font: UIFont.systemFont(ofSize: preferences.fontSize + 8, weight: .bold), .foregroundColor: UIColor.label, .paragraphStyle: p])) 
        }
        
        let style = NSMutableParagraphStyle()
        style.lineSpacing = preferences.lineSpacing
        style.alignment = .justified
        // 移除 style.firstLineHeadIndent = preferences.fontSize * 1.5
        
        // 为每一段开头手动增加两个全角空格
        let indentedText = text.components(separatedBy: "\n").map { "　　" + $0 }.joined(separator: "\n")
        
        fullAttr.append(NSAttributedString(string: indentedText, attributes: [
            .font: UIFont.systemFont(ofSize: preferences.fontSize),
            .foregroundColor: UIColor.label,
            .paragraphStyle: style
        ]))
        return fullAttr
    }

    private func prepareRenderStore() {
        let spec = currentLayoutSpec; let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        let attrString = createAttrString(contentSentences.joined(separator: "\n"), title: title)
        let width = max(100, spec.pageSize.width - spec.sideMargin * 2)
        if let store = renderStore { store.update(attributedString: attrString, layoutWidth: width) } else { renderStore = TextKit2RenderStore(attributedString: attrString, layoutWidth: width) }
    }
    
    private func performPagination() {
        guard let s = renderStore else { return }; let spec = currentLayoutSpec
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        let pLen = title.isEmpty ? 0 : (title + "\n").utf16.count
        var starts: [Int] = []; var curr = pLen; for sent in contentSentences { 
            starts.append(curr)
            curr += (sent.count + 2 + 1) // 2 是全角空格 "　　" 的长度，1 是换行符
        }
        let res = TextKit2Paginator.paginate(renderStore: s, pageSize: spec.pageSize, paragraphStarts: starts, prefixLen: pLen, topInset: spec.topInset, bottomInset: spec.bottomInset)
        self.pages = res.pages; self.pageInfos = res.pageInfos
        self.currentParagraphStarts = starts
    }

    private func setupVerticalMode() {
        let v = VerticalTextViewController(); v.onVisibleIndexChanged = { [weak self] idx in self?.onProgressChanged?(self?.currentChapterIndex ?? 0, Double(idx) / Double(max(1, self?.contentSentences.count ?? 1))) }
        v.onAddReplaceRule = { [weak self] text in self?.onAddReplaceRuleWithText?(text) }; v.onTapMenu = { [weak self] in self?.onToggleMenu?() }
        v.isInfiniteScrollEnabled = preferences.isInfiniteScrollEnabled
        v.onChapterSwitched = { [weak self] offset in 
            guard let self = self else { return }
            
            // 如果关闭了无限流，禁止滚动自动切换章节
            if !self.preferences.isInfiniteScrollEnabled { return }
            
            // 连跳保护
            let now = Date().timeIntervalSince1970
            guard now - self.lastChapterSwitchTime > self.chapterSwitchCooldown else { return }
            
            let target = self.currentChapterIndex + offset
            guard target >= 0 && target < self.chapters.count else { return }
            
            self.lastChapterSwitchTime = now
            self.jumpToChapter(target, startAtEnd: offset < 0)
        }
        v.onInteractionChanged = { [weak self] interacting in self?.isUserInteracting = interacting }
        addChild(v); view.insertSubview(v.view, at: 0); v.view.frame = view.bounds; v.didMove(toParent: self); v.safeAreaTop = safeAreaTop
        
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        let nextTitle = (currentChapterIndex + 1 < chapters.count) ? chapters[currentChapterIndex + 1].title : nil
        let prevTitle = (currentChapterIndex - 1 >= 0) ? chapters[currentChapterIndex - 1].title : nil
        let nextSentences = preferences.isInfiniteScrollEnabled ? nextChapterSentences : nil
        let prevSentences = preferences.isInfiniteScrollEnabled ? prevChapterSentences : nil
        v.update(sentences: contentSentences, nextSentences: nextSentences, prevSentences: prevSentences, title: title, nextTitle: nextTitle, prevTitle: prevTitle, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, margin: preferences.pageHorizontalMargin, highlightIndex: ttsManager.isPlaying ? ttsManager.currentSentenceIndex : nil, secondaryIndices: [], isPlaying: ttsManager.isPlaying)
        self.verticalVC = v
    }
    
    private func setupMangaMode() {
        if mangaVC == nil {
            let vc = MangaReaderViewController()
            vc.safeAreaTop = safeAreaTop
            vc.onToggleMenu = { [weak self] in self?.onToggleMenu?() }
            vc.onInteractionChanged = { [weak self] interacting in self?.isUserInteracting = interacting }
            vc.onChapterSwitched = { [weak self] offset in
                guard let self = self else { return }
                let now = Date().timeIntervalSince1970
                guard now - self.lastChapterSwitchTime > self.chapterSwitchCooldown else { return }
                let target = self.currentChapterIndex + offset
                guard target >= 0 && target < self.chapters.count else { return }
                self.lastChapterSwitchTime = now
                self.jumpToChapter(target, startAtEnd: offset < 0)
            }
            addChild(vc); view.insertSubview(vc.view, at: 0); vc.view.frame = view.bounds; vc.didMove(toParent: self)
            self.mangaVC = vc
        }
        let imgs = extractMangaImageSentences(from: rawContent)
        mangaVC?.update(urls: imgs)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { return nil }
    func syncTTSState() {
        if isMangaMode || isUserInteracting { return }
        let hIndex = ttsManager.currentSentenceIndex
        if currentReadingMode == .vertical { 
            updateVerticalAdjacent(secondaryIndices: Set(ttsManager.preloadedIndices))
        }
        else if currentReadingMode == .horizontal && ttsManager.isPlaying { 
            syncHorizontalPageToTTS(sentenceIndex: hIndex) 
        }
    }

    private func syncHorizontalPageToTTS(sentenceIndex: Int) { 
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        let pLen = title.isEmpty ? 0 : (title + "\n").utf16.count
        
        var curr = pLen
        var pS: [Int] = []
        for s in contentSentences { 
            pS.append(curr)
            curr += (s.count + 2 + 1) // 计入全角空格和换行符
        }
        
        guard sentenceIndex < pS.count else { return }
        let o = pS[sentenceIndex]
        
        if let t = pages.firstIndex(where: { NSLocationInRange(o, $0.globalRange) }), t != currentPageIndex { 
            // 只有当 TTS 正在播放且不是用户正在手动翻页时才自动跳转
            if ttsManager.isPlaying && !isUserInteracting {
                updateHorizontalPage(to: t, animated: true) 
            }
        }
    }
    private func currentStartPosition() -> (index: Int, offset: Int) {
        guard !contentSentences.isEmpty else { return (0, 0) }
        let offset: Int
        if currentReadingMode == .horizontal, currentPageIndex < pageInfos.count {
            offset = pageInfos[currentPageIndex].range.location
        } else if currentReadingMode == .vertical {
            offset = verticalVC?.getCurrentCharOffset() ?? 0
        } else {
            offset = 0
        }
        let starts = currentParagraphStarts
        if starts.isEmpty { return (0, 0) }
        let idx = max(0, min((starts.lastIndex(where: { $0 <= offset }) ?? 0), contentSentences.count - 1))
        let start = starts[idx]
        var intra = max(0, offset - start)
        let indentLen = 2
        intra = intra >= indentLen ? intra - indentLen : 0
        let maxLen = contentSentences[idx].utf16.count
        intra = min(intra, maxLen)
        return (idx, intra)
    }
    private func scrollToChapterEnd(animated: Bool) { 
        if isMangaMode, let m = mangaVC { 
            let sv = m.scrollView
            sv.setContentOffset(CGPoint(x: 0, y: max(0, sv.contentSize.height - sv.bounds.height)), animated: animated) 
        } else if currentReadingMode == .vertical { 
            verticalVC?.scrollToBottom(animated: animated) 
        } else if !pages.isEmpty { 
            updateHorizontalPage(to: max(0, pages.count - 1), animated: animated) 
        } 
    }
    private func applyReplaceRules(to text: String) -> String { guard let rules = replaceRuleViewModel?.rules else { return text }; var res = text; for r in rules where r.isEnabled == true { if r.isRegex == true { if let reg = try? NSRegularExpression(pattern: r.pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) { res = reg.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: res.utf16.count), withTemplate: r.replacement) } } else { res = res.replacingOccurrences(of: r.pattern, with: r.replacement) } }; return res }
    private func removeHTMLAndSVG(_ text: String) -> String { var res = text; let patterns = ["<svg[^>]*>.*?</svg>", "<img[^>]*>", "<[^>]+>"]; for p in patterns { if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators]) { res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: res.utf16.count), withTemplate: "") } }; return res.replacingOccurrences(of: "&nbsp;", with: " ") }
    private func extractMangaImageSentences(from text: String) -> [String] { let pattern = #"<img[^>]+(?:src|data-src|data-original)=["']([^"']+)["'][^>]*>"#; guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }; let nsText = text as NSString; let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)); return matches.compactMap { match in guard match.numberOfRanges > 1 else { return nil }; return "__IMG__" + nsText.substring(with: match.range(at: 1)) } }
}
class PageContentViewController: UIViewController { var pageIndex: Int; var chapterOffset: Int; init(pageIndex: Int, chapterOffset: Int) { self.pageIndex = pageIndex; self.chapterOffset = chapterOffset; super.init(nibName: nil, bundle: nil) }; required init?(coder: NSCoder) { fatalError() } }
