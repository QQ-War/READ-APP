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
    var safeAreaInsets: EdgeInsets // 传入的安全区
    
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
        vc.safeAreaTop = safeAreaInsets.top
        vc.safeAreaBottom = safeAreaInsets.bottom
        return vc
    }
    
    func updateUIViewController(_ vc: ReaderContainerViewController, context: Context) {
        vc.safeAreaTop = safeAreaInsets.top
        vc.safeAreaBottom = safeAreaInsets.bottom
        vc.updatePreferences(preferences)
        vc.updateReplaceRules(replaceRuleViewModel.rules)
        if !vc.isInternalTransitioning && vc.currentChapterIndex != currentChapterIndex {
            vc.jumpToChapter(currentChapterIndex)
        }
        if vc.currentReadingMode != readingMode { vc.switchReadingMode(to: readingMode) }
        vc.syncTTSState()
    }
}

class ReaderContainerViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    var book: Book!; var chapters: [BookChapter] = []; var preferences: UserPreferences!; var ttsManager: TTSManager!; var replaceRuleViewModel: ReplaceRuleViewModel?
    var onToggleMenu: (() -> Void)?; var onAddReplaceRuleWithText: ((String) -> Void)?; var onProgressChanged: ((Int, Double) -> Void)?; var onChaptersLoaded: (([BookChapter]) -> Void)?
    var safeAreaTop: CGFloat = 0; var safeAreaBottom: CGFloat = 0
    
    private(set) var currentChapterIndex: Int = 0
    private(set) var currentReadingMode: ReadingMode = .vertical
    var isInternalTransitioning = false
    
    private var rawContent: String = ""; private var contentSentences: [String] = []
    private var renderStore: TextKit2RenderStore?; private var currentCharOffset: Int = 0 
    
    private var nextChapterStore: TextKit2RenderStore?; private var prevChapterStore: TextKit2RenderStore?
    private var nextChapterPages: [PaginatedPage] = []; private var prevChapterPages: [PaginatedPage] = []
    private var nextChapterPageInfos: [TK2PageInfo] = []; private var prevChapterPageInfos: [TK2PageInfo] = []

    private var verticalVC: VerticalTextViewController?; private var horizontalVC: UIPageViewController?; private var mangaScrollView: UIScrollView?
    private var mangaStackView: UIStackView?
    private var pages: [PaginatedPage] = []; private var pageInfos: [TK2PageInfo] = []
    private var currentPageIndex: Int = 0; private var isMangaMode = false
    private let contentInset: CGFloat = 20
    private let progressLabel = UILabel()
    private var pendingTargetPageIndex: Int?
    private var pendingTargetDirection: UIPageViewController.NavigationDirection?
    
    private var currentLoadTask: Task<Void, Never>?; private var prefetchNextTask: Task<Void, Never>?; private var prefetchPrevTask: Task<Void, Never>?
    private var loadToken: Int = 0; private var lastRenderedMode: ReadingMode?; private var lastRenderedIsManga: Bool?; private var lastAppliedRulesSignature: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupProgressLabel(); currentChapterIndex = book.durChapterIndex ?? 0; currentReadingMode = preferences.readingMode; loadChapters()
    }
    
    private func setupProgressLabel() {
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular); progressLabel.textColor = .secondaryLabel; progressLabel.textAlignment = .right
        view.addSubview(progressLabel); progressLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([progressLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), progressLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4)])
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds; verticalVC?.view.frame = b; horizontalVC?.view.frame = b; mangaScrollView?.frame = b
    }

    func updatePreferences(_ prefs: UserPreferences) {
        let oldP = self.preferences!; self.preferences = prefs
        if (oldP.fontSize != prefs.fontSize || oldP.lineSpacing != prefs.lineSpacing) && renderStore != nil && !isMangaMode { reRenderCurrentContent(maintainOffset: true) }
    }
    
    func updateReplaceRules(_ rules: [ReplaceRule]) {
        let signature = rulesSignature(rules)
        if signature == lastAppliedRulesSignature { return }
        lastAppliedRulesSignature = signature
        if !rawContent.isEmpty && !isMangaMode { reRenderCurrentContent(maintainOffset: true) }
    }
    
    func jumpToChapter(_ index: Int, startAtEnd: Bool = false) {
        currentChapterIndex = index
        if startAtEnd {
            pendingTargetPageIndex = -1
            pendingTargetDirection = .reverse
        } else {
            pendingTargetPageIndex = 0
            pendingTargetDirection = .forward
        }
        loadChapterContent(at: index, resetOffset: true)
    }
    func switchReadingMode(to mode: ReadingMode) { captureCurrentProgress(); currentReadingMode = mode; setupReaderMode(); applyCapturedProgress() }
    
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
        } else if currentReadingMode == .horizontal && ttsManager.isPlaying { syncHorizontalPageToTTS(sentenceIndex: hIndex) }
    }

    private func loadChapters() {
        Task { do {
            let list = try await APIService.shared.fetchChapterList(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin)
            await MainActor.run { self.chapters = list; self.onChaptersLoaded?(list); loadChapterContent(at: currentChapterIndex) }
        } catch { print("Load chapters failed") } }
    }
    
    private func loadChapterContent(at index: Int, resetOffset: Bool = false) {
        guard index >= 0 && (chapters.isEmpty || index < chapters.count) else { return }
        loadToken += 1; let token = loadToken; currentLoadTask?.cancel()
        currentLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let isM = book.type == 2 || preferences.manualMangaUrls.contains(book.bookUrl ?? "")
                let content = try await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index, contentType: isM ? 2 : 0)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.loadToken == token else { return }
                    self.rawContent = content; self.isMangaMode = isM
                    self.reRenderCurrentContent(maintainOffset: !resetOffset)
                    if resetOffset {
                        self.verticalVC?.scrollToTop(animated: false)
                        if self.pendingTargetPageIndex == nil {
                            self.updateHorizontalPage(to: 0, animated: false)
                        }
                        self.mangaScrollView?.setContentOffset(.zero, animated: false)
                    }
                    self.prefetchAdjacentChapters(index: index)
                }
            } catch { print("Content load failed") }
        }
    }
    
    private func reRenderCurrentContent(maintainOffset: Bool) {
        if maintainOffset { captureCurrentProgress() }
        let cleaned = removeHTMLAndSVG(rawContent)
        let processed = applyReplaceRules(to: cleaned)
        if isMangaMode {
            let images = extractMangaImageSentences(from: rawContent)
            if !images.isEmpty {
                self.contentSentences = images
            } else {
                self.contentSentences = processed.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
        } else {
            self.contentSentences = processed.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        if !isMangaMode { prepareRenderStore(); if currentReadingMode == .horizontal { performPagination() } }
        setupReaderMode()
        if maintainOffset { applyCapturedProgress() }
        if currentReadingMode == .horizontal, let pendingIndex = pendingTargetPageIndex {
            let target = pendingIndex == -1 ? max(0, pages.count - 1) : min(pendingIndex, max(0, pages.count - 1))
            updateHorizontalPage(to: target, animated: false, direction: pendingTargetDirection)
            pendingTargetPageIndex = nil
            pendingTargetDirection = nil
        } else if currentReadingMode != .horizontal {
            pendingTargetPageIndex = nil
            pendingTargetDirection = nil
        }
        updateProgressUI()
    }
    
    private func updateProgressUI() {
        if isMangaMode { progressLabel.text = ""; return }
        let total = max(1, pages.count); let current = min(total, currentPageIndex + 1)
        progressLabel.text = currentReadingMode == .horizontal ? "\(current)/\(total) (\(Int(Double(current)/Double(total)*100))%)" : ""
    }
    
    private func applyReplaceRules(to text: String) -> String {
        guard let rules = replaceRuleViewModel?.rules, !rules.isEmpty else { return text }
        var res = text
        for r in rules where r.isEnabled == true { if r.isRegex == true { if let reg = try? NSRegularExpression(pattern: r.pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) { res = reg.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: res.utf16.count), withTemplate: r.replacement) } } else { res = res.replacingOccurrences(of: r.pattern, with: r.replacement) } }
        return res
    }

    private func prefetchAdjacentChapters(index: Int) {
        prefetchNextTask?.cancel()
        prefetchPrevTask?.cancel()
        let baseIndex = index
        if index + 1 < chapters.count {
            prefetchNextTask = Task { [weak self] in
                guard let self else { return }
                if let content = try? await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index + 1) {
                    await MainActor.run {
                        guard self.currentChapterIndex == baseIndex else { return }
                        let processed = applyReplaceRules(to: removeHTMLAndSVG(content))
                        let title = self.chapters[index + 1].title
                        let attr = self.createAttrString(processed, title: title)
                        self.nextChapterStore = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, view.bounds.width - preferences.pageHorizontalMargin * 2))
                        let res = self.performSilentPagination(for: self.nextChapterStore!, sentences: processed.components(separatedBy: "\n"), title: title)
                        self.nextChapterPages = res.pages
                        self.nextChapterPageInfos = res.pageInfos
                    }
                }
            }
        }
        if index - 1 >= 0 {
            prefetchPrevTask = Task { [weak self] in
                guard let self else { return }
                if let content = try? await APIService.shared.fetchChapterContent(bookUrl: book.bookUrl ?? "", bookSourceUrl: book.origin, index: index - 1) {
                    await MainActor.run {
                        guard self.currentChapterIndex == baseIndex else { return }
                        let processed = applyReplaceRules(to: removeHTMLAndSVG(content))
                        let title = self.chapters[index - 1].title
                        let attr = self.createAttrString(processed, title: title)
                        self.prevChapterStore = TextKit2RenderStore(attributedString: attr, layoutWidth: max(100, view.bounds.width - preferences.pageHorizontalMargin * 2))
                        let res = self.performSilentPagination(for: self.prevChapterStore!, sentences: processed.components(separatedBy: "\n"), title: title)
                        self.prevChapterPages = res.pages
                        self.prevChapterPageInfos = res.pageInfos
                    }
                }
            }
        }
    }

    private func performSilentPagination(for store: TextKit2RenderStore, sentences: [String], title: String) -> TextKit2Paginator.PaginationResult {
        var pS: [Int] = []; var c = title.isEmpty ? 0 : (title + "\n").utf16.count
        for s in sentences { pS.append(c); c += s.count + 1 }
        let pSize = paginationPageSize()
        return TextKit2Paginator.paginate(renderStore: store, pageSize: pSize, paragraphStarts: pS, prefixLen: title.isEmpty ? 0 : (title + "\n").utf16.count, contentInset: paginationContentInset())
    }

    private func createAttrString(_ text: String, title: String) -> NSAttributedString {
        let fullAttr = NSMutableAttributedString()
        if !title.isEmpty { fullAttr.append(NSAttributedString(string: title + "\n", attributes: [.font: UIFont.systemFont(ofSize: preferences.fontSize + 8, weight: .bold), .foregroundColor: UIColor.label])) }
        fullAttr.append(NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: preferences.fontSize), .foregroundColor: UIColor.label, .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineSpacing = preferences.lineSpacing; p.alignment = .justified; return p }() ]))
        return fullAttr
    }

    private func prepareRenderStore() {
        let width = max(100, view.bounds.width - preferences.pageHorizontalMargin * 2)
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        let attrString = createAttrString(contentSentences.joined(separator: "\n"), title: title)
        if let store = renderStore { store.update(attributedString: attrString, layoutWidth: width) } else { renderStore = TextKit2RenderStore(attributedString: attrString, layoutWidth: width) }
        renderStore?.textContainer.lineFragmentPadding = 8 // 解决边缘遮挡
    }
    
    private func performPagination() {
        guard let s = renderStore else { return }
        let title = chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].title : ""
        let prefixLen = title.isEmpty ? 0 : (title + "\n").utf16.count
        var starts: [Int] = []; var curr = prefixLen; for sent in contentSentences { starts.append(curr); curr += sent.count + 1 }
        let pSize = paginationPageSize()
        let res = TextKit2Paginator.paginate(renderStore: s, pageSize: pSize, paragraphStarts: starts, prefixLen: prefixLen, contentInset: paginationContentInset())
        self.pages = res.pages; self.pageInfos = res.pageInfos
    }

    private func setupReaderMode() {
        verticalVC?.view.removeFromSuperview(); verticalVC?.removeFromParent(); verticalVC = nil
        horizontalVC?.view.removeFromSuperview(); horizontalVC?.removeFromParent(); horizontalVC = nil
        mangaScrollView?.removeFromSuperview(); mangaScrollView = nil; mangaStackView = nil
        if isMangaMode { setupMangaMode() }
        else if currentReadingMode == .vertical { setupVerticalMode() }
        else { setupHorizontalMode() }
    }
    
    private func setupVerticalMode() {
        let v = VerticalTextViewController(); v.onVisibleIndexChanged = { [weak self] idx in self?.onProgressChanged?(self?.currentChapterIndex ?? 0, Double(idx) / Double(max(1, self?.contentSentences.count ?? 1))) }
        v.onAddReplaceRule = { [weak self] text in self?.onAddReplaceRuleWithText?(text) }; v.onTapMenu = { [weak self] in self?.onToggleMenu?() }
        addChild(v); view.addSubview(v.view); v.view.frame = view.bounds; v.didMove(toParent: self); v.safeAreaTop = safeAreaTop
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
        let sv = UIScrollView(frame: view.bounds); sv.backgroundColor = .black; sv.contentInsetAdjustmentBehavior = .never
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 0; stack.alignment = .fill; stack.distribution = .fill
        sv.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: sv.contentLayoutGuide.topAnchor, constant: safeAreaTop), stack.bottomAnchor.constraint(equalTo: sv.contentLayoutGuide.bottomAnchor), stack.leadingAnchor.constraint(equalTo: sv.contentLayoutGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: sv.contentLayoutGuide.trailingAnchor), stack.widthAnchor.constraint(equalTo: sv.frameLayoutGuide.widthAnchor), stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)])
        mangaStackView = stack
        for sent in contentSentences where sent.contains("__IMG__") {
            let iv = UIImageView(); iv.contentMode = .scaleAspectFit; iv.clipsToBounds = true; stack.addArrangedSubview(iv)
            let url = sent.replacingOccurrences(of: "__IMG__", with: "").trimmingCharacters(in: .whitespaces)
            Task { if let u = URL(string: url), let (data, _) = try? await URLSession.shared.data(from: u), let img = UIImage(data: data) {
                await MainActor.run { iv.image = img; iv.heightAnchor.constraint(equalTo: iv.widthAnchor, multiplier: img.size.height / img.size.width).isActive = true }
            }}
        }
        view.addSubview(sv); self.mangaScrollView = sv
        sv.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleMangaTap)))
    }
    @objc private func handleMangaTap() { onToggleMenu?() }

    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating f: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed, let visibleVC = pvc.viewControllers?.first as? PageContentViewController {
            self.isInternalTransitioning = true 
            if visibleVC.chapterOffset == 0 {
                self.currentPageIndex = visibleVC.pageIndex; self.currentCharOffset = pages[visibleVC.pageIndex].globalRange.location
                self.onProgressChanged?(currentChapterIndex, Double(visibleVC.pageIndex) / Double(max(1, pages.count)))
            } else {
                if visibleVC.chapterOffset > 0 { prevChapterStore = renderStore; prevChapterPages = pages; prevChapterPageInfos = pageInfos; renderStore = nextChapterStore; pages = nextChapterPages; pageInfos = nextChapterPageInfos; nextChapterStore = nil; nextChapterPages = []; nextChapterPageInfos = [] }
                else { nextChapterStore = renderStore; nextChapterPages = pages; nextChapterPageInfos = pageInfos; renderStore = prevChapterStore; pages = prevChapterPages; pageInfos = prevChapterPageInfos; prevChapterStore = nil; prevChapterPages = []; prevChapterPageInfos = [] }
                self.currentChapterIndex += visibleVC.chapterOffset; self.currentPageIndex = visibleVC.pageIndex; self.currentCharOffset = pages[currentPageIndex].globalRange.location
                self.onProgressChanged?(currentChapterIndex, Double(currentPageIndex) / Double(max(1, pages.count)))
                prefetchAdjacentChapters(index: currentChapterIndex)
            }
            updateProgressUI(); self.isInternalTransitioning = false 
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
    
    private func updateHorizontalPage(to index: Int, animated: Bool, direction: UIPageViewController.NavigationDirection? = nil) {
        guard let h = horizontalVC, index >= 0 && index < pages.count else { return }
        let navDirection = direction ?? (index >= currentPageIndex ? .forward : .reverse)
        currentPageIndex = index
        h.setViewControllers([createPageVC(at: index, offset: 0)], direction: navDirection, animated: animated)
        updateProgressUI()
    }
    
    private func createPageVC(at index: Int, offset: Int) -> PageContentViewController {
        let vc = PageContentViewController(pageIndex: index, chapterOffset: offset); let pageView = ReadContent2View(frame: .zero)
        let activeStore = (offset == 0) ? renderStore : (offset > 0 ? nextChapterStore : prevChapterStore)
        let activeInfos = (offset == 0) ? pageInfos : (offset > 0 ? nextChapterPageInfos : prevChapterPageInfos)
        pageView.renderStore = activeStore
        if index < activeInfos.count {
            pageView.pageInfo = activeInfos[index]
        }
        pageView.onTapLocation = { [weak self] loc in if loc == .middle { self?.onToggleMenu?() } else { self?.handlePageTap(isNext: loc == .right) } }
        vc.view.addSubview(pageView); pageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([pageView.topAnchor.constraint(equalTo: vc.view.topAnchor), pageView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor), pageView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor), pageView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor)])
        return vc
    }
    
    private func handlePageTap(isNext: Bool) {
        let target = isNext ? currentPageIndex + 1 : currentPageIndex - 1
        if target >= 0 && target < pages.count {
            updateHorizontalPage(to: target, animated: true, direction: isNext ? .forward : .reverse)
        } else {
            let nextIndex = isNext ? currentChapterIndex + 1 : currentChapterIndex - 1
            jumpToChapter(nextIndex, startAtEnd: !isNext)
        }
    }

    private func syncHorizontalPageToTTS(sentenceIndex: Int) {
        var curr = 0; var pStarts: [Int] = []
        for s in contentSentences { pStarts.append(curr); curr += s.count + 1 }
        guard sentenceIndex < pStarts.count else { return }
        let offset = pStarts[sentenceIndex]
        if let target = pages.firstIndex(where: { NSLocationInRange(offset, $0.globalRange) }), target != currentPageIndex { updateHorizontalPage(to: target, animated: true) }
    }

    private func removeHTMLAndSVG(_ text: String) -> String {
        var res = text; let patterns = ["<svg[^>]*>.*?</svg>", "<img[^>]*>", "<[^>]+>"]
        for p in patterns { if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators]) { res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: res.utf16.count), withTemplate: "") } }
        return res.replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private func rulesSignature(_ rules: [ReplaceRule]) -> String {
        rules.map {
            "\($0.id ?? "")|\($0.pattern)|\($0.replacement)|\($0.isEnabled ?? false)|\($0.isRegex ?? false)"
        }.joined(separator: ";")
    }

    private func extractMangaImageSentences(from text: String) -> [String] {
        let pattern = "<img[^>]+src=[\"']([^\"']+)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        if matches.isEmpty { return [] }
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return "__IMG__" + nsText.substring(with: match.range(at: 1))
        }
    }

    private func paginationPageSize() -> CGSize {
        CGSize(width: view.bounds.width, height: max(1, view.bounds.height - safeAreaBottom - 40))
    }

    private func paginationContentInset() -> CGFloat {
        contentInset + safeAreaTop
    }
}

class PageContentViewController: UIViewController {
    let pageIndex: Int; let chapterOffset: Int
    init(pageIndex: Int, chapterOffset: Int) { self.pageIndex = pageIndex; self.chapterOffset = chapterOffset; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
}
