import SwiftUI
import UIKit
import Combine

// MARK: - SwiftUI 桥接入口
struct ReaderContainerRepresentable: UIViewControllerRepresentable {
    let book: Book
    @ObservedObject var preferences: UserPreferences
    @ObservedObject var ttsManager: TTSManager
    @ObservedObject var replaceRuleViewModel: ReplaceRuleViewModel // 注入规则
    
    @Binding var chapters: [BookChapter]
    @Binding var currentChapterIndex: Int
    
    var onToggleMenu: () -> Void
    var onAddReplaceRule: (String) -> Void
    var onProgressChanged: (Int, Double) -> Void
    
    var readingMode: ReadingMode
    
    func makeUIViewController(context: Context) -> ReaderContainerViewController {
        let vc = ReaderContainerViewController()
        vc.book = book; vc.preferences = preferences; vc.ttsManager = ttsManager
        vc.replaceRuleViewModel = replaceRuleViewModel
        vc.onToggleMenu = onToggleMenu; vc.onAddReplaceRuleWithText = onAddReplaceRule
        vc.onProgressChanged = { idx, pos in
            DispatchQueue.main.async {
                self.currentChapterIndex = idx
                onProgressChanged(idx, pos)
            }
        }
        vc.onChaptersLoaded = { list in
            DispatchQueue.main.async { self.chapters = list }
        }
        return vc
    }
    
    func updateUIViewController(_ vc: ReaderContainerViewController, context: Context) {
        vc.updatePreferences(preferences)
        // 规则变化时触发刷新
        vc.updateReplaceRules(replaceRuleViewModel.rules)
        
        if vc.currentChapterIndex != currentChapterIndex {
            vc.jumpToChapter(currentChapterIndex)
        }
        if vc.currentReadingMode != readingMode {
            vc.switchReadingMode(to: readingMode)
        }
        vc.syncTTSState()
    }
}

// MARK: - UIKit 核心容器
class ReaderContainerViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    var book: Book!; var chapters: [BookChapter] = []; var preferences: UserPreferences!; var ttsManager: TTSManager!
    var replaceRuleViewModel: ReplaceRuleViewModel?
    var onToggleMenu: (() -> Void)?; var onAddReplaceRuleWithText: ((String) -> Void)?; var onProgressChanged: ((Int, Double) -> Void)?; var onChaptersLoaded: (([BookChapter]) -> Void)?
    
    private(set) var currentChapterIndex: Int = 0
    private(set) var currentReadingMode: ReadingMode = .vertical
    private var rawContent: String = "" // 保存原始文本以供即时净化
    private var contentSentences: [String] = []
    private var renderStore: TextKit2RenderStore?
    private var currentCharOffset: Int = 0 
    
    // 多章节缓存系统 (The Swap System)
    private var nextChapterStore: TextKit2RenderStore?; private var prevChapterStore: TextKit2RenderStore?
    private var nextChapterPages: [PaginatedPage] = []; private var prevChapterPages: [PaginatedPage] = []

    private var verticalVC: VerticalTextViewController?; private var horizontalVC: UIPageViewController?; private var mangaVC: UIViewController?
    private var pages: [PaginatedPage] = []; private var currentPageIndex: Int = 0; private var isMangaMode = false

    override func viewDidLoad() {
        super.viewDidLoad()
        currentChapterIndex = book.durChapterIndex ?? 0
        currentReadingMode = preferences.readingMode
        loadChapters()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        verticalVC?.view.frame = view.bounds; horizontalVC?.view.frame = view.bounds; mangaVC?.view.frame = view.bounds
    }

    func updatePreferences(_ prefs: UserPreferences) {
        let fontSizeChanged = preferences.fontSize != prefs.fontSize
        let lineSpacingChanged = preferences.lineSpacing != prefs.lineSpacing
        self.preferences = prefs
        if (fontSizeChanged || lineSpacingChanged) && renderStore != nil && !isMangaMode {
            reRenderCurrentContent(maintainOffset: true)
        }
    }
    
    func updateReplaceRules(_ rules: [ReplaceRule]) {
        // 仅在规则真正变化时重绘（后续可加 hash 校验优化）
        if !rawContent.isEmpty {
            reRenderCurrentContent(maintainOffset: true)
        }
    }
    
    func jumpToChapter(_ index: Int) {
        guard index >= 0 && (chapters.isEmpty || index < chapters.count) else { return }
        currentChapterIndex = index
        loadChapterContent(at: index, resetOffset: true)
    }
    
    func switchReadingMode(to mode: ReadingMode) {
        captureCurrentProgress()
        currentReadingMode = mode
        setupReaderMode()
        applyCapturedProgress()
    }
    
    private func captureCurrentProgress() {
        if isMangaMode { return }
        if currentReadingMode == .vertical, let v = verticalVC { currentCharOffset = v.getCurrentCharOffset() }
        else if currentReadingMode == .horizontal { if currentPageIndex < pages.count { currentCharOffset = pages[currentPageIndex].globalRange.location } }
    }
    
    private func applyCapturedProgress() {
        if isMangaMode { return }
        if currentReadingMode == .vertical { verticalVC?.scrollToCharOffset(currentCharOffset, animated: false) }
        else if currentReadingMode == .horizontal {
            let targetPage = pages.firstIndex(where: { NSLocationInRange(currentCharOffset, $0.globalRange) }) ?? 0
            updateHorizontalPage(to: targetPage, animated: false)
        }
    }

    func syncTTSState() {
        guard !isMangaMode else { return }
        let hIndex = ttsManager.currentSentenceIndex
        if currentReadingMode == .vertical {
            verticalVC?.update(sentences: contentSentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, margin: preferences.pageHorizontalMargin, highlightIndex: hIndex, secondaryIndices: Set(ttsManager.preloadedIndices), isPlaying: ttsManager.isPlaying)
            if ttsManager.isPlaying { verticalVC?.ensureSentenceVisible(index: hIndex) }
        } else if currentReadingMode == .horizontal {
            if ttsManager.isPlaying { syncHorizontalPageToTTS(sentenceIndex: hIndex) }
        }
    }

    // MARK: - 数据加载与缓存管理
    private func loadChapters() {
        Task {
            do {
                let list = try await APIService.shared.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
                await MainActor.run { self.chapters = list; self.onChaptersLoaded?(list); loadChapterContent(at: currentChapterIndex) }
            } catch { print("加载目录失败") }
        }
    }
    
    private func loadChapterContent(at index: Int, resetOffset: Bool = false) {
        guard index >= 0 && index < chapters.count else { return }
        Task {
            do {
                let isM = book.type == 2 || preferences.manualMangaUrls.contains(book.bookUrl ?? "")
                let content = try await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index, contentType: isM ? 2 : 0)
                await MainActor.run {
                    self.rawContent = content
                    self.isMangaMode = isM
                    reRenderCurrentContent(maintainOffset: !resetOffset)
                    if resetOffset {
                        verticalVC?.scrollToTop(animated: false)
                        updateHorizontalPage(to: 0, animated: false)
                    }
                    prefetchAdjacentChapters(index: index)
                }
            } catch { print("加载内容失败") }
        }
    }
    
    private func reRenderCurrentContent(maintainOffset: Bool) {
        if maintainOffset { captureCurrentProgress() }
        
        let cleaned = removeHTMLAndSVG(rawContent)
        let processed = applyReplaceRules(to: cleaned)
        self.contentSentences = processed.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        if !isMangaMode {
            prepareRenderStore()
            if currentReadingMode == .horizontal { performPagination() }
        }
        
        setupReaderMode()
        if maintainOffset { applyCapturedProgress() }
    }
    
    private func applyReplaceRules(to text: String) -> String {
        guard let rules = replaceRuleViewModel?.rules, !rules.isEmpty else { return text }
        var result = text
        for rule in rules where rule.isEnabled == true {
            let pattern = rule.pattern
            let replacement = rule.replacement
            if rule.isRegex == true {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                    result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: replacement)
                }
            } else {
                result = result.replacingOccurrences(of: pattern, with: replacement)
            }
        }
        return result
    }

    private func prefetchAdjacentChapters(index: Int) {
        if index + 1 < chapters.count {
            Task {
                if let content = try? await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index + 1) {
                    await MainActor.run {
                        let cleaned = removeHTMLAndSVG(content)
                        let processed = applyReplaceRules(to: cleaned)
                        let sents = processed.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        let attr = createAttrString(processed)
                        self.nextChapterStore = TextKit2RenderStore(attributedString: attr, layoutWidth: view.bounds.width - preferences.pageHorizontalMargin * 2)
                        self.nextChapterPages = performSilentPagination(for: nextChapterStore!, sentences: sents)
                    }
                }
            }
        }
    }

    private func performSilentPagination(for store: TextKit2RenderStore, sentences: [String]) -> [PaginatedPage] {
        var pS: [Int] = []; var c = 0
        for s in sentences { pS.append(c); c += s.count + 1 }
        let res = TextKit2Paginator.paginate(renderStore: store, pageSize: view.bounds.size, paragraphStarts: pS, prefixLen: 0, contentInset: 20)
        return res.pageInfos.map { PaginatedPage(globalRange: $0.range, startSentenceIndex: $0.startSentenceIndex) }
    }

    private func createAttrString(_ text: String) -> NSAttributedString {
        return NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: preferences.fontSize), .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineSpacing = preferences.lineSpacing; p.alignment = .justified; return p }() ])
    }

    private func prepareRenderStore() {
        let fullText = contentSentences.joined(separator: "\n")
        let attrString = createAttrString(fullText)
        let width = max(100, view.bounds.width - preferences.pageHorizontalMargin * 2)
        if let store = renderStore { store.update(attributedString: attrString, layoutWidth: width) }
        else { renderStore = TextKit2RenderStore(attributedString: attrString, layoutWidth: width) }
    }
    
    private func performPagination() {
        guard let store = renderStore else { return }
        var starts: [Int] = []; var curr = 0; for s in contentSentences { starts.append(curr); curr += s.count + 1 }
        let result = TextKit2Paginator.paginate(renderStore: store, pageSize: view.bounds.size, paragraphStarts: starts, prefixLen: 0, contentInset: 20)
        self.pages = result.pageInfos.map { PaginatedPage(globalRange: $0.range, startSentenceIndex: $0.startSentenceIndex) }
    }

    // MARK: - 渲染器管理
    private func setupReaderMode() {
        verticalVC?.view.removeFromSuperview(); verticalVC?.removeFromParent(); verticalVC = nil
        horizontalVC?.view.removeFromSuperview(); horizontalVC?.removeFromParent(); horizontalVC = nil
        mangaVC?.view.removeFromSuperview(); mangaVC?.removeFromParent(); mangaVC = nil
        if isMangaMode { setupMangaMode() }
        else if currentReadingMode == .vertical { setupVerticalMode() }
        else { setupHorizontalMode() }
    }
    
    private func setupVerticalMode() {
        let v = VerticalTextViewController()
        v.onVisibleIndexChanged = { [weak self] idx in
            let pos = Double(idx) / Double(max(1, self?.contentSentences.count ?? 1))
            self?.onProgressChanged?(self?.currentChapterIndex ?? 0, pos)
        }
        v.onAddReplaceRule = { [weak self] text in self?.onAddReplaceRuleWithText?(text) }
        v.onTapMenu = { [weak self] in self?.onToggleMenu?() }
        addChild(v); view.addSubview(v.view); v.view.frame = view.bounds; v.didMove(toParent: self)
        v.update(sentences: contentSentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, margin: preferences.pageHorizontalMargin, highlightIndex: ttsManager.isPlaying ? ttsManager.currentSentenceIndex : nil, secondaryIndices: [], isPlaying: ttsManager.isPlaying)
        self.verticalVC = v
    }
    
    private func setupHorizontalMode() {
        let h = UIPageViewController(transitionStyle: preferences.pageTurningMode == .simulation ? .pageCurl : .scroll, navigationOrientation: .horizontal, options: nil)
        h.dataSource = self; h.delegate = self
        addChild(h); view.addSubview(h.view); h.view.frame = view.bounds; h.didMove(toParent: self); self.horizontalVC = h
        updateHorizontalPage(to: currentPageIndex, animated: false)
    }
    
    private func setupMangaMode() {
        let vc = UIViewController()
        let mangaView = MangaNativeReader(sentences: contentSentences, chapterUrl: chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].url : nil, showUIControls: .constant(false), currentVisibleIndex: .constant(0), pendingScrollIndex: .constant(nil))
        let host = UIHostingController(rootView: mangaView); addChild(host); vc.view.addSubview(host.view); host.view.frame = vc.view.bounds; host.didMove(toParent: vc)
        addChild(vc); view.addSubview(vc.view); vc.view.frame = view.bounds; vc.didMove(toParent: self); self.mangaVC = vc
    }

    // MARK: - UIPageViewController Logic (The Swap Core)
    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating f: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed, let visibleVC = pvc.viewControllers?.first as? PageContentViewController {
            if visibleVC.chapterOffset == 0 {
                // 本章内翻页
                self.currentPageIndex = visibleVC.pageIndex
                self.currentCharOffset = pages[visibleVC.pageIndex].globalRange.location
                self.onProgressChanged?(currentChapterIndex, Double(visibleVC.pageIndex) / Double(max(1, pages.count)))
            } else {
                // 跨章交换 (Memory Swap)
                if visibleVC.chapterOffset > 0 {
                    // 向前：Prev = Current, Current = Next
                    prevChapterStore = renderStore; prevChapterPages = pages
                    renderStore = nextChapterStore; pages = nextChapterPages
                    nextChapterStore = nil; nextChapterPages = []
                } else {
                    // 向后：Next = Current, Current = Prev
                    nextChapterStore = renderStore; nextChapterPages = pages
                    renderStore = prevChapterStore; pages = prevChapterPages
                    prevChapterStore = nil; prevChapterPages = []
                }
                
                self.currentChapterIndex += visibleVC.chapterOffset
                self.currentPageIndex = visibleVC.pageIndex
                self.currentCharOffset = pages[currentPageIndex].globalRange.location
                
                // 通知 SwiftUI 章节已变
                self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, pages.count)))
                
                // 异步补齐缺失的另一侧邻近章节
                prefetchAdjacentChapters(index: currentChapterIndex)
            }
        }
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        guard let current = vc as? PageContentViewController else { return nil }
        if current.chapterOffset == 0 {
            if current.pageIndex > 0 { return createPageVC(at: current.pageIndex - 1, offset: 0) }
            // 无缝回翻上一章最后一页
            if !prevChapterPages.isEmpty { return createPageVC(at: prevChapterPages.count - 1, offset: -1) }
        } else if current.chapterOffset == 1 {
            // 从下一章第一页往回翻
            return createPageVC(at: pages.count - 1, offset: 0)
        }
        return nil
    }
    
    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        guard let current = vc as? PageContentViewController else { return nil }
        if current.chapterOffset == 0 {
            if current.pageIndex < pages.count - 1 { return createPageVC(at: current.pageIndex + 1, offset: 0) }
            // 无缝进入下一章第一页
            if !nextChapterPages.isEmpty { return createPageVC(at: 0, offset: 1) } 
        } else if current.chapterOffset == -1 {
            // 从上一章最后一页往后翻
            return createPageVC(at: 0, offset: 0)
        }
        return nil
    }
    
    private func updateHorizontalPage(to index: Int, animated: Bool) {
        guard let h = horizontalVC, index >= 0 && index < pages.count else { return }
        currentPageIndex = index; h.setViewControllers([createPageVC(at: index, offset: 0)], direction: .forward, animated: animated)
    }
    
    private func createPageVC(at index: Int, offset: Int) -> PageContentViewController {
        let vc = PageContentViewController(pageIndex: index, chapterOffset: offset)
        let pageView = ReadContent2View(frame: .zero)
        let activeStore = (offset == 0) ? renderStore : (offset > 0 ? nextChapterStore : prevChapterStore)
        let activePages = (offset == 0) ? pages : (offset > 0 ? nextChapterPages : prevChapterPages)
        pageView.renderStore = activeStore
        if index < activePages.count {
            let p = activePages[index]
            pageView.pageInfo = TK2PageInfo(range: p.globalRange, yOffset: 0, pageHeight: view.bounds.height, actualContentHeight: view.bounds.height, startSentenceIndex: p.startSentenceIndex, contentInset: 20)
        }
        pageView.onTapLocation = { [weak self] loc in
            if loc == .middle { self?.onToggleMenu?() }
            else { self?.handlePageTap(isNext: loc == .right) }
        }
        vc.view.addSubview(pageView); pageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([pageView.topAnchor.constraint(equalTo: vc.view.topAnchor), pageView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor), pageView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor), pageView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor)])
        return vc
    }
    
    private func handlePageTap(isNext: Bool) {
        let target = isNext ? currentPageIndex + 1 : currentPageIndex - 1
        if target >= 0 && target < pages.count { updateHorizontalPage(to: target, animated: true) }
        else { jumpToChapter(isNext ? currentChapterIndex + 1 : currentChapterIndex - 1) }
    }

    private func syncHorizontalPageToTTS(sentenceIndex: Int) {
        var curr = 0; var pStarts: [Int] = []
        for s in contentSentences { pStarts.append(curr); curr += s.count + 1 }
        guard sentenceIndex < pStarts.count else { return }
        let offset = pStarts[sentenceIndex]
        if let target = pages.firstIndex(where: { NSLocationInRange(offset, $0.globalRange) }), target != currentPageIndex {
            updateHorizontalPage(to: target, animated: true)
        }
    }

    private func removeHTMLAndSVG(_ text: String) -> String {
        var res = text; let patterns = ["<svg[^>]*>.*?</svg>", "<img[^>]*>", "<[^>]+>"]
        for p in patterns { if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators]) { res = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: res.utf16.count), withTemplate: "") } }
        return res.replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

class PageContentViewController: UIViewController {
    let pageIndex: Int; let chapterOffset: Int
    init(pageIndex: Int, chapterOffset: Int) { self.pageIndex = pageIndex; self.chapterOffset = chapterOffset; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
}