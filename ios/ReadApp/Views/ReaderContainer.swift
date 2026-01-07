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
    var readingMode: ReadingMode
    var safeAreaInsets: EdgeInsets 
    
    // MARK: - Coordinator 托管状态
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
        vc.onToggleMenu = onToggleMenu; vc.onAddReplaceRuleWithText = onAddReplaceRule
        
        // 挂载托管回调
        vc.onChapterIndexChanged = { idx in context.coordinator.handleChapterChange(idx) }
        vc.onProgressChanged = { idx, pos in context.coordinator.handleProgress(idx, pos) }
        vc.onChaptersLoaded = { list in context.coordinator.handleChaptersLoaded(list) }
        vc.onModeDetected = { isManga in context.coordinator.handleModeDetected(isManga) }
        
        return vc
    }
    
    func updateUIViewController(_ vc: ReaderContainerViewController, context: Context) {
        context.coordinator.parent = self // 刷新引用
        
        vc.updateLayout(safeArea: safeAreaInsets)
        vc.updatePreferences(preferences)
        vc.updateReplaceRules(replaceRuleViewModel.rules)
        
        if !vc.isInternalTransitioning && vc.currentChapterIndex != currentChapterIndex {
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
    private(set) var currentReadingMode: ReadingMode = .vertical
    var isInternalTransitioning = false
    
    private var rawContent: String = ""; private var contentSentences: [String] = []
    private var renderStore: TextKit2RenderStore?
    private var pages: [PaginatedPage] = []; private var pageInfos: [TK2PageInfo] = []
    private var currentPageIndex: Int = 0; private var isMangaMode = false
    
    private var nextChapterStore: TextKit2RenderStore?; private var prevChapterStore: TextKit2RenderStore?
    private var nextChapterPages: [PaginatedPage] = []; private var prevChapterPages: [PaginatedPage] = []
    private var nextChapterPageInfos: [TK2PageInfo] = []; private var prevChapterPageInfos: [TK2PageInfo] = []
    private var nextChapterSentences: [String]?; private var prevChapterSentences: [String]?
    private var nextChapterRawContent: String?; private var prevChapterRawContent: String?

    private var verticalVC: VerticalTextViewController?; private var horizontalVC: UIPageViewController?; private var mangaScrollView: UIScrollView?
    private let progressLabel = UILabel()
    private var lastLayoutSignature: String = ""
    private var loadToken: Int = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupProgressLabel(); currentChapterIndex = book.durChapterIndex ?? 0; currentReadingMode = preferences.readingMode; loadChapters()
    }
    
    private func setupProgressLabel() {
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular); progressLabel.textColor = .secondaryLabel
        view.addSubview(progressLabel); progressLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([progressLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), progressLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4)])
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isInternalTransitioning else { return }
        let b = view.bounds; verticalVC?.view.frame = b; horizontalVC?.view.frame = b; mangaScrollView?.frame = b
        
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
        if (oldP.fontSize != prefs.fontSize || oldP.lineSpacing != prefs.lineSpacing) && !isMangaMode { reRenderCurrentContent() }
    }
    func updateReplaceRules(_ rules: [ReplaceRule]) { if !rawContent.isEmpty && !isMangaMode { reRenderCurrentContent() } }
    
    func jumpToChapter(_ index: Int, startAtEnd: Bool = false) {
        currentChapterIndex = index; loadChapterContent(at: index, startAtEnd: startAtEnd)
    }
    func switchReadingMode(to mode: ReadingMode) { currentReadingMode = mode; setupReaderMode() }

    private func loadChapters() {
        Task { do {
            let list = try await APIService.shared.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
            await MainActor.run { self.chapters = list; self.onChaptersLoaded?(list); loadChapterContent(at: currentChapterIndex) }
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
                    if startAtEnd { self.scrollToChapterEnd(animated: false) }
                    else { self.updateHorizontalPage(to: 0, animated: false); self.verticalVC?.scrollToTop(animated: false) }
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
            self.contentSentences = processed.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            prepareRenderStore(); performPagination()
        }
        setupReaderMode(); updateProgressUI()
    }
    
    private func updateProgressUI() {
        if isMangaMode { progressLabel.text = ""; return }
        let total = max(1, pages.count); let current = min(total, currentPageIndex + 1)
        progressLabel.text = currentReadingMode == .horizontal ? "\(current)/\(total)" : ""
    }

    private func setupReaderMode() {
        verticalVC?.view.removeFromSuperview(); horizontalVC?.view.removeFromSuperview(); mangaScrollView?.removeFromSuperview()
        if isMangaMode { setupMangaMode() } else if currentReadingMode == .vertical { setupVerticalMode() } else { setupHorizontalMode() }
    }
    
    private func setupHorizontalMode() {
        let h = UIPageViewController(transitionStyle: preferences.pageTurningMode == .simulation ? .pageCurl : .scroll, navigationOrientation: .horizontal, options: nil)
        h.dataSource = self; h.delegate = self; addChild(h); view.insertSubview(h.view, at: 0); h.didMove(toParent: self)
        self.horizontalVC = h; updateHorizontalPage(to: currentPageIndex, animated: false)
    }
    
    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating f: Bool, previousViewControllers p: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let v = pvc.viewControllers?.first as? PageContentViewController else { return }
        
        if v.chapterOffset != 0 {
            self.isInternalTransitioning = true
            let offset = v.chapterOffset
            let pageIdx = v.pageIndex
            
            // 关键：异步执行状态置换，防止死锁
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.performAtomicChapterSwap(offset: offset, targetPage: pageIdx)
                self.isInternalTransitioning = false
            }
        } else {
            self.currentPageIndex = v.pageIndex
            self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, pages.count)))
            updateProgressUI()
        }
    }
    
    private func performAtomicChapterSwap(offset: Int, targetPage: Int) {
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
        self.currentPageIndex = targetPage
        self.onChapterIndexChanged?(self.currentChapterIndex)
        
        // 重新锚定视图
        let newCurrentVC = createPageVC(at: currentPageIndex, offset: 0)
        horizontalVC?.setViewControllers([newCurrentVC], direction: .forward, animated: false)
        
        updateProgressUI()
        self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, pages.count)))
        prefetchAdjacentChapters(index: currentChapterIndex)
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
        guard let h = horizontalVC, i >= 0 && i < pages.count else { return }
        currentPageIndex = i; h.setViewControllers([createPageVC(at: i, offset: 0)], direction: .forward, animated: animated)
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
        if t >= 0 && t < pages.count { updateHorizontalPage(to: t, animated: true) } 
        else { jumpToChapter(isNext ? currentChapterIndex + 1 : currentChapterIndex - 1, startAtEnd: !isNext) }
    }

    private func prefetchAdjacentChapters(index: Int) {
        if isMangaMode { return }
        if index + 1 < chapters.count {
            Task { if let content = try? await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index + 1, contentType: 0) {
                await MainActor.run {
                    let processed = self.applyReplaceRules(to: self.removeHTMLAndSVG(content)); let sents = processed.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    let title = self.chapters[index + 1].title; let attr = self.createAttrString(processed, title: title); let spec = self.currentLayoutSpec
                    self.nextChapterStore = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, spec.pageSize.width - spec.sideMargin * 2))
                    let res = self.performSilentPagination(for: self.nextChapterStore!, sentences: sents, title: title)
                    self.nextChapterPages = res.pages; self.nextChapterPageInfos = res.pageInfos; self.nextChapterSentences = sents; self.nextChapterRawContent = content
                }
            } }
        }
        if index - 1 >= 0 {
            Task { if let content = try? await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index - 1, contentType: 0) {
                await MainActor.run {
                    let processed = self.applyReplaceRules(to: self.removeHTMLAndSVG(content)); let sents = processed.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    let title = self.chapters[index - 1].title; let attr = self.createAttrString(processed, title: title); let spec = self.currentLayoutSpec
                    self.prevChapterStore = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, spec.pageSize.width - spec.sideMargin * 2))
                    let res = self.performSilentPagination(for: self.prevChapterStore!, sentences: sents, title: title)
                    self.prevChapterPages = res.pages; self.prevChapterPageInfos = res.pageInfos; self.prevChapterSentences = sents; self.prevChapterRawContent = content
                }
            } }
        }
    }

    private func performSilentPagination(for store: TextKit2RenderStore, sentences: [String], title: String) -> TextKit2Paginator.PaginationResult {
        let spec = currentLayoutSpec; var pS: [Int] = []; var c = title.isEmpty ? 0 : (title + "\n").utf16.count; for s in sentences { pS.append(c); c += s.count + 1 }
        return TextKit2Paginator.paginate(renderStore: store, pageSize: spec.pageSize, paragraphStarts: pS, prefixLen: title.isEmpty ? 0 : (title + "\n").utf16.count, topInset: spec.topInset, bottomInset: spec.bottomInset)
    }

    private func createAttrString(_ text: String, title: String) -> NSAttributedString {
        let fullAttr = NSMutableAttributedString()
        if !title.isEmpty { fullAttr.append(NSAttributedString(string: title + "\n", attributes: [.font: UIFont.systemFont(ofSize: preferences.fontSize + 8, weight: .bold), .foregroundColor: UIColor.label])) }
        fullAttr.append(NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: preferences.fontSize), .foregroundColor: UIColor.label, .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineSpacing = preferences.lineSpacing; p.alignment = .justified; return p }() ]))
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
        var starts: [Int] = []; var curr = pLen; for sent in contentSentences { starts.append(curr); curr += sent.count + 1 }
        let res = TextKit2Paginator.paginate(renderStore: s, pageSize: spec.pageSize, paragraphStarts: starts, prefixLen: pLen, topInset: spec.topInset, bottomInset: spec.bottomInset)
        self.pages = res.pages; self.pageInfos = res.pageInfos
    }

    private func setupVerticalMode() {
        let v = VerticalTextViewController(); v.onVisibleIndexChanged = { [weak self] idx in self?.onProgressChanged?(self?.currentChapterIndex ?? 0, Double(idx) / Double(max(1, self?.contentSentences.count ?? 1))) }
        v.onAddReplaceRule = { [weak self] text in self?.onAddReplaceRuleWithText?(text) }; v.onTapMenu = { [weak self] in self?.onToggleMenu?() }
        v.onChapterSwitched = { [weak self] _ in self?.jumpToChapter((self?.currentChapterIndex ?? 0) + 1) }
        addChild(v); view.insertSubview(v.view, at: 0); v.view.frame = view.bounds; v.didMove(toParent: self); v.safeAreaTop = safeAreaTop
        v.update(sentences: contentSentences, nextSentences: nextChapterSentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, margin: preferences.pageHorizontalMargin, highlightIndex: ttsManager.isPlaying ? ttsManager.currentSentenceIndex : nil, secondaryIndices: [], isPlaying: ttsManager.isPlaying)
        self.verticalVC = v
    }
    
    private func setupMangaMode() {
        let sv = UIScrollView(frame: view.bounds); sv.backgroundColor = .black; sv.contentInsetAdjustmentBehavior = .never; sv.delegate = self
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 0; stack.alignment = .fill; sv.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: sv.contentLayoutGuide.topAnchor, constant: safeAreaTop), stack.bottomAnchor.constraint(equalTo: sv.contentLayoutGuide.bottomAnchor), stack.leadingAnchor.constraint(equalTo: sv.contentLayoutGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: sv.contentLayoutGuide.trailingAnchor), stack.widthAnchor.constraint(equalTo: sv.frameLayoutGuide.widthAnchor)])
        for sent in contentSentences.filter({ $0.contains("__IMG__") }) {
            let iv = UIImageView(); iv.contentMode = .scaleAspectFit; iv.clipsToBounds = true; stack.addArrangedSubview(iv)
            let url = sent.replacingOccurrences(of: "__IMG__", with: "").trimmingCharacters(in: .whitespaces)
            Task { if let u = URL(string: url), let (data, _) = try? await URLSession.shared.data(from: u), let img = UIImage(data: data) { await MainActor.run { iv.image = img; iv.heightAnchor.constraint(equalTo: iv.widthAnchor, multiplier: img.size.height / img.size.width).isActive = true } } }
        }
        view.insertSubview(sv, at: 0); self.mangaScrollView = sv; sv.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleMangaTap)))
    }
    @objc private func handleMangaTap() { onToggleMenu?() }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { return nil }
    func syncTTSState() {
        if isMangaMode { return }; let hIndex = ttsManager.currentSentenceIndex
        if currentReadingMode == .vertical { verticalVC?.update(sentences: contentSentences, nextSentences: nextChapterSentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, margin: preferences.pageHorizontalMargin, highlightIndex: hIndex, secondaryIndices: Set(ttsManager.preloadedIndices), isPlaying: ttsManager.isPlaying) }
        else if currentReadingMode == .horizontal && ttsManager.isPlaying { syncHorizontalPageToTTS(sentenceIndex: hIndex) }
    }
    private func syncHorizontalPageToTTS(sentenceIndex: Int) { 
        var curr = 0; var pS: [Int] = []; for s in contentSentences { pS.append(curr); curr += s.count + 1 }; guard sentenceIndex < pS.count else { return }
        let o = pS[sentenceIndex]; if let t = pages.firstIndex(where: { NSLocationInRange(o, $0.globalRange) }), t != currentPageIndex { updateHorizontalPage(to: t, animated: true) }
    }
    private func scrollToChapterEnd(animated: Bool) { if isMangaMode, let sv = mangaScrollView { sv.setContentOffset(CGPoint(x: 0, y: max(0, sv.contentSize.height - sv.bounds.height)), animated: animated) } else if currentReadingMode == .vertical { verticalVC?.scrollToBottom(animated: animated) } else if !pages.isEmpty { updateHorizontalPage(to: max(0, pages.count - 1), animated: animated) } }
    private func applyReplaceRules(to text: String) -> String { guard let rules = replaceRuleViewModel?.rules else { return text }; var res = text; for r in rules where r.isEnabled == true { if r.isRegex == true { if let reg = try? NSRegularExpression(pattern: r.pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) { res = reg.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: res.utf16.count), withTemplate: r.replacement) } } else { res = res.replacingOccurrences(of: r.pattern, with: r.replacement) } }; return res }
    private func removeHTMLAndSVG(_ text: String) -> String { var res = text; let patterns = ["<svg[^>]*>.*?</svg>", "<img[^>]*>", "<[^>]+>"]; for p in patterns { if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators]) { res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: res.utf16.count), withTemplate: "") } }; return res.replacingOccurrences(of: "&nbsp;", with: " ") }
    private func extractMangaImageSentences(from text: String) -> [String] { let pattern = #"<img[^>]+(?:src|data-src|data-original)=["']([^"']+)["'][^>]*>"#; guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }; let nsText = text as NSString; let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)); return matches.compactMap { match in guard match.numberOfRanges > 1 else { return nil }; return "__IMG__" + nsText.substring(with: match.range(at: 1)) } }
}
class PageContentViewController: UIViewController { var pageIndex: Int; var chapterOffset: Int; init(pageIndex: Int, chapterOffset: Int) { self.pageIndex = pageIndex; self.chapterOffset = chapterOffset; super.init(nibName: nil, bundle: nil) }; required init?(coder: NSCoder) { fatalError() } }