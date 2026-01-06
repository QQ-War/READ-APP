import SwiftUI
import UIKit
import Combine

// MARK: - SwiftUI 桥接入口
struct ReaderContainerRepresentable: UIViewControllerRepresentable {
    let book: Book
    @ObservedObject var preferences: UserPreferences
    @ObservedObject var ttsManager: TTSManager
    @ObservedObject var replaceRuleViewModel: ReplaceRuleViewModel
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
            if self.currentChapterIndex != idx { DispatchQueue.main.async { self.currentChapterIndex = idx } }
            onProgressChanged(idx, pos)
        }
        vc.onChaptersLoaded = { list in DispatchQueue.main.async { self.chapters = list } }
        return vc
    }
    
    func updateUIViewController(_ vc: ReaderContainerViewController, context: Context) {
        vc.updatePreferences(preferences)
        vc.updateReplaceRules(replaceRuleViewModel.rules)
        // 关键：仅在非内部切换时才响应外部章节变化，防止颤动
        if !vc.isInternalTransitioning && vc.currentChapterIndex != currentChapterIndex {
            vc.jumpToChapter(currentChapterIndex)
        }
        if vc.currentReadingMode != readingMode { vc.switchReadingMode(to: readingMode) }
        vc.syncTTSState()
    }
}

// MARK: - UIKit 核心容器
class ReaderContainerViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    var book: Book!; var chapters: [BookChapter] = []; var preferences: UserPreferences!; var ttsManager: TTSManager!; var replaceRuleViewModel: ReplaceRuleViewModel?
    var onToggleMenu: (() -> Void)?; var onAddReplaceRuleWithText: ((String) -> Void)?; var onProgressChanged: ((Int, Double) -> Void)?; var onChaptersLoaded: (([BookChapter]) -> Void)?
    
    private(set) var currentChapterIndex: Int = 0
    private(set) var currentReadingMode: ReadingMode = .vertical
    var isInternalTransitioning = false // 防止颤动的锁
    
    private var rawContent: String = ""; private var contentSentences: [String] = []
    private var renderStore: TextKit2RenderStore?; private var currentCharOffset: Int = 0 
    
    private var nextChapterStore: TextKit2RenderStore?; private var prevChapterStore: TextKit2RenderStore?
    private var nextChapterPages: [PaginatedPage] = []; private var prevChapterPages: [PaginatedPage] = []

    private var verticalVC: VerticalTextViewController?; private var horizontalVC: UIPageViewController?; private var mangaScrollView: UIScrollView?
    private var pages: [PaginatedPage] = []; private var currentPageIndex: Int = 0; private var isMangaMode = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        currentChapterIndex = book.durChapterIndex ?? 0
        currentReadingMode = preferences.readingMode
        loadChapters()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        verticalVC?.view.frame = b; horizontalVC?.view.frame = b; mangaScrollView?.frame = b
    }

    func updatePreferences(_ prefs: UserPreferences) {
        let oldP = self.preferences!
        self.preferences = prefs
        if (oldP.fontSize != prefs.fontSize || oldP.lineSpacing != prefs.lineSpacing) && renderStore != nil && !isMangaMode {
            reRenderCurrentContent(maintainOffset: true)
        }
    }
    
    func updateReplaceRules(_ rules: [ReplaceRule]) {
        if !rawContent.isEmpty && !isMangaMode { reRenderCurrentContent(maintainOffset: true) }
    }
    
    func jumpToChapter(_ index: Int) {
        guard index >= 0 && (chapters.isEmpty || index < chapters.count) else { return }
        currentChapterIndex = index
        loadChapterContent(at: index, resetOffset: true)
    }
    
    func switchReadingMode(to mode: ReadingMode) {
        captureCurrentProgress(); currentReadingMode = mode; setupReaderMode(); applyCapturedProgress()
    }
    
    private func captureCurrentProgress() {
        if isMangaMode { return }
        if currentReadingMode == .vertical, let v = verticalVC { currentCharOffset = v.getCurrentCharOffset() }
        else if currentReadingMode == .horizontal, currentPageIndex < pages.count { currentCharOffset = pages[currentPageIndex].globalRange.location }
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
        if isMangaMode { return }
        let hIndex = ttsManager.currentSentenceIndex
        if currentReadingMode == .vertical {
            verticalVC?.update(sentences: contentSentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, margin: preferences.pageHorizontalMargin, highlightIndex: hIndex, secondaryIndices: Set(ttsManager.preloadedIndices), isPlaying: ttsManager.isPlaying)
            if ttsManager.isPlaying { verticalVC?.ensureSentenceVisible(index: hIndex) }
        } else if currentReadingMode == .horizontal && ttsManager.isPlaying {
            syncHorizontalPageToTTS(sentenceIndex: hIndex)
        }
    }

    private func loadChapters() {
        Task {
            do {
                let list = try await APIService.shared.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
                await MainActor.run { self.chapters = list; self.onChaptersLoaded?(list); loadChapterContent(at: currentChapterIndex) }
            } catch { print("Chapters load failed") }
        }
    }
    
    private func loadChapterContent(at index: Int, resetOffset: Bool = false) {
        guard index >= 0 && (chapters.isEmpty || index < chapters.count) else { return }
        Task {
            do {
                let isM = book.type == 2 || preferences.manualMangaUrls.contains(book.bookUrl ?? "")
                let content = try await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index, contentType: isM ? 2 : 0)
                await MainActor.run {
                    self.rawContent = content; self.isMangaMode = isM
                    reRenderCurrentContent(maintainOffset: !resetOffset)
                    if resetOffset {
                        verticalVC?.scrollToTop(animated: false)
                        updateHorizontalPage(to: 0, animated: false)
                        mangaScrollView?.setContentOffset(.zero, animated: false)
                    }
                    prefetchAdjacentChapters(index: index)
                }
            } catch { print("Content load failed") }
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
        var res = text
        for r in rules where r.isEnabled == true {
            if r.isRegex == true { if let reg = try? NSRegularExpression(pattern: r.pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) { res = reg.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: res.utf16.count), withTemplate: r.replacement) } } 
            else { res = res.replacingOccurrences(of: r.pattern, with: r.replacement) }
        }
        return res
    }

    private func prefetchAdjacentChapters(index: Int) {
        if index + 1 < chapters.count {
            Task {
                if let content = try? await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index + 1) {
                    await MainActor.run {
                        let processed = applyReplaceRules(to: removeHTMLAndSVG(content))
                        let sents = processed.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        let attr = createAttrString(processed)
                        self.nextChapterStore = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, view.bounds.width - preferences.pageHorizontalMargin * 2))
                        self.nextChapterPages = performSilentPagination(for: nextChapterStore!, sentences: sents)
                    }
                }
            }
        }
    }

    private func performSilentPagination(for store: TextKit2RenderStore, sentences: [String]) -> [PaginatedPage] {
        var pS: [Int] = []; var c = 0; for s in sentences { pS.append(c); c += s.count + 1 }
        let res = TextKit2Paginator.paginate(renderStore: store, pageSize: view.bounds.size, paragraphStarts: pS, prefixLen: 0, contentInset: 20)
        return res.pageInfos.map { PaginatedPage(globalRange: $0.range, startSentenceIndex: $0.startSentenceIndex) }
    }

    private func createAttrString(_ text: String) -> NSAttributedString {
        return NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: preferences.fontSize), .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineSpacing = preferences.lineSpacing; p.alignment = .justified; return p }() ])
    }

    private func prepareRenderStore() {
        let width = max(100, view.bounds.width - preferences.pageHorizontalMargin * 2)
        let attr = createAttrString(contentSentences.joined(separator: "\n"))
        if let s = renderStore { s.update(attributedString: attr, layoutWidth: width) }
        else { renderStore = TextKit2RenderStore(attributedString: attr, layoutWidth: width) }
    }
    
    private func performPagination() {
        guard let s = renderStore else { return }
        var starts: [Int] = []; var curr = 0; for sent in contentSentences { starts.append(curr); curr += sent.count + 1 }
        let res = TextKit2Paginator.paginate(renderStore: s, pageSize: view.bounds.size, paragraphStarts: starts, prefixLen: 0, contentInset: 20)
        self.pages = res.pageInfos.map { PaginatedPage(globalRange: $0.range, startSentenceIndex: $0.startSentenceIndex) }
    }

    private func setupReaderMode() {
        verticalVC?.view.removeFromSuperview(); verticalVC?.removeFromParent(); verticalVC = nil
        horizontalVC?.view.removeFromSuperview(); horizontalVC?.removeFromParent(); horizontalVC = nil
        mangaScrollView?.removeFromSuperview(); mangaScrollView = nil
        
        if isMangaMode { setupMangaMode() }
        else if currentReadingMode == .vertical { setupVerticalMode() }
        else { setupHorizontalMode() }
    }
    
    private func setupVerticalMode() {
        let v = VerticalTextViewController(); v.onVisibleIndexChanged = { [weak self] idx in
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
        let sv = UIScrollView(frame: view.bounds)
        sv.backgroundColor = .black
        let stack = UIStackView()
        stack.axis = .vertical; stack.spacing = 0; stack.alignment = .fill; stack.distribution = .fill
        sv.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: sv.contentLayoutGuide.topAnchor), stack.bottomAnchor.constraint(equalTo: sv.contentLayoutGuide.bottomAnchor), stack.leadingAnchor.constraint(equalTo: sv.contentLayoutGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: sv.contentLayoutGuide.trailingAnchor), stack.widthAnchor.constraint(equalTo: sv.frameLayoutGuide.widthAnchor)])
        
        for sent in contentSentences where sent.contains("__IMG__") {
            let url = sent.replacingOccurrences(of: "__IMG__", with: "").trimmingCharacters(in: .whitespaces)
            let iv = UIImageView(); iv.contentMode = .scaleAspectFit; iv.clipsToBounds = true
            stack.addArrangedSubview(iv)
            Task { if let u = URL(string: url), let (data, _) = try? await URLSession.shared.data(from: u), let img = UIImage(data: data) {
                await MainActor.run { iv.image = img; iv.heightAnchor.constraint(equalTo: iv.widthAnchor, multiplier: img.size.height / img.size.width).isActive = true }
            }}
        }
        view.addSubview(sv); self.mangaScrollView = sv
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleMangaTap)); sv.addGestureRecognizer(tap)
    }
    @objc private func handleMangaTap() { onToggleMenu?() }

    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating f: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed, let visibleVC = pvc.viewControllers?.first as? PageContentViewController {
            self.isInternalTransitioning = true // 锁定
            if visibleVC.chapterOffset == 0 {
                self.currentPageIndex = visibleVC.pageIndex; self.currentCharOffset = pages[visibleVC.pageIndex].globalRange.location
                self.onProgressChanged?(currentChapterIndex, Double(visibleVC.pageIndex) / Double(max(1, pages.count)))
            } else {
                if visibleVC.chapterOffset > 0 { prevChapterStore = renderStore; prevChapterPages = pages; renderStore = nextChapterStore; pages = nextChapterPages; nextChapterStore = nil; nextChapterPages = [] } 
                else { nextChapterStore = renderStore; nextChapterPages = pages; renderStore = prevChapterStore; pages = prevChapterPages; prevChapterStore = nil; prevChapterPages = [] }
                self.currentChapterIndex += visibleVC.chapterOffset; self.currentPageIndex = visibleVC.pageIndex; self.currentCharOffset = pages[currentPageIndex].globalRange.location
                self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, pages.count)))
                prefetchAdjacentChapters(index: currentChapterIndex)
            }
            self.isInternalTransitioning = false // 释放
        }
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        guard let current = vc as? PageContentViewController else { return nil }
        if current.chapterOffset == 0 {
            if current.pageIndex > 0 { return createPageVC(at: current.pageIndex - 1, offset: 0) }
            if !prevChapterPages.isEmpty { return createPageVC(at: prevChapterPages.count - 1, offset: -1) }
        } else if current.chapterOffset == 1 { return createPageVC(at: pages.count - 1, offset: 0) }
        return nil
    }
    
    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        guard let current = vc as? PageContentViewController else { return nil }
        if current.chapterOffset == 0 {
            if current.pageIndex < pages.count - 1 { return createPageVC(at: current.pageIndex + 1, offset: 0) }
            if !nextChapterPages.isEmpty { return createPageVC(at: 0, offset: 1) } 
        } else if current.chapterOffset == -1 { return createPageVC(at: 0, offset: 0) }
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
        for p in patterns { if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators]) { res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: res.utf16.count), withTemplate: "") } }
        return res.replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

class PageContentViewController: UIViewController {
    let pageIndex: Int; let chapterOffset: Int
    init(pageIndex: Int, chapterOffset: Int) { self.pageIndex = pageIndex; self.chapterOffset = chapterOffset; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
}