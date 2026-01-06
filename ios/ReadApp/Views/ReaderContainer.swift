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
    @Binding var isMangaMode: Bool
    var onToggleMenu: () -> Void
    var onAddReplaceRule: (String) -> Void
    var onProgressChanged: (Int, Double) -> Void
    var readingMode: ReadingMode
    var safeAreaInsets: EdgeInsets 
    
    func makeUIViewController(context: Context) -> ReaderContainerViewController {
        let vc = ReaderContainerViewController()
        vc.book = book; vc.preferences = preferences; vc.ttsManager = ttsManager
        vc.replaceRuleViewModel = replaceRuleViewModel
        vc.onToggleMenu = onToggleMenu; vc.onAddReplaceRuleWithText = onAddReplaceRule
        vc.onProgressChanged = { idx, pos in if self.currentChapterIndex != idx { DispatchQueue.main.async { self.currentChapterIndex = idx } }; onProgressChanged(idx, pos) }
        vc.onChaptersLoaded = { list in DispatchQueue.main.async { self.chapters = list } }
        vc.onModeDetected = { isManga in DispatchQueue.main.async { self.isMangaMode = isManga } }
        return vc
    }
    
    func updateUIViewController(_ vc: ReaderContainerViewController, context: Context) {
        vc.safeAreaTop = safeAreaInsets.top; vc.safeAreaBottom = safeAreaInsets.bottom
        vc.updatePreferences(preferences); vc.updateReplaceRules(replaceRuleViewModel.rules)
        if !vc.isInternalTransitioning && vc.currentChapterIndex != currentChapterIndex { vc.jumpToChapter(currentChapterIndex) }
        if vc.currentReadingMode != readingMode { vc.switchReadingMode(to: readingMode) }
        vc.syncTTSState()
    }
}

class ReaderContainerViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIScrollViewDelegate {
    var book: Book!; var chapters: [BookChapter] = []; var preferences: UserPreferences!; var ttsManager: TTSManager!; var replaceRuleViewModel: ReplaceRuleViewModel?
    var onToggleMenu: (() -> Void)?; var onAddReplaceRuleWithText: ((String) -> Void)?; var onProgressChanged: ((Int, Double) -> Void)?; var onChaptersLoaded: (([BookChapter]) -> Void)?; var onModeDetected: ((Bool) -> Void)?
    var safeAreaTop: CGFloat = 0; var safeAreaBottom: CGFloat = 0
    
    private(set) var currentChapterIndex: Int = 0
    private(set) var currentReadingMode: ReadingMode = .vertical
    var isInternalTransitioning = false
    
    private var rawContent: String = ""; private var contentSentences: [String] = []
    private var renderStore: TextKit2RenderStore?; private var currentCharOffset: Int = 0 
    
    // 多章节缓存与分句缓存
    private var nextChapterStore: TextKit2RenderStore?; private var prevChapterStore: TextKit2RenderStore?
    private var nextChapterPages: [PaginatedPage] = []; private var prevChapterPages: [PaginatedPage] = []
    private var nextChapterPageInfos: [TK2PageInfo] = []; private var prevChapterPageInfos: [TK2PageInfo] = []
    private var nextChapterSentences: [String]?

    private var verticalVC: VerticalTextViewController?; private var horizontalVC: UIPageViewController?; private var mangaScrollView: UIScrollView?
    private var mangaStackView: UIStackView?
    private var pages: [PaginatedPage] = []; private var pageInfos: [TK2PageInfo] = []
    private var currentPageIndex: Int = 0; private var isMangaMode = false
    private let contentInset: CGFloat = 20; private let progressLabel = UILabel()
    private var loadToken: Int = 0; private var lastAppliedRulesSignature: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupProgressLabel(); currentChapterIndex = book.durChapterIndex ?? 0; currentReadingMode = preferences.readingMode; loadChapters()
    }
    private func setupProgressLabel() {
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular); progressLabel.textColor = .secondaryLabel; progressLabel.textAlignment = .right; view.addSubview(progressLabel); progressLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([progressLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), progressLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4)])
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); let b = view.bounds; verticalVC?.view.frame = b; horizontalVC?.view.frame = b; mangaScrollView?.frame = b }

    func updatePreferences(_ prefs: UserPreferences) {
        let oldP = self.preferences!; self.preferences = prefs
        if (oldP.fontSize != prefs.fontSize || oldP.lineSpacing != prefs.lineSpacing) && renderStore != nil && !isMangaMode { reRenderCurrentContent(maintainOffset: true) }
    }
    func updateReplaceRules(_ rules: [ReplaceRule]) {
        let signature = rules.map{"\($0.id ?? "")\($0.isEnabled ?? false)"}.joined()
        if signature == lastAppliedRulesSignature { return }; lastAppliedRulesSignature = signature
        if !rawContent.isEmpty && !isMangaMode { reRenderCurrentContent(maintainOffset: true) }
    }
    func jumpToChapter(_ index: Int) { currentChapterIndex = index; loadChapterContent(at: index, resetOffset: true) }
    func switchReadingMode(to mode: ReadingMode) { captureCurrentProgress(); currentReadingMode = mode; setupReaderMode(); applyCapturedProgress() }
    
    private func captureCurrentProgress() {
        if isMangaMode { return }; if currentReadingMode == .vertical, let v = verticalVC { currentCharOffset = v.getCurrentCharOffset() }
        else if currentReadingMode == .horizontal, currentPageIndex < pages.count { currentCharOffset = pages[currentPageIndex].globalRange.location }
    }
    private func applyCapturedProgress() {
        if isMangaMode { return }; if currentReadingMode == .vertical { verticalVC?.scrollToCharOffset(currentCharOffset, animated: false) }
        else if currentReadingMode == .horizontal { let target = pages.firstIndex(where: { NSLocationInRange(currentCharOffset, $0.globalRange) }) ?? 0; updateHorizontalPage(to: target, animated: false) }
    }
    func syncTTSState() {
        if isMangaMode { return }; let hI = ttsManager.currentSentenceIndex
        if currentReadingMode == .vertical { verticalVC?.update(sentences: contentSentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, margin: preferences.pageHorizontalMargin, highlightIndex: hI, secondaryIndices: Set(ttsManager.preloadedIndices), isPlaying: ttsManager.isPlaying); if ttsManager.isPlaying { verticalVC?.ensureSentenceVisible(index: hI) } }
        else if currentReadingMode == .horizontal && ttsManager.isPlaying { syncHorizontalPageToTTS(sentenceIndex: hI) }
    }

    private func loadChapters() {
        Task { do { let list = try await APIService.shared.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin); await MainActor.run { self.chapters = list; self.onChaptersLoaded?(list); loadChapterContent(at: currentChapterIndex) } } catch { print("Load chapters failed") } }
    }
    private func loadChapterContent(at index: Int, resetOffset: Bool = false) {
        guard index >= 0 && (chapters.isEmpty || index < chapters.count) else { return }
        loadToken += 1; let t = loadToken; Task { [weak self] in
            guard let self else { return }
            do {
                let isM = book.type == 2 || preferences.manualMangaUrls.contains(book.bookUrl ?? "")
                let content = try await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index, contentType: isM ? 2 : 0)
                await MainActor.run {
                    guard self.loadToken == t else { return }; self.rawContent = content; self.isMangaMode = isM; self.onModeDetected?(isM)
                    self.nextChapterStore = nil; self.nextChapterPages = []; self.nextChapterSentences = nil
                    self.reRenderCurrentContent(maintainOffset: !resetOffset)
                    if resetOffset { self.verticalVC?.scrollToTop(animated: false); self.updateHorizontalPage(to: 0, animated: false); self.mangaScrollView?.setContentOffset(.zero, animated: false) }
                    self.prefetchAdjacentChapters(index: index)
                }
            } catch { print("Content load failed") }
        }
    }
    private func reRenderCurrentContent(maintainOffset: Bool) {
        if maintainOffset { captureCurrentProgress() }
        let cleaned = removeHTMLAndSVG(rawContent); let processed = applyReplaceRules(to: cleaned); self.contentSentences = processed.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !isMangaMode { prepareRenderStore(); if currentReadingMode == .horizontal { performPagination() } }
        setupReaderMode(); if maintainOffset { applyCapturedProgress() }; updateProgressUI()
    }
    private func updateProgressUI() {
        if isMangaMode { progressLabel.text = ""; return }; let total = max(1, pages.count), current = min(total, currentPageIndex + 1); progressLabel.text = currentReadingMode == .horizontal ? "\(current)/\(total) (\(Int(Double(current)/Double(total)*100))%)" : ""
    }
    private func applyReplaceRules(to text: String) -> String {
        guard let rules = replaceRuleViewModel?.rules, !rules.isEmpty else { return text }; var res = text
        for r in rules where r.isEnabled == true { if r.isRegex == true { if let reg = try? NSRegularExpression(pattern: r.pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) { res = reg.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: res.utf16.count), withTemplate: r.replacement) } } else { res = res.replacingOccurrences(of: r.pattern, with: r.replacement) } }; return res
    }
    private func prefetchAdjacentChapters(index: Int) {
        if index + 1 < chapters.count { Task {
            if let content = try? await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index + 1) { await MainActor.run {
                let processed = applyReplaceRules(to: removeHTMLAndSVG(content)); let sents = processed.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                let title = self.chapters[index+1].title; let attr = self.createAttrString(processed, title: title)
                self.nextChapterStore = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, view.bounds.width - preferences.pageHorizontalMargin * 2))
                self.nextChapterSentences = sents
                if currentReadingMode == .vertical { self.verticalVC?.update(sentences: contentSentences, nextSentences: sents, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, margin: preferences.pageHorizontalMargin, highlightIndex: nil, secondaryIndices: [], isPlaying: false) }
                else { let res = self.performSilentPagination(for: self.nextChapterStore!, sentences: sents, title: title); self.nextChapterPages = res.pages; self.nextChapterPageInfos = res.pageInfos }
            }}
        }}
    }
    private func performSilentPagination(for store: TextKit2RenderStore, sentences: [String], title: String) -> TextKit2Paginator.PaginationResult {
        var pS: [Int] = []; var c = title.isEmpty ? 0 : (title + "\n").utf16.count; for s in sentences { pS.append(c); c += s.count + 1 }
        let pSize = CGSize(width: view.bounds.width, height: view.bounds.height - safeAreaTop - safeAreaBottom - 40)
        return TextKit2Paginator.paginate(renderStore: store, pageSize: pSize, paragraphStarts: pS, prefixLen: title.isEmpty ? 0 : (title + "\n").utf16.count, contentInset: 20 + safeAreaTop)
    }
    private func createAttrString(_ text: String, title: String) -> NSAttributedString {
        let fullAttr = NSMutableAttributedString()
        if !title.isEmpty { fullAttr.append(NSAttributedString(string: title + "\n", attributes: [.font: UIFont.systemFont(ofSize: preferences.fontSize + 8, weight: .bold), .foregroundColor: UIColor.label])) }
        fullAttr.append(NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: preferences.fontSize), .foregroundColor: UIColor.label, .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineSpacing = preferences.lineSpacing; p.alignment = .justified; return p }() ]))
        return fullAttr
    }
    private func prepareRenderStore() {
        let width = max(100, view.bounds.width - preferences.pageHorizontalMargin * 2); let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        let attr = createAttrString(contentSentences.joined(separator: "\n"), title: title)
        if let s = renderStore { s.update(attributedString: attr, layoutWidth: width) } else { renderStore = TextKit2RenderStore(attributedString: attr, layoutWidth: width) }
        renderStore?.textContainer.lineFragmentPadding = 8
    }
    private func performPagination() {
        guard let s = renderStore else { return }; let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        let pLen = title.isEmpty ? 0 : (title + "\n").utf16.count; var pS: [Int] = []; var c = pLen; for sent in contentSentences { pS.append(c); c += sent.count + 1 }
        let pSize = CGSize(width: view.bounds.width, height: view.bounds.height - safeAreaTop - safeAreaBottom - 40)
        let res = TextKit2Paginator.paginate(renderStore: s, pageSize: pSize, paragraphStarts: pS, prefixLen: pLen, contentInset: 20 + safeAreaTop)
        self.pages = res.pages; self.pageInfos = res.pageInfos
    }
    private func setupReaderMode() {
        verticalVC?.view.removeFromSuperview(); verticalVC?.removeFromParent(); verticalVC = nil; horizontalVC?.view.removeFromSuperview(); horizontalVC?.removeFromParent(); horizontalVC = nil; mangaScrollView?.removeFromSuperview(); mangaScrollView = nil
        if isMangaMode { setupMangaMode() } else if currentReadingMode == .vertical { setupVerticalMode() } else { setupHorizontalMode() }
    }
    private func setupVerticalMode() {
        let v = VerticalTextReader(sentences: contentSentences, fontSize: preferences.fontSize, lineSpacing: preferences.lineSpacing, horizontalMargin: preferences.pageHorizontalMargin, highlightIndex: ttsManager.isPlaying ? ttsManager.currentSentenceIndex : nil, secondaryIndices: [], isPlayingHighlight: ttsManager.isPlaying, chapterUrl: chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].url : nil, currentVisibleIndex: .constant(0), pendingScrollIndex: .constant(nil), safeAreaTop: safeAreaTop, nextChapterSentences: nextChapterSentences, onReachedBottom: { [weak self] in self?.prefetchAdjacentChapters(index: self?.currentChapterIndex ?? 0) }, onChapterSwitched: { [weak self] offset in if offset > 0 { self?.jumpToChapter((self?.currentChapterIndex ?? 0) + 1) } })
        let host = UIHostingController(rootView: v); addChild(host); view.addSubview(host.view); host.view.frame = view.bounds; host.didMove(toParent: self)
    }
    private func setupHorizontalMode() {
        let h = UIPageViewController(transitionStyle: preferences.pageTurningMode == .simulation ? .pageCurl : .scroll, navigationOrientation: .horizontal, options: nil); h.dataSource = self; h.delegate = self
        addChild(h); view.addSubview(h.view); h.view.frame = view.bounds; h.didMove(toParent: self); self.horizontalVC = h; updateHorizontalPage(to: currentPageIndex, animated: false)
    }
    private func setupMangaMode() {
        let sv = UIScrollView(frame: view.bounds); sv.backgroundColor = .black; sv.contentInsetAdjustmentBehavior = .never; sv.delegate = self; sv.minimumZoomScale = 1.0; sv.maximumZoomScale = 5.0
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 0; stack.alignment = .fill; stack.distribution = .fill; sv.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: sv.contentLayoutGuide.topAnchor, constant: safeAreaTop), stack.bottomAnchor.constraint(equalTo: sv.contentLayoutGuide.bottomAnchor), stack.leadingAnchor.constraint(equalTo: sv.contentLayoutGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: sv.contentLayoutGuide.trailingAnchor), stack.widthAnchor.constraint(equalTo: sv.frameLayoutGuide.widthAnchor), stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)])
        mangaStackView = stack; for sent in contentSentences where sent.contains("__IMG__") {
            let iv = UIImageView(); iv.contentMode = .scaleAspectFit; iv.clipsToBounds = true; stack.addArrangedSubview(iv)
            let url = sent.replacingOccurrences(of: "__IMG__", with: "").trimmingCharacters(in: .whitespaces)
            Task { if let u = URL(string: url), let (data, _) = try? await URLSession.shared.data(from: u), let img = UIImage(data: data) { await MainActor.run { iv.image = img; iv.heightAnchor.constraint(equalTo: iv.widthAnchor, multiplier: img.size.height / img.size.width).isActive = true } } }
        }
        view.addSubview(sv); self.mangaScrollView = sv; sv.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleMangaTap)))
    }
    @objc private func handleMangaTap() { onToggleMenu?() }; func viewForZooming(in scrollView: UIScrollView) -> UIView? { return mangaStackView }
    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating f: Bool, previousViewControllers p: [UIViewController], transitionCompleted completed: Bool) {
        if completed, let v = pvc.viewControllers?.first as? PageContentViewController {
            self.isInternalTransitioning = true; if v.chapterOffset == 0 { self.currentPageIndex = v.pageIndex; self.currentCharOffset = pages[v.pageIndex].globalRange.location; self.onProgressChanged?(currentChapterIndex, Double(v.pageIndex) / Double(max(1, pages.count))) }
            else { if v.chapterOffset > 0 { prevChapterStore = renderStore; prevChapterPages = pages; prevChapterPageInfos = pageInfos; renderStore = nextChapterStore; pages = nextChapterPages; pageInfos = nextChapterPageInfos; nextChapterStore = nil; nextChapterPages = []; nextChapterPageInfos = [] }
                else { nextChapterStore = renderStore; nextChapterPages = pages; nextChapterPageInfos = pageInfos; renderStore = prevChapterStore; pages = prevChapterPages; pageInfos = prevChapterPageInfos; prevChapterStore = nil; prevChapterPages = [] }; self.currentChapterIndex += v.chapterOffset; self.currentPageIndex = v.pageIndex; self.currentCharOffset = pages[currentPageIndex].globalRange.location; self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, pages.count))); prefetchAdjacentChapters(index: currentChapterIndex) }
            updateProgressUI(); self.isInternalTransitioning = false
        }
    }
    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? { guard let c = vc as? PageContentViewController else { return nil }; if c.chapterOffset == 0 { if c.pageIndex > 0 { return createPageVC(at: c.pageIndex - 1, offset: 0) }; if !prevChapterPages.isEmpty { return createPageVC(at: prevChapterPages.count - 1, offset: -1) } }; return nil }
    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? { guard let c = vc as? PageContentViewController else { return nil }; if c.chapterOffset == 0 { if c.pageIndex < pages.count - 1 { return createPageVC(at: c.pageIndex + 1, offset: 0) }; if !nextChapterPages.isEmpty { return createPageVC(at: 0, offset: 1) } }; return nil }
    private func updateHorizontalPage(to i: Int, animated: Bool) { guard let h = horizontalVC, i >= 0 && i < pages.count else { return }; currentPageIndex = i; h.setViewControllers([createPageVC(at: i, offset: 0)], direction: .forward, animated: animated); updateProgressUI() }
    private func createPageVC(at i: Int, offset: Int) -> PageContentViewController {
        let vc = PageContentViewController(pageIndex: i, chapterOffset: offset); let pV = ReadContent2View(frame: .zero); let aS = (offset == 0) ? renderStore : (offset > 0 ? nextChapterStore : prevChapterStore); let aP = (offset == 0) ? pages : (offset > 0 ? nextChapterPages : prevChapterPages); let aI = (offset == 0) ? pageInfos : (offset > 0 ? nextChapterPageInfos : prevChapterPageInfos)
        pV.renderStore = aS; if i < aI.count { var info = aI[i]; info.contentInset = safeAreaTop + 20; pV.pageInfo = info }; pV.onTapLocation = { [weak self] loc in if loc == .middle { self?.onToggleMenu?() } else { self?.handlePageTap(isNext: loc == .right) } }
        vc.view.addSubview(pV); pV.translatesAutoresizingMaskIntoConstraints = false; NSLayoutConstraint.activate([pV.topAnchor.constraint(equalTo: vc.view.topAnchor), pV.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor), pV.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor), pV.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor)]); return vc
    }
    private func handlePageTap(isNext: Bool) { let t = isNext ? currentPageIndex + 1 : currentPageIndex - 1; if t >= 0 && t < pages.count { updateHorizontalPage(to: t, animated: true) } else { jumpToChapter(isNext ? currentChapterIndex + 1 : currentChapterIndex - 1) } }
    private func syncHorizontalPageToTTS(sentenceIndex: Int) { var curr = 0; var pS: [Int] = []; for s in contentSentences { pS.append(curr); curr += s.count + 1 }; guard sentenceIndex < pS.count else { return }; let o = pS[sentenceIndex]; if let t = pages.firstIndex(where: { NSLocationInRange(o, $0.globalRange) }), t != currentPageIndex { updateHorizontalPage(to: t, animated: true) } }
    private func removeHTMLAndSVG(_ text: String) -> String { var res = text; let patterns = ["<svg[^>]*>.*?</svg>", "<img[^>]*>", "<[^>]+>"]; for p in patterns { if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators]) { res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: res.utf16.count), withTemplate: "") } }; return res.replacingOccurrences(of: "&nbsp;", with: " ") }
}
class PageContentViewController: UIViewController { let pageIndex: Int; let chapterOffset: Int; init(pageIndex: Int, chapterOffset: Int) { self.pageIndex = pageIndex; self.chapterOffset = chapterOffset; super.init(nibName: nil, bundle: nil) }; required init?(coder: NSCoder) { fatalError() } }